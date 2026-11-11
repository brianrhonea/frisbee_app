import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/hosted_tournament/hosted_tournament_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../domain/models/hosted_tournament.dart';
import '../../../domain/models/live_draft.dart';
import '../../../domain/models/team.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// The captains' draft board for one division. The host picks captains and
/// starts it; then the captains take turns picking players in snake order
/// while everyone in the division watches. Every change goes through the
/// server, which checks whose turn it is, so this only reflects the board
/// and asks.
///
/// Skill and gender are private: [details] is null unless the user is the
/// host or one of the captains.
class LiveDraftViewModel extends ChangeNotifier {
  LiveDraftViewModel({
    required this.tournamentId,
    required this.divisionId,
    required HostedTournamentRepository tournamentRepository,
    required TeamRepository teamRepository,
    required AuthRepository authRepository,
    DateTime Function()? now,
  }) : _repo = tournamentRepository,
       _teams = teamRepository,
       _uid = authRepository.currentUser?.uid ?? '',
       _now = now ?? DateTime.now {
    start = Command0<void>(_start);
    pick = Command1<void, String>(_pick);
    control = Command1<void, DraftControl>(_control);
    finish = Command0<void>(_finish);
    _subs = [
      _repo.watchTournament(tournamentId).listen((t) {
        final hostChanged = t?.hostId != _tournament?.hostId;
        _tournament = t;
        if (hostChanged && t != null) _watchHost(t.hostId);
        notifyListeners();
      }, onError: _onError),
      _repo.watchDivisions(tournamentId).listen((all) {
        _division = all.where((x) => x.id == divisionId).firstOrNull;
        _loaded = true;
        notifyListeners();
      }, onError: _onError),
      _repo.watchDraft(tournamentId, divisionId).listen((d) {
        _draft = d;
        _drafts = true;
        notifyListeners();
      }, onError: _onError),
      _repo.watchDraftDetails(tournamentId, divisionId).listen((d) {
        _details = d;
        notifyListeners();
      }, onError: (Object _) {}),
    ];
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_draft?.secondsLeft(_now()) != null) notifyListeners();
    });
  }

  final String tournamentId;
  final String divisionId;
  final HostedTournamentRepository _repo;
  final TeamRepository _teams;
  final String _uid;
  final DateTime Function() _now;
  late final List<StreamSubscription<Object?>> _subs;
  StreamSubscription<Team?>? _hostSub;
  StreamSubscription<List<PlayerSignup>>? _signupsSub;
  Timer? _timer;

  late final Command0<void> start;
  late final Command1<void, String> pick;
  late final Command1<void, DraftControl> control;
  late final Command0<void> finish;

  List<Command<void>> get commands => [start, pick, control, finish];

  HostedTournament? _tournament;
  TournamentDivision? _division;
  Team? _host;
  LiveDraft? _draft;
  Map<String, DraftDetail>? _details;
  List<PlayerSignup> _signups = const [];
  bool _loaded = false;
  bool _drafts = false;
  Object? _error;

  // Setup.
  final Set<String> _chosen = {};
  int _pickSeconds = 90;

  // The pool's view.
  bool _bySkill = false;
  GenderMatch? _genderFilter;

  bool get loaded => (_loaded && _drafts) || _error != null;
  Object? get error => _error;
  HostedTournament? get tournament => _tournament;
  TournamentDivision? get division => _division;
  LiveDraft? get draft => _draft;
  String get uid => _uid;

  bool get isManager => _host?.has(_uid, TeamPermission.manageEvents) ?? false;

  bool get isCaptain => _draft?.captains.any((c) => c.uid == _uid) ?? false;

  /// Skill and gender, for the host and the captains; null for everyone
  /// else.
  Map<String, DraftDetail>? get details => _details;

  /// The host's accepted players in this division, who can be captains.
  List<PlayerSignup> get accepted => [
    for (final s in _signups)
      if (s.divisionId == divisionId && s.status == SignupStatus.accepted) s,
  ];

  /// The draft can't be started or finished once the real teams are made
  /// or the schedule is out.
  bool get locked => _division?.teamsCreated ?? false;

  bool get mixed => _division?.division == Division.mixed;

  void _onError(Object e) {
    _error = e;
    notifyListeners();
  }

  void _watchHost(String hostId) {
    _hostSub?.cancel();
    _hostSub = _teams.watchTeam(hostId).listen((h) {
      final was = isManager;
      _host = h;
      if (isManager != was) _watchSignups();
      notifyListeners();
    }, onError: (Object _) {});
  }

  void _watchSignups() {
    _signupsSub?.cancel();
    _signupsSub = null;
    if (!isManager) {
      _signups = const [];
      return;
    }
    _signupsSub = _repo.watchSignups(tournamentId).listen((s) {
      _signups = s;
      notifyListeners();
    }, onError: (Object _) {});
  }

  // ---- Setup --------------------------------------------------------------

  Set<String> get chosen => Set.unmodifiable(_chosen);
  int get pickSeconds => _pickSeconds;

  static const minCaptains = 2;
  static const maxCaptains = 16;

  void toggleCaptain(String uid) {
    if (!_chosen.remove(uid) && _chosen.length < maxCaptains) _chosen.add(uid);
    notifyListeners();
  }

  void setPickSeconds(int seconds) {
    _pickSeconds = seconds.clamp(0, 600);
    notifyListeners();
  }

  /// Why the draft can't start yet, or null.
  String? get startProblem {
    if (_chosen.length < minCaptains) {
      return 'Choose at least $minCaptains captains.';
    }
    if (accepted.length - _chosen.length < _chosen.length) {
      return 'There are not enough players for every captain to pick.';
    }
    if (locked) return 'The teams have already been created.';
    return null;
  }

  Future<Result<void>> _start() async {
    final problem = startProblem;
    if (problem != null) return Result.error(Exception(problem));
    final r = await _repo.startDraft(
      tournamentId,
      divisionId,
      _chosen.toList(),
      pickSeconds: _pickSeconds,
    );
    _chosen.clear();
    notifyListeners();
    return r;
  }

  // ---- The board ----------------------------------------------------------

  /// Whether the user can pick now: they're on the clock, or the host.
  bool get isMyTurn =>
      _draft?.running == true && _draft?.onTheClock == _uid && isCaptain;

  bool get canPick => _draft?.running == true && (isMyTurn || isManager);

  String? get onClockName {
    final d = _draft;
    final c = d?.onTheClock;
    return c == null ? null : d!.nameOf(c);
  }

  int? get secondsLeft => _draft?.secondsLeft(_now());

  /// The host can step in once a captain's time is up.
  bool get timeUp => secondsLeft == 0;

  bool get bySkill => _bySkill && _details != null;
  GenderMatch? get genderFilter => _genderFilter;

  void setBySkill(bool v) {
    _bySkill = v;
    notifyListeners();
  }

  void setGenderFilter(GenderMatch? g) {
    _genderFilter = g;
    notifyListeners();
  }

  /// Players left to pick: by name, or best first when [bySkill], and
  /// narrowed to [genderFilter].
  List<MapEntry<String, String>> get pool {
    final d = _draft;
    if (d == null) return const [];
    final list = [
      for (final e in d.available)
        if (_genderFilter == null || _details?[e.key]?.gender == _genderFilter)
          e,
    ];
    if (bySkill) {
      list.sort((a, b) {
        final bySkill =
            (_details![b.key]?.skill ?? 0) - (_details![a.key]?.skill ?? 0);
        return bySkill != 0 ? bySkill : a.value.compareTo(b.value);
      });
    }
    return list;
  }

  Future<Result<void>> _pick(String uid) =>
      _repo.draftPick(tournamentId, divisionId, uid);

  Future<Result<void>> _control(DraftControl action) =>
      _repo.draftControl(tournamentId, divisionId, action);

  Future<Result<void>> _finish() => _repo.finishDraft(tournamentId, divisionId);

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _hostSub?.cancel();
    _signupsSub?.cancel();
    _timer?.cancel();
    super.dispose();
  }
}
