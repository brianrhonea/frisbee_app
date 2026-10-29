import 'dart:async';
import 'dart:math';

import '../../../domain/models/roster_player.dart';
import '../../../domain/models/stats.dart';
import '../../../utils/result.dart';
import '../team/team_repository.dart';
import 'stats_repository.dart';

/// In-memory stats for tests and demos. Nothing is saved; each team is
/// seeded with a sample tournament and games the first time it's opened.
/// The app uses `StatsRepositoryFirebase`.
///
/// Uses the real team roster when it has at least seven players, otherwise
/// a sample roster so the screens can be tried on an empty team.
class MockStatsRepository implements StatsRepository {
  MockStatsRepository({required TeamRepository teamRepository})
    : _teams = teamRepository;

  final TeamRepository _teams;
  final _data = <String, Future<_TeamStats>>{};
  final _changes = StreamController<String>.broadcast();
  var _nextId = 0;

  String _id(String prefix) => '$prefix${++_nextId}';

  Future<_TeamStats> _load(String teamId) => _data[teamId] ??= () async {
    var roster = const <RosterPlayer>[];
    try {
      roster = await _teams.watchRoster(teamId).first;
    } on Exception {
      // Fall back to the sample roster.
    }
    if (roster.length < StatLine.size) roster = _sampleRoster;
    return _seed(roster);
  }();

  Stream<T> _watch<T>(String teamId, T Function(_TeamStats) read) async* {
    final s = await _load(teamId);
    yield read(s);
    yield* _changes.stream.where((id) => id == teamId).map((_) => read(s));
  }

  @override
  Stream<List<RosterPlayer>> watchPlayers(String teamId) =>
      _watch(teamId, (s) => s.players);

  @override
  Stream<List<StatsTournament>> watchTournaments(String teamId) => _watch(
    teamId,
    (s) =>
        s.tournaments.values.toList()
          ..sort((a, b) => b.startDate.compareTo(a.startDate)),
  );

  @override
  Stream<List<StatsGame>> watchGames(String teamId) => _watch(
    teamId,
    (s) => s.games.values.toList()..sort((a, b) => b.date.compareTo(a.date)),
  );

  @override
  Future<Result<String>> saveTournament(
    String teamId,
    StatsTournament t,
  ) async {
    final s = await _load(teamId);
    final id = t.id.isEmpty ? _id('t') : t.id;
    s.tournaments[id] = t.id.isEmpty
        ? StatsTournament(
            id: id,
            name: t.name,
            startDate: t.startDate,
            location: t.location,
            eventId: t.eventId,
            roster: t.roster,
            lines: t.lines,
          )
        : t;
    _changes.add(teamId);
    return Result.ok(id);
  }

  @override
  Future<Result<String>> saveGame(String teamId, StatsGame game) async {
    final s = await _load(teamId);
    final id = game.id.isEmpty ? _id('g') : game.id;
    s.games[id] = game.id.isEmpty
        ? StatsGame(
            id: id,
            opponent: game.opponent,
            date: game.date,
            gameTo: game.gameTo,
            tournamentId: game.tournamentId,
            eventId: game.eventId,
            points: game.points,
            finished: game.finished,
            lines: game.lines,
            timeoutsPerHalf: game.timeoutsPerHalf,
            timeouts: game.timeouts,
          )
        : game;
    _changes.add(teamId);
    return Result.ok(id);
  }

  @override
  Future<Result<void>> deleteGame(String teamId, String gameId) async {
    final s = await _load(teamId);
    s.games.remove(gameId);
    _changes.add(teamId);
    return const Result.ok(null);
  }

  // ---- Sample data -------------------------------------------------------

  static const _sampleNames = [
    ('Alex Rivera', PlayerPosition.handler),
    ('Sam Okafor', PlayerPosition.handler),
    ('Jordan Lee', PlayerPosition.handler),
    ('Casey Nguyen', PlayerPosition.hybrid),
    ('Riley Patel', PlayerPosition.hybrid),
    ('Morgan Diaz', PlayerPosition.cutter),
    ('Taylor Brooks', PlayerPosition.cutter),
    ('Jamie Chen', PlayerPosition.cutter),
    ('Avery Kim', PlayerPosition.cutter),
    ('Quinn Foster', PlayerPosition.hybrid),
    ('Drew Martin', PlayerPosition.cutter),
    ('Parker Shah', PlayerPosition.handler),
    ('Reese Walker', PlayerPosition.cutter),
    ('Skyler Ortiz', PlayerPosition.hybrid),
  ];

  static final _sampleRoster = [
    for (var i = 0; i < _sampleNames.length; i++)
      RosterPlayer(
        id: 'sample-$i',
        name: _sampleNames[i].$1,
        number: [2, 4, 7, 9, 11, 13, 17, 21, 23, 31, 42, 44, 55, 88][i],
        position: _sampleNames[i].$2,
      ),
  ];

  _TeamStats _seed(List<RosterPlayer> roster) {
    final ids = [for (final p in roster) p.id];
    final handlers = [
      for (final p in roster)
        if (p.position == PlayerPosition.handler) p.id,
    ];
    // O-line: handlers first; D-line: everyone else first.
    final byO = [...handlers, ...ids.where((id) => !handlers.contains(id))];
    final byD = [...ids.where((id) => !handlers.contains(id)), ...handlers];
    final lines = [
      StatLine(
        id: _id('l'),
        name: 'O-line',
        players: byO.take(7).toList(),
        side: Side.offense,
      ),
      StatLine(
        id: _id('l'),
        name: 'D-line',
        players: byD.take(7).toList(),
        side: Side.defense,
      ),
    ];

    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day - 10);
    final tournament = StatsTournament(
      id: _id('t'),
      name: 'Fall Classic',
      startDate: start,
      location: 'Riverside Fields',
      roster: ids,
      lines: lines,
    );
    final rng = Random(7);
    final games = [
      for (final (i, opp) in ['Ring of Fire', 'Truck Stop', 'Sockeye'].indexed)
        StatsGame(
          id: _id('g'),
          opponent: opp,
          date: start.add(Duration(hours: 9 + i * 2)),
          tournamentId: tournament.id,
          gameTo: 13,
          points: _simulateGame(rng, lines, winBias: i == 2 ? 0.45 : 0.6),
        ),
      StatsGame(
        id: _id('g'),
        opponent: 'Alumni scrimmage',
        date: DateTime(now.year, now.month, now.day - 2, 18),
        gameTo: 11,
        points: _simulateGame(rng, lines, winBias: 0.55, cap: 5),
      ),
    ];
    return _TeamStats(
      players: roster,
      tournaments: {tournament.id: tournament},
      games: {for (final g in games) g.id: g},
    );
  }

  /// Plays points until someone reaches [cap].
  static List<StatPoint> _simulateGame(
    Random rng,
    List<StatLine> lines, {
    required double winBias,
    int cap = 13,
  }) {
    final points = <StatPoint>[];
    var us = 0, them = 0;
    var side = Side.defense;
    while (us < cap && them < cap) {
      final line = side == Side.offense ? lines[0] : lines[1];
      final point = _simulatePoint(rng, line.players, side, winBias);
      points.add(point);
      if (point.result == PointResult.weScored) {
        us++;
        side = Side.defense;
      } else {
        them++;
        side = Side.offense;
      }
    }
    return points;
  }

  static StatPoint _simulatePoint(
    Random rng,
    List<String> line,
    Side startedOn,
    double winBias,
  ) {
    String pick([String? not]) {
      String id;
      do {
        id = line[rng.nextInt(line.length)];
      } while (id == not);
      return id;
    }

    final actions = <StatAction>[
      if (startedOn == Side.defense)
        StatAction(
          StatKind.pull,
          playerId: line.last,
          hangTimeMs: 4200 + rng.nextInt(2600),
          outOfBounds: rng.nextDouble() < 0.12,
        ),
    ];
    var side = startedOn;
    for (var possession = 0; possession < 6; possession++) {
      if (side == Side.defense) {
        if (rng.nextDouble() < 0.25) {
          actions.add(StatAction(StatKind.beat, playerId: pick()));
        }
        final r = rng.nextDouble();
        if (r > winBias + 0.1) {
          return StatPoint(
            line: line,
            startedOn: startedOn,
            actions: actions,
            result: PointResult.theyScored,
          );
        }
        actions.add(
          r < 0.15
              ? StatAction(StatKind.handBlock, playerId: pick())
              : r < 0.4
              ? StatAction(StatKind.breakup, playerId: pick())
              : const StatAction(StatKind.theirTurnover),
        );
        side = Side.offense;
        continue;
      }
      var holder = pick();
      actions.add(StatAction(StatKind.pickup, playerId: holder));
      final passes = 2 + rng.nextInt(7);
      var turned = false;
      for (var i = 0; i < passes; i++) {
        final receiver = pick(holder);
        final r = rng.nextDouble();
        if (r < 0.05) {
          actions.add(StatAction(StatKind.throwaway, playerId: holder));
          turned = true;
          break;
        }
        if (r < 0.08) {
          actions.add(
            StatAction(StatKind.drop, playerId: receiver, throwerId: holder),
          );
          turned = true;
          break;
        }
        final last = i == passes - 1;
        actions.add(
          StatAction(
            last ? StatKind.goal : StatKind.catch_,
            playerId: receiver,
            throwerId: holder,
          ),
        );
        holder = receiver;
      }
      if (!turned) {
        return StatPoint(
          line: line,
          startedOn: startedOn,
          actions: actions,
          result: PointResult.weScored,
        );
      }
      side = Side.defense;
    }
    return StatPoint(
      line: line,
      startedOn: startedOn,
      actions: actions,
      result: PointResult.theyScored,
    );
  }
}

class _TeamStats {
  _TeamStats({
    required this.players,
    required this.tournaments,
    required this.games,
  });

  final List<RosterPlayer> players;
  final Map<String, StatsTournament> tournaments;
  final Map<String, StatsGame> games;
}
