import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/hosted_tournament/hosted_tournament_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../domain/models/hosted_tournament.dart';
import '../../../domain/models/team.dart';

/// A list of hosted tournaments: one host's (its Tournaments section,
/// drafts included for its managers) or, with no [hostId], every
/// upcoming one, for finding tournaments to play in or follow.
class HostedTournamentsViewModel extends ChangeNotifier {
  HostedTournamentsViewModel({
    this.hostId,
    required HostedTournamentRepository tournamentRepository,
    TeamRepository? teamRepository,
    required AuthRepository authRepository,
  }) : _repo = tournamentRepository,
       _uid = authRepository.currentUser?.uid ?? '' {
    final id = hostId;
    if (id == null) {
      _listen(_repo.watchUpcoming());
    } else {
      _hostSub = teamRepository?.watchTeam(id).listen((t) {
        _host = t;
        _watchHost();
        _watchEntered();
        notifyListeners();
      }, onError: _onError);
    }
  }

  final String? hostId;
  final HostedTournamentRepository _repo;
  final String _uid;
  StreamSubscription<Team?>? _hostSub;
  StreamSubscription<List<HostedTournament>>? _sub;
  StreamSubscription<List<EnteredTournament>>? _enteredSub;
  List<EnteredTournament> _entered = const [];

  /// Tournaments this team plays in (or has applied to, or been invited
  /// to), for its members. Empty for groups, and for everyone else.
  List<EnteredTournament> get playingIn => [
    for (final e in _entered)
      if (e.isCurrent) e,
  ];

  /// Members of a team see what it plays in; it's private to them.
  void _watchEntered() {
    final id = hostId;
    final t = _host;
    if (id == null || t == null || _enteredSub != null) return;
    if (t.kind != TeamKind.team || !t.members.containsKey(_uid)) return;
    _enteredSub = _repo.watchEnteredBy(id).listen(
      (l) {
        _entered = l;
        notifyListeners();
      },
      // Not being able to see them shouldn't hide the hosted list.
      onError: (Object _) {},
    );
  }

  bool? _watchingAsManager;

  Team? _host;
  List<HostedTournament> _list = const [];
  bool _loaded = false;
  Object? _error;
  String _query = '';
  HostedStatus? _status;

  bool get loaded => _loaded || _error != null;
  Object? get error => _error;
  Team? get host => _host;
  String get query => _query;

  /// The status [tournaments] is narrowed to; null for all.
  HostedStatus? get statusFilter => _status;

  /// How many of the [query]'s matches are in each status, in the order
  /// a tournament goes through them; only statuses some have.
  Map<HostedStatus, int> get statusCounts {
    final counts = <HostedStatus, int>{};
    for (final t in _matching) {
      counts[t.status] = (counts[t.status] ?? 0) + 1;
    }
    return {
      for (final s in HostedStatus.values)
        s: ?counts[s],
    };
  }

  /// Whether there's more than one status to filter by.
  bool get filtersByStatus => statusCounts.length > 1;

  /// Matching [query] (name, host or place) and [statusFilter].
  List<HostedTournament> get tournaments {
    final status = filtersByStatus ? _status : null;
    final matching = _matching;
    if (status == null) return matching;
    return [
      for (final t in matching)
        if (t.status == status) t,
    ];
  }

  /// Matching [query] only.
  List<HostedTournament> get _matching {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _list;
    return [
      for (final t in _list)
        if ('${t.name} ${t.hostName} ${t.location}'.toLowerCase().contains(q))
          t,
    ];
  }

  void setStatusFilter(HostedStatus? status) {
    _status = status;
    notifyListeners();
  }

  /// Members with Manage events host tournaments here.
  bool get canHost => _host?.has(_uid, TeamPermission.manageEvents) ?? false;

  void setQuery(String q) {
    _query = q;
    notifyListeners();
  }

  void _onError(Object e) {
    _error = e;
    _loaded = true;
    notifyListeners();
  }

  /// Drafts are only readable by managers, so the query depends on the
  /// role; re-subscribe when it changes.
  void _watchHost() {
    final id = hostId;
    if (id == null || _host == null) {
      _loaded = true;
      return;
    }
    final manager = canHost;
    if (_watchingAsManager == manager) return;
    _watchingAsManager = manager;
    _listen(_repo.watchHostedBy(id, manager: manager));
  }

  void _listen(Stream<List<HostedTournament>> stream) {
    _sub?.cancel();
    _sub = stream.listen((l) {
      _list = l;
      _loaded = true;
      _error = null;
      notifyListeners();
    }, onError: _onError);
  }

  @override
  void dispose() {
    _hostSub?.cancel();
    _sub?.cancel();
    _enteredSub?.cancel();
    super.dispose();
  }
}
