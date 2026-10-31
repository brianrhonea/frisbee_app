import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/ranking/ranking_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../data/repositories/usau_team/usau_team_repository.dart';
import '../../../domain/models/ranking.dart';
import '../../../domain/models/roster_player.dart';
import '../../../domain/models/roster_sync.dart';
import '../../../domain/models/team.dart';
import '../../../domain/models/usau_team.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

typedef UsauLink = ({String url, String name});

/// A ranked USA Ultimate team that could be this team.
typedef UsauCandidate = ({RankingEntry entry, String division});

/// Links a team to its USA Ultimate page and syncs the roster from it.
class UsauRosterViewModel extends ChangeNotifier {
  UsauRosterViewModel({
    required this.teamId,
    required TeamRepository teamRepository,
    required UsauTeamRepository usauTeamRepository,
    required RankingRepository rankingRepository,
    required AuthRepository authRepository,
  }) : _teams = teamRepository,
       _usau = usauTeamRepository,
       _rankings = rankingRepository,
       _auth = authRepository {
    link = Command1<void, UsauLink>(
      (l) => switch (parseLink(l.url)) {
        null => Future.value(
          Result.error(Exception('That isn’t a USA Ultimate team page link.')),
        ),
        final url => _teams.linkUsauTeam(teamId, url: url, name: l.name),
      },
    );
    unlink = Command0<void>(() => _teams.linkUsauTeam(teamId));
    load = Command0<UsauTeam>(_load)..addListener(notifyListeners);
    apply = Command0<void>(_apply);
    _subs = [
      _teams.watchTeam(teamId).listen((t) {
        final urlChanged = t?.usauUrl != _team?.usauUrl;
        _team = t;
        _teamLoaded = true;
        if (t?.usauUrl == null) {
          _startSearch();
        } else if (urlChanged) {
          load.execute();
        }
        notifyListeners();
      }, onError: _onError),
      _teams.watchRoster(teamId).listen((r) {
        _roster = r;
        notifyListeners();
      }, onError: _onError),
    ];
  }

  final String teamId;
  final TeamRepository _teams;
  final UsauTeamRepository _usau;
  final RankingRepository _rankings;
  final AuthRepository _auth;
  late final List<StreamSubscription<Object?>> _subs;
  StreamSubscription<List<RankingDivision>>? _rankingSub;

  late final Command1<void, UsauLink> link;
  late final Command0<void> unlink;

  /// Fetches the linked USA Ultimate page.
  late final Command0<UsauTeam> load;

  /// Writes [plan] to the roster.
  late final Command0<void> apply;

  Team? _team;
  Team? get team => _team;
  bool _teamLoaded = false;
  bool get loaded => _teamLoaded || _error != null;

  List<RosterPlayer> _roster = const [];

  Object? _error;
  Object? get error => _error;

  bool get canEdit => _team?.canEdit(_auth.currentUser?.uid ?? '') ?? false;
  bool get linked => _team?.usauUrl != null;

  // ---- Finding the team ---------------------------------------------------

  List<RankingDivision> _divisions = const [];
  bool _searchDone = false;
  Object? _searchError;

  /// Rankings still loading; results fill in as divisions arrive.
  bool get searching => _rankingSub != null && !_searchDone;
  Object? get searchError => _searchError;

  String _query = '';
  String get query => _query;

  void setQuery(String q) {
    _query = q;
    notifyListeners();
  }

  void _startSearch() {
    if (_rankingSub != null) return;
    if (_query.isEmpty) _query = _team?.name ?? '';
    _rankingSub = _rankings.watchDivisions().listen(
      (d) {
        _divisions = d;
        notifyListeners();
      },
      onError: (Object e) {
        _searchError = e;
        notifyListeners();
      },
      onDone: () {
        _searchDone = true;
        notifyListeners();
      },
    );
  }

  /// Ranked teams whose name contains the query, exact names and the
  /// team's own level and division first.
  List<UsauCandidate> get candidates {
    final q = normalizeName(_query);
    if (q.isEmpty) return const [];
    final team = _team;
    int score(UsauCandidate c) {
      final name = normalizeName(c.entry.teamName);
      final label = c.division.toLowerCase();
      var s = name == q ? 0 : 10;
      if (team != null && !label.contains(team.level.label.toLowerCase())) {
        s += 2;
      }
      if (team != null && !label.contains(_usauDivision(team.division))) {
        s += 1;
      }
      return s;
    }

    final found = [
      for (final d in _divisions)
        for (final e in d.entries)
          if (e.teamUrl.isNotEmpty && normalizeName(e.teamName).contains(q))
            (entry: e, division: d.label),
    ]..sort((a, b) => score(a).compareTo(score(b)));
    return found.take(30).toList();
  }

  static String _usauDivision(Division d) => switch (d) {
    Division.open => 'men',
    Division.women => 'women',
    Division.mixed => 'mixed',
    Division.masters => 'masters',
  };

  /// A pasted team page link, or null if it isn't one.
  static String? parseLink(String text) {
    final uri = Uri.tryParse(text.trim());
    if (uri == null ||
        uri.host != 'play.usaultimate.org' ||
        !uri.path.toLowerCase().startsWith('/teams/events/eventteam') ||
        (uri.queryParameters['TeamId'] ?? '').isEmpty) {
      return null;
    }
    return Uri.https(uri.host, '/teams/events/Eventteam/', {
      'TeamId': uri.queryParameters['TeamId']!,
    }).toString();
  }

  // ---- Syncing ------------------------------------------------------------

  UsauTeam? get usauTeam => switch (load.result) {
    Ok(:final value) => value,
    _ => null,
  };

  Object? get loadError => switch (load.result) {
    Error(:final error) => error,
    _ => null,
  };

  /// New USA Ultimate players the admin chose not to add.
  final Set<String> _skipped = {};

  bool isSkipped(RosterPlayer added) => _skipped.contains(added.name);

  void toggleSkip(RosterPlayer added) {
    if (!_skipped.remove(added.name)) _skipped.add(added.name);
    notifyListeners();
  }

  RosterSyncPlan? get plan {
    final usau = usauTeam;
    return usau == null ? null : RosterSyncPlan.build(_roster, usau.roster);
  }

  List<RosterPlayer> get _writes => [
    for (final p in plan?.writes ?? const <RosterPlayer>[])
      if (!(p.id.isEmpty && _skipped.contains(p.name))) p,
  ];

  /// Changes Apply would make, counting the sync stamp as nothing.
  int get pendingWrites => _writes.length;

  Future<Result<UsauTeam>> _load() async {
    final url = _team?.usauUrl;
    if (url == null) return Result.error(Exception('No USA Ultimate link'));
    final result = await _usau.getTeam(url);
    // Fill in the name for links pasted before the page was read.
    if (result case Ok(
      :final value,
    ) when value.name.isNotEmpty && _team?.usauName != value.name) {
      unawaited(_teams.linkUsauTeam(teamId, url: url, name: value.name));
    }
    return result;
  }

  Future<Result<void>> _apply() async {
    if (plan == null) return Result.error(Exception('Roster not loaded'));
    return _teams.applyRosterSync(teamId, _writes);
  }

  void _onError(Object e) {
    _error = e;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _rankingSub?.cancel();
    load.removeListener(notifyListeners);
    super.dispose();
  }
}
