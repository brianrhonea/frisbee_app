import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/hosted_tournament/hosted_tournament_repository.dart';
import '../../../domain/models/group_tournament.dart';
import '../../../domain/models/hosted_tournament.dart';
import '../../../domain/models/team.dart';
import '../../../domain/tournament_engine/team_builder.dart' as engine;
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// The host turns a division's accepted players into teams: the app deals
/// balanced teams from skill (and gender match in mixed divisions), then
/// the host moves players, renames teams and picks captains before saving.
/// Saving writes the division's teams and seeds, so the schedule can be
/// published, exactly as it would with teams that applied.
class TeamDraftViewModel extends ChangeNotifier {
  TeamDraftViewModel({
    required this.tournamentId,
    required this.divisionId,
    required HostedTournamentRepository tournamentRepository,
    int? seed,
  }) : _repo = tournamentRepository,
       _seed = seed ?? DateTime.now().millisecondsSinceEpoch & 0xffff {
    draft = Command0<void>(_draft);
    reshuffle = Command0<void>(_reshuffle);
    save = Command0<void>(_save);
    _subs = [
      _repo.watchTournament(tournamentId).listen((t) {
        _tournament = t;
        notifyListeners();
      }, onError: _onError),
      _repo.watchDivisions(tournamentId).listen((all) {
        final d = all.where((x) => x.id == divisionId).firstOrNull;
        _division = d;
        // Start from the saved teams until the host edits.
        if (d != null && !_started) {
          _started = true;
          _teams = d.teams;
          _teamCount = d.teams.isNotEmpty ? d.teams.length : null;
        }
        _loaded = true;
        notifyListeners();
      }, onError: _onError),
      _repo.watchSignups(tournamentId).listen((s) {
        _signups = s;
        notifyListeners();
      }, onError: _onError),
      _repo.watchGames(tournamentId, divisionId).listen((g) {
        _locked = g.isNotEmpty;
        notifyListeners();
      }, onError: (Object _) {}),
    ];
  }

  final String tournamentId;
  final String divisionId;
  final HostedTournamentRepository _repo;
  late final List<StreamSubscription<Object?>> _subs;

  HostedTournament? _tournament;
  TournamentDivision? _division;
  List<PlayerSignup> _signups = const [];
  List<TournamentTeam> _teams = const [];
  int? _teamCount;
  int _seed;
  bool _started = false;
  bool _loaded = false;
  bool _locked = false;
  bool _dirty = false;
  Object? _error;

  late final Command0<void> draft;
  late final Command0<void> reshuffle;
  late final Command0<void> save;

  List<Command<void>> get commands => [draft, reshuffle, save];

  bool get loaded => _loaded || _error != null;
  Object? get error => _error;
  HostedTournament? get tournament => _tournament;
  TournamentDivision? get division => _division;

  /// Once the schedule is published its games refer to the teams, so teams
  /// can't be added, removed or dealt again, but players can still move,
  /// teams can be renamed and captains changed.
  bool get locked => _locked;

  /// A league has made real teams from these: rosters live on those teams
  /// now, so nothing here can change.
  bool get created => _division?.teamsCreated ?? false;

  /// Unsaved changes.
  bool get dirty => _dirty;

  /// Mixed divisions balance each gender match across the teams.
  bool get mixed => _division?.division == Division.mixed;

  /// The captains drafted these teams live, so dealing balanced teams
  /// would throw their picks away; the host only adjusts them here.
  bool get fromCaptains =>
      _tournament?.draftMode == DraftMode.captains &&
      (_division?.teams.isNotEmpty ?? false);

  List<TournamentTeam> get teams => _teams;

  /// The accepted players, who get drafted.
  List<PlayerSignup> get players => [
    for (final s in _signups)
      if (s.divisionId == divisionId && s.status == SignupStatus.accepted) s,
  ];

  PlayerSignup? signupOf(String uid) =>
      _signups.where((s) => s.uid == uid).firstOrNull;

  Set<String> get _placed => {for (final t in _teams) ...t.playerIds};

  /// Accepted players not on a team yet.
  List<PlayerSignup> get unassigned => [
    for (final p in players)
      if (!_placed.contains(p.uid)) p,
  ];

  /// People on a team who are no longer accepted (they withdrew or were
  /// declined since the draft).
  List<String> get staleIds {
    final accepted = {for (final p in players) p.uid};
    return [
      for (final t in _teams)
        for (final id in t.playerIds)
          if (!accepted.contains(id)) id,
    ];
  }

  /// A team's total self-rated skill, to show how even they are.
  int skillOf(TournamentTeam t) => [
    for (final id in t.playerIds) signupOf(id)?.skill ?? 0,
  ].fold(0, (a, b) => a + b);

  /// Teams to start with: players per team around one and a half times a
  /// field, e.g. 10 or 11 for 7v7 and 6 for 4v4.
  int get suggestedTeamCount {
    final d = _division;
    if (d == null) return 2;
    final perTeam = (d.settings.playersOnField * 1.5).round();
    return (players.length / perTeam).round().clamp(2, d.maxTeams);
  }

  /// How many teams the next deal makes (or the saved teams have).
  int get teamCount =>
      _teamCount ?? (_teams.isNotEmpty ? _teams.length : suggestedTeamCount);
  int get maxTeams => _division?.maxTeams ?? 2;

  void _onError(Object e) {
    _error = e;
    notifyListeners();
  }

  void _set(List<TournamentTeam> teams) {
    if (created) return;
    _teams = teams;
    _dirty = true;
    notifyListeners();
  }

  // ---- Editing ------------------------------------------------------------

  /// Sets how many teams to draft into. Teams that go away drop their
  /// players back to unassigned.
  void setTeamCount(int count) {
    if (_locked || created) return;
    final n = count.clamp(2, maxTeams).toInt();
    _teamCount = n;
    if (n > _teams.length) {
      _set([
        ..._teams,
        ...engine.blankTeams(n - _teams.length, existing: _teams),
      ]);
    } else if (n < _teams.length) {
      _set(_teams.take(n).toList());
    } else {
      notifyListeners();
    }
  }

  void rename(String teamId, String name) => _set([
    for (final t in _teams)
      if (t.id == teamId) t.copyWith(name: name) else t,
  ]);

  void setCaptain(String teamId, String uid) => _set([
    for (final t in _teams)
      if (t.id == teamId && t.playerIds.contains(uid))
        t.copyWith(captainId: () => uid)
      else
        t,
  ]);

  /// Moves a player onto a team, or back to unassigned when [teamId] is
  /// null.
  void movePlayer(String uid, {required String? teamId}) {
    final p = signupOf(uid);
    if (p == null && !_placed.contains(uid)) return;
    final name =
        p?.name ??
        _teams.map((t) => t.playerNames[uid]).whereType<String>().firstOrNull ??
        'Player';
    _set(engine.movePlayer(_teams, (uid: uid, name: name), teamId: teamId));
  }

  /// Drops people who are on a team but no longer accepted.
  void removeStale() {
    final stale = staleIds.toSet();
    if (stale.isEmpty) return;
    var next = _teams;
    for (final id in stale) {
      next = engine.movePlayer(next, (uid: id, name: ''), teamId: null);
    }
    _set(next);
  }

  // ---- Commands -----------------------------------------------------------

  List<engine.DraftPlayer> get _draftPlayers => [
    for (final p in players)
      (uid: p.uid, name: p.name, skill: p.skill, gender: p.gender),
  ];

  Future<Result<void>> _draft() async {
    if (fromCaptains) {
      return Result.error(
        Exception("The captains drafted these teams. Adjust them instead."),
      );
    }
    if (created) return Result.error(Exception(_createdMessage));
    if (_locked) {
      return Result.error(
        Exception('The schedule is published, so teams can only be adjusted.'),
      );
    }
    final count = _teamCount ?? suggestedTeamCount;
    if (players.length < 2) {
      return Result.error(Exception('Accept at least two players first.'));
    }
    final base = _teams.length == count
        ? _teams
        : [
            ..._teams.take(count),
            if (count > _teams.length)
              ...engine.blankTeams(count - _teams.length, existing: _teams),
          ];
    _teamCount = count;
    _set(engine.balancedDraft(_draftPlayers, base, seed: _seed, mixed: mixed));
    return const Result.ok(null);
  }

  /// Deals again with a new seed.
  Future<Result<void>> _reshuffle() async {
    _seed++;
    return _draft();
  }

  static const _createdMessage =
      "The league's teams are made. Manage rosters on each team.";

  Future<Result<void>> _save() async {
    final d = _division;
    if (d == null) return Result.error(Exception('Pick a division.'));
    if (created) return Result.error(Exception(_createdMessage));
    if (_locked &&
        !listEquals(
          [for (final t in _teams) t.id]..sort(),
          [for (final t in d.teams) t.id]..sort(),
        )) {
      return Result.error(
        Exception('The schedule is published, so teams can only be adjusted.'),
      );
    }
    if (_teams.length < 2) {
      return Result.error(Exception('Make at least two teams.'));
    }
    if (_teams.length > d.maxTeams) {
      return Result.error(
        Exception('This division takes up to ${d.maxTeams} teams.'),
      );
    }
    final empty = _teams.where((t) => t.playerIds.isEmpty).firstOrNull;
    if (empty != null) {
      return Result.error(Exception('${empty.name} has no players.'));
    }
    if (_teams.any((t) => t.name.trim().isEmpty)) {
      return Result.error(Exception('Every team needs a name.'));
    }
    final names = [for (final t in _teams) t.name.trim().toLowerCase()];
    if (names.toSet().length != names.length) {
      return Result.error(Exception('Team names must be different.'));
    }
    final r = await _repo.saveDraftTeams(tournamentId, d, [
      for (final t in _teams)
        t.copyWith(
          name: t.name.trim(),
          captainId: () => t.captainId ?? t.playerIds.first,
        ),
    ]);
    if (r is Ok) _dirty = false;
    return r;
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}
