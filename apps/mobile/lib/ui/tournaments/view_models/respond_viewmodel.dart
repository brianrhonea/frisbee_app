import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/hosted_tournament/hosted_tournament_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../domain/models/hosted_tournament.dart';
import '../../../domain/models/roster_player.dart';
import '../../../domain/models/team.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// What the respond flow is for, settled when it opens.
enum RespondMode {
  /// The host invited the team: Accept or Decline.
  invite,

  /// A public event: Apply.
  apply,

  /// An entered team's next steps (roster, payment) or its captains.
  entered,
}

enum RespondStep { respond, roster, pay, done, declined }

/// The respond flow (`/tournaments/:id/respond?team=&step=`; the website's
/// EnterTeam), a step at a time:
///
/// 1. Respond: an invite's Accept or Decline (or Apply), with the team,
///    division and captains. Accepting an invite puts the team straight in
///    (or on the waitlist when the division is full).
/// 2. Roster: the players the team brings, or set it later (by the
///    deadline).
/// 3. Payment: pay now in the app's payment sheet, or later.
/// 4. Done: "Request confirmed!" (or "Request sent!" while the host
///    decides), with what's left.
///
/// What it's for ([mode]) and whether the user may do it ([blocked]) are
/// decided once everything has loaded: the flow's own writes change the
/// entry, and mustn't swap the screen out from under it. Every rule is the
/// API's; this only offers what the API takes.
class RespondViewModel extends ChangeNotifier {
  RespondViewModel({
    required this.tournamentId,
    String? teamId,
    String? step,
    required HostedTournamentRepository tournamentRepository,
    required TeamRepository teamRepository,
    required AuthRepository authRepository,
    DateTime Function()? now,
  }) : _repo = tournamentRepository,
       _teams = teamRepository,
       _uid = authRepository.currentUser?.uid ?? '',
       _askedTeam = teamId,
       _askedStep = step,
       _now = now ?? DateTime.now {
    respond = Command0(_respond);
    decline = Command0(_decline);
    saveRoster = Command0(_saveRoster);
    _subs = [
      _repo.watchTournament(tournamentId).listen((t) {
        _tournament = t;
        _tournamentIn = true;
        _settle();
      }, onError: _onError),
      _repo.watchDivisions(tournamentId).listen((d) {
        _divisions = d;
        _divisionsIn = true;
        _settle();
      }, onError: _onError),
      _repo.watchEntries(tournamentId).listen((e) {
        _entries = e;
        _entriesIn = true;
        _settle();
      }, onError: _onError),
      if (_uid.isNotEmpty)
        _teams.watchMyTeams(_uid).listen((teams) {
          _myTeams = teams;
          _teamsIn = true;
          _settle();
        }, onError: _onError),
    ];
    if (_uid.isEmpty) _teamsIn = true;
  }

  final String tournamentId;
  final HostedTournamentRepository _repo;
  final TeamRepository _teams;
  final String _uid;
  final String? _askedTeam;
  final String? _askedStep;
  final DateTime Function() _now;
  late final List<StreamSubscription<Object?>> _subs;
  StreamSubscription<List<RosterPlayer>>? _rosterSub;
  StreamSubscription<EntryPayment?>? _paymentSub;

  /// Accept / Apply / Save and continue (the first step).
  late final Command0<void> respond;

  /// Declines the invite (the entry is withdrawn, reason "declined").
  late final Command0<void> decline;

  /// Saves the roster and moves on.
  late final Command0<void> saveRoster;

  HostedTournament? _tournament;
  List<TournamentDivision> _divisions = const [];
  List<TournamentEntry> _entries = const [];
  List<Team> _myTeams = const [];
  bool _tournamentIn = false;
  bool _divisionsIn = false;
  bool _entriesIn = false;
  bool _teamsIn = false;
  String? _error;

  // Settled once loaded.
  bool _settled = false;
  RespondMode _mode = RespondMode.apply;
  String? _blocked;

  RespondStep _step = RespondStep.respond;
  String? _teamId;
  String? _divisionId;
  Set<String> _captains = {};
  EntryStatus? _answer;

  List<RosterPlayer>? _players;
  Set<String> _picked = {};
  bool _pickedTouched = false;
  EntryPayment? _payment;
  bool _paymentIn = false;

  String get uid => _uid;
  bool get loaded => _settled || _error != null;
  String? get error => _error;
  HostedTournament? get tournament => _tournament;
  List<TournamentDivision> get divisions => _divisions;
  RespondMode get mode => _mode;

  /// Why the user can't go on, or null.
  String? get blocked => _blocked;
  RespondStep get step => _step;
  String? get teamId => _teamId;
  String? get divisionId => _divisionId;
  Set<String> get captains => _captains;
  List<RosterPlayer>? get players => _players;
  Set<String> get picked => _picked;

  /// The entry now (after this flow's own writes).
  TournamentEntry? get entry =>
      _entries.where((e) => e.teamId == _teamId).firstOrNull;

  /// What the respond step answered, or the entry's status.
  EntryStatus get status => _answer ?? entry?.status ?? EntryStatus.applied;

  Team? get team => _myTeams.where((t) => t.id == _teamId).firstOrNull;

  /// The user's teams they can enter with (admins of team-kind teams).
  List<Team> get adminTeams => [
    for (final t in _myTeams)
      if (t.kind == TeamKind.team && t.has(_uid, TeamPermission.manageTeam)) t,
  ];

  /// Admin teams that haven't entered yet (or withdrew).
  List<Team> get teamsToEnter => [
    for (final t in adminTeams)
      if (!_entries.any(
        (e) =>
            e.teamId == t.id &&
            e.status != EntryStatus.withdrawn &&
            e.status != EntryStatus.declined,
      ))
        t,
  ];

  /// The team a new entry can't be picked from once it's fixed (an
  /// invite, or an entered team).
  bool get teamFixed => _mode != RespondMode.apply || _askedTeam != null;

  TournamentDivision? get division => _divisions
      .where((d) => d.id == (entry?.divisionId ?? _divisionId))
      .firstOrNull;

  BidFee? get fee => _tournament?.feeFor(_teamId);
  bool get owes => (fee?.amountCents ?? 0) > 0;
  DateTime? get deadline => _tournament?.effectiveDeadline;

  /// Players' events where teams reserve spots don't name a roster here.
  bool get mixed => _tournament?.mixedEntry ?? false;
  int get minRoster => mixed
      ? 0
      : (division?.effectiveMinRoster ?? TournamentDivision.defaultMinRoster);

  /// The steps shown in the bar (Payment only with a fee).
  List<RespondStep> get steps => [
    RespondStep.respond,
    if (!mixed) RespondStep.roster,
    if (owes) RespondStep.pay,
  ];

  bool get locked =>
      _tournament?.status == HostedStatus.live ||
      _tournament?.status == HostedStatus.finished;

  bool get paid => _payment?.paid == true;
  bool get paymentKnown => !owes || _paymentIn;

  EntryChecklist get checklist => EntryChecklist.of(
    status: status.name,
    rosterSize: mixed ? null : (entry?.roster.length ?? 0),
    minRoster: minRoster,
    paid: paid,
    owes: owes,
    deadline: deadline,
    now: _now(),
  );

  bool get canRespond =>
      _teamId != null && _divisionId != null && _captains.isNotEmpty;

  void _onError(Object e) {
    _error ??= "Couldn't load the event. Check your connection and try again.";
    notifyListeners();
  }

  /// Decides [mode] and [blocked] once everything is in.
  void _settle() {
    if (!_settled && _tournamentIn && _divisionsIn && _entriesIn && _teamsIn) {
      _settled = true;
      _decide();
    }
    notifyListeners();
  }

  void _decide() {
    final t = _tournament;
    if (t == null) {
      _blocked =
          "This event isn't here: it may have been removed, or it hasn't "
          'been published yet.';
      return;
    }
    final asked = _askedTeam;
    final e = asked == null
        ? null
        : _entries.where((x) => x.teamId == asked).firstOrNull;
    _mode = e?.status == EntryStatus.invited
        ? RespondMode.invite
        : e != null &&
              e.status != EntryStatus.withdrawn &&
              e.status != EntryStatus.declined
        ? RespondMode.entered
        : RespondMode.apply;
    final admin = asked == null
        ? null
        : adminTeams.where((x) => x.id == asked).firstOrNull;
    final myActive = _entries
        .where(
          (x) =>
              _myTeams.any((m) => m.id == x.teamId) &&
              (x.status == EntryStatus.applied ||
                  x.status == EntryStatus.accepted ||
                  x.status == EntryStatus.waitlisted),
        )
        .firstOrNull;
    if (_mode == RespondMode.apply) {
      _blocked = t.status != HostedStatus.registration
          ? "Registration isn't open."
          : t.visibility != TournamentVisibility.public
          ? "Teams play here by the host's invitation."
          : _divisions.isEmpty
          ? 'The host is still setting up divisions.'
          : myActive != null && myActive.teamId != asked
          ? '${myActive.teamName} is already entered here.'
          : teamsToEnter.isEmpty
          ? "None of the teams you run can enter: you need to be an owner "
                "or admin of a team that hasn't entered."
          : null;
    } else if (admin == null && !(e?.captainIds.contains(_uid) ?? false)) {
      _blocked = "Only the team's admins and captains can change its entry.";
    } else if (_mode == RespondMode.invite && e!.isExpired(_now())) {
      _blocked = TournamentEntry.expiredMessage;
    }
    if (_blocked != null) return;

    final first = asked ?? teamsToEnter.firstOrNull?.id;
    _pickTeam(first, mine: e);
    _step = _mode == RespondMode.entered ? _firstStep(e!) : RespondStep.respond;
  }

  /// Where an entered team picks up: the asked-for step, else the first
  /// thing still to do.
  RespondStep _firstStep(TournamentEntry e) {
    switch (_askedStep) {
      case 'roster':
        return RespondStep.roster;
      case 'pay':
        return owes ? RespondStep.pay : RespondStep.done;
      case 'captains':
        return RespondStep.respond;
    }
    if (!mixed && e.roster.length < minRoster) return RespondStep.roster;
    return owes ? RespondStep.pay : RespondStep.done;
  }

  void _pickTeam(String? id, {TournamentEntry? mine}) {
    _teamId = id;
    final t = team;
    _divisionId =
        mine?.divisionId ??
        _divisions
            .where(
              (d) =>
                  t != null && d.division == t.division && d.level == t.level,
            )
            .firstOrNull
            ?.id ??
        _divisions.firstOrNull?.id;
    _captains = mine != null && _mode == RespondMode.entered
        ? {...mine.captainIds}
        : {if (_uid.isNotEmpty) _uid};
    _watchTeam();
  }

  void _watchTeam() {
    _rosterSub?.cancel();
    _paymentSub?.cancel();
    _players = null;
    _paymentIn = false;
    final id = _teamId;
    if (id == null) return;
    _rosterSub = _teams
        .watchRoster(id)
        .listen(
          (p) {
            _players = p;
            // A first roster starts with everyone ticked.
            if (!_pickedTouched) {
              final saved = entry?.roster ?? const [];
              _picked = saved.isNotEmpty
                  ? {...saved}
                  : {for (final x in p.take(TournamentEntry.maxRoster)) x.id};
            }
            notifyListeners();
          },
          onError: (Object _) {
            _players = const [];
            notifyListeners();
          },
        );
    _paymentSub = _repo
        .watchPayment(tournamentId, id)
        .listen(
          (p) {
            _payment = p;
            _paymentIn = true;
            notifyListeners();
          },
          onError: (Object _) {
            _paymentIn = true;
            notifyListeners();
          },
        );
  }

  void selectTeam(String id) {
    if (teamFixed || id == _teamId) return;
    _pickTeam(id);
    notifyListeners();
  }

  void selectDivision(String id) {
    _divisionId = id;
    notifyListeners();
  }

  void toggleCaptain(String uid, bool on) {
    if (on && _captains.length >= TournamentEntry.maxCaptains) return;
    _captains = {..._captains};
    on ? _captains.add(uid) : _captains.remove(uid);
    notifyListeners();
  }

  void togglePlayer(String id, bool on) {
    _pickedTouched = true;
    _picked = {..._picked};
    if (on && _picked.length < TournamentEntry.maxRoster) {
      _picked.add(id);
    } else {
      _picked.remove(id);
    }
    notifyListeners();
  }

  void pickEveryone(bool on) {
    _pickedTouched = true;
    _picked = on
        ? {
            for (final p in (_players ?? const <RosterPlayer>[]).take(
              TournamentEntry.maxRoster,
            ))
              p.id,
          }
        : {};
    notifyListeners();
  }

  /// Moves on from [from] (Set later, Pay later, Continue).
  void next(RespondStep from) {
    _step = switch (from) {
      RespondStep.respond when !mixed => RespondStep.roster,
      RespondStep.respond ||
      RespondStep.roster => owes ? RespondStep.pay : RespondStep.done,
      _ => RespondStep.done,
    };
    notifyListeners();
  }

  /// Back to a step from Done's checklist.
  void goTo(RespondStep step) {
    _step = step;
    notifyListeners();
  }

  Future<Result<void>> _respond() async {
    final team = _teamId;
    final div = _divisionId;
    if (team == null || div == null || _captains.isEmpty) {
      return Result.error(Exception('Pick the team, division and captains.'));
    }
    final r = await _repo.respond(
      tournamentId,
      team,
      divisionId: div,
      captainIds: _captains.toList(),
    );
    switch (r) {
      case Ok(:final value):
        _answer = value;
        next(RespondStep.respond);
        return const Result.ok(null);
      case Error(:final error):
        return Result.error(error);
    }
  }

  Future<Result<void>> _decline() async {
    final team = _teamId;
    if (team == null) return Result.error(Exception('No team.'));
    final r = await _repo.declineInvite(tournamentId, team);
    if (r is Ok) {
      _step = RespondStep.declined;
      notifyListeners();
    }
    return r;
  }

  Future<Result<void>> _saveRoster() async {
    final team = _teamId;
    if (team == null) return Result.error(Exception('No team.'));
    final r = await _repo.saveRoster(tournamentId, team, _picked.toList());
    if (r is Ok) next(RespondStep.roster);
    return r;
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _rosterSub?.cancel();
    _paymentSub?.cancel();
    super.dispose();
  }
}
