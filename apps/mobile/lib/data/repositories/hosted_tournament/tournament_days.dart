import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../domain/models/group_tournament.dart';
import '../../../domain/models/hosted_tournament.dart';
import '../../../domain/models/team.dart';
import '../../../domain/tournament_engine/tournament_day.dart';
import 'hosted_tournament_repository.dart';

/// One of the user's teams on a tournament day: the card Home and the
/// team page show in place of "Up next".
class TeamTournamentDay {
  const TeamTournamentDay({
    required this.team,
    required this.tournament,
    required this.divisionId,
    required this.day,
    required this.now,
    this.names = const {},
    this.isCaptain = false,
    this.liveGame,
  });

  final Team team;

  /// When [day] was worked out, for "Tomorrow" and weekday labels.
  final DateTime now;
  final HostedTournament tournament;
  final String divisionId;
  final TournamentDay day;

  /// Entered teams' names by id.
  final Map<String, String> names;

  /// The user captains [team] in this division: they report its scores.
  final bool isCaptain;

  /// The team's game being played now ([GroupGame.liveAt] at [now]), if
  /// any: not always [TournamentDay.next], since an earlier game may
  /// still wait for its score.
  final GroupGame? liveGame;

  String nameOf(String? teamId) =>
      teamId == null ? 'TBD' : names[teamId] ?? 'TBD';

  /// The game a captain should act on now (report or confirm); null when
  /// there's none, or the user isn't a captain.
  GroupGame? get actionGame =>
      isCaptain &&
          (day.scoreDueKind == ScoreDueKind.report ||
              day.scoreDueKind == ScoreDueKind.confirm)
      ? day.scoreDue
      : null;
}

/// Watches the tournaments [teams] are entered in (accepted entries, from
/// the day before they start to the day they end) and, for each, the
/// team's division and games, so [days] can say what each team has on.
/// The rules are TournamentDay.of's; this only gathers the data.
class TournamentDays extends ChangeNotifier {
  TournamentDays({
    required HostedTournamentRepository repository,
    required Stream<List<Team>> teams,
    required this.uid,
    DateTime Function()? clock,
  }) : _repo = repository,
       _clock = clock ?? DateTime.now {
    _teamSub = teams.listen(_onTeams, onError: (Object _) {});
  }

  final HostedTournamentRepository _repo;
  final String uid;
  final DateTime Function() _clock;
  late final StreamSubscription<List<Team>> _teamSub;
  bool _disposed = false;

  /// What changes with the time of day (a game starting, 17:00 the day
  /// before) is checked each minute while something is on.
  Timer? _tick;

  final _teams = <String, Team>{};
  final _enteredSubs = <String, StreamSubscription<Object?>>{};
  final _entered = <String, List<EnteredTournament>>{};

  /// Per "teamId/tournamentId" being followed.
  final _follows = <String, _Follow>{};

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void _onTeams(List<Team> all) {
    // Only teams enter tournaments; communities host them.
    final teams = [
      for (final t in all)
        if (t.kind == TeamKind.team) t,
    ];
    final ids = {for (final t in teams) t.id};
    _teams
      ..clear()
      ..addEntries([for (final t in teams) MapEntry(t.id, t)]);
    for (final id in _enteredSubs.keys.toList()) {
      if (ids.contains(id)) continue;
      _enteredSubs.remove(id)?.cancel();
      _entered.remove(id);
    }
    for (final t in teams) {
      _enteredSubs[t.id] ??= _repo.watchEnteredBy(t.id).listen((e) {
        _entered[t.id] = e;
        _sync();
      }, onError: (Object _) {});
    }
    _sync();
  }

  /// Accepted entries from the day before they start to the day they end,
  /// with a day's slack each side: dates are the host's local midnight,
  /// which can fall on the day before (or after) here. Whether a card
  /// shows is still decided by the games' own times.
  bool _current(EnteredTournament e) {
    final starts = e.startsOn;
    if (e.status != EntryStatus.accepted || starts == null) return false;
    final now = _clock();
    final today = DateTime(now.year, now.month, now.day);
    final from = DateTime(starts.year, starts.month, starts.day - 2);
    final ends = e.endsOn ?? starts;
    final to = DateTime(ends.year, ends.month, ends.day + 1);
    return !today.isBefore(from) && !today.isAfter(to);
  }

  void _sync() {
    final wanted = <String>{};
    for (final MapEntry(key: teamId, value: list) in _entered.entries) {
      if (!_teams.containsKey(teamId)) continue;
      for (final e in list) {
        if (!_current(e)) continue;
        final key = '$teamId/${e.tournamentId}';
        wanted.add(key);
        _follows[key] ??= _Follow(
          _repo,
          teamId: teamId,
          tournamentId: e.tournamentId,
          onChange: _changed,
        );
      }
    }
    for (final key in _follows.keys.toList()) {
      if (!wanted.contains(key)) _follows.remove(key)?.cancel();
    }
    if (_follows.isEmpty) {
      _tick?.cancel();
      _tick = null;
    } else {
      _tick ??= Timer.periodic(const Duration(minutes: 1), (_) => _sync());
    }
    _changed();
  }

  /// What each team has on, today's first, then by its next game's time.
  List<TeamTournamentDay> get days {
    final now = _clock();
    final out = <TeamTournamentDay>[];
    for (final f in _follows.values) {
      final team = _teams[f.teamId];
      final t = f.tournament;
      final entry = f.entry;
      if (team == null || t == null || entry == null) continue;
      if (t.status != HostedStatus.scheduled &&
          t.status != HostedStatus.live &&
          t.status != HostedStatus.finished) {
        continue;
      }
      final day = TournamentDay.of(
        f.games,
        f.teamId,
        now: now,
        live: t.status == HostedStatus.live,
      );
      if (day == null) continue;
      final division = f.divisions
          .where((d) => d.id == entry.divisionId)
          .firstOrNull;
      out.add(
        TeamTournamentDay(
          team: team,
          tournament: t,
          divisionId: entry.divisionId,
          day: day,
          now: now,
          names: f.names,
          isCaptain: division?.captains[f.teamId]?.contains(uid) ?? false,
          liveGame: f.games
              .where((g) => g.involves(f.teamId) && g.liveAt(now) != null)
              .firstOrNull,
        ),
      );
    }
    final far = DateTime(9999);
    out.sort((a, b) {
      if (a.day.phase != b.day.phase) {
        return a.day.phase == TournamentDayPhase.today ? -1 : 1;
      }
      return (a.day.next?.game.startsAt ?? far).compareTo(
        b.day.next?.game.startsAt ?? far,
      );
    });
    return out;
  }

  /// [teamId]'s card, if it has one.
  TeamTournamentDay? forTeam(String teamId) =>
      days.where((d) => d.team.id == teamId).firstOrNull;

  @override
  void dispose() {
    _disposed = true;
    _tick?.cancel();
    _teamSub.cancel();
    for (final s in _enteredSubs.values) {
      s.cancel();
    }
    for (final f in _follows.values) {
      f.cancel();
    }
    super.dispose();
  }
}

/// One team's entry in one tournament: the tournament, the entries (its
/// division, and every team's name), the divisions (captains) and its
/// division's games.
class _Follow {
  _Follow(
    this._repo, {
    required this.teamId,
    required this.tournamentId,
    required this.onChange,
  }) {
    _subs = [
      _repo.watchTournament(tournamentId).listen((t) {
        tournament = t;
        onChange();
      }, onError: (Object _) {}),
      _repo.watchEntries(tournamentId).listen((e) {
        entry = e.where((x) => x.teamId == teamId).firstOrNull;
        names = {for (final x in e) x.teamId: x.teamName};
        _watchGames();
        onChange();
      }, onError: (Object _) {}),
      _repo.watchDivisions(tournamentId).listen((d) {
        divisions = d;
        onChange();
      }, onError: (Object _) {}),
    ];
  }

  final HostedTournamentRepository _repo;
  final String teamId;
  final String tournamentId;
  final VoidCallback onChange;
  late final List<StreamSubscription<Object?>> _subs;
  StreamSubscription<List<GroupGame>>? _gameSub;
  String? _gamesOf;

  HostedTournament? tournament;
  TournamentEntry? entry;
  Map<String, String> names = const {};
  List<TournamentDivision> divisions = const [];
  List<GroupGame> games = const [];

  void _watchGames() {
    final division = entry?.divisionId;
    if (division == _gamesOf) return;
    _gamesOf = division;
    _gameSub?.cancel();
    games = const [];
    if (division == null || division.isEmpty) return;
    _gameSub = _repo.watchGames(tournamentId, division).listen((g) {
      games = g;
      onChange();
    }, onError: (Object _) {});
  }

  void cancel() {
    for (final s in _subs) {
      s.cancel();
    }
    _gameSub?.cancel();
  }
}
