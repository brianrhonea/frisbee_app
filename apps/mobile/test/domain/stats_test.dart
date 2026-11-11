import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/stats.dart';

void main() {
  const line = ['a', 'b', 'c', 'd', 'e', 'f', 'g'];

  test('scoring: assist/goal +1, throwaway and drop -1, blocks +2/+1', () {
    final sheet = StatSheet.fromPoints([
      // O point: a picks up, a → b, b → c (goal).
      const StatPoint(
        line: line,
        startedOn: Side.offense,
        result: PointResult.weScored,
        actions: [
          StatAction(StatKind.pickup, playerId: 'a'),
          StatAction(StatKind.catch_, playerId: 'b', throwerId: 'a'),
          StatAction(StatKind.goal, playerId: 'c', throwerId: 'b'),
        ],
      ),
      // D point: d gets beat, e hand blocks, a throws it away, b breaks up,
      // a → c dropped, then they score.
      const StatPoint(
        line: line,
        startedOn: Side.defense,
        result: PointResult.theyScored,
        actions: [
          StatAction(StatKind.beat, playerId: 'd'),
          StatAction(StatKind.handBlock, playerId: 'e'),
          StatAction(StatKind.pickup, playerId: 'a'),
          StatAction(StatKind.throwaway, playerId: 'a'),
          StatAction(StatKind.breakup, playerId: 'b'),
          StatAction(StatKind.pickup, playerId: 'a'),
          StatAction(StatKind.drop, playerId: 'c', throwerId: 'a'),
        ],
      ),
    ]);
    final p = sheet.players;
    expect(p['b']!.assists, 1);
    expect(p['c']!.goals, 1);
    expect(p['b']!.plusMinus, 2); // assist + breakup
    expect(p['c']!.plusMinus, 0); // goal - drop
    expect(p['a']!.plusMinus, -1); // throwaway
    expect(p['e']!.plusMinus, 2); // hand block
    expect(p['d']!.plusMinus, -1); // got beat
    expect(p['a']!.pointsO, 1);
    expect(p['a']!.pointsD, 1);
  });

  test('touches, completion % and catch %', () {
    final sheet = StatSheet.fromPoints([
      const StatPoint(
        line: line,
        startedOn: Side.offense,
        actions: [
          StatAction(StatKind.pickup, playerId: 'a'),
          StatAction(StatKind.catch_, playerId: 'b', throwerId: 'a'),
          StatAction(StatKind.catch_, playerId: 'a', throwerId: 'b'),
          StatAction(StatKind.drop, playerId: 'b', throwerId: 'a'),
        ],
      ),
    ]);
    final a = sheet.players['a']!, b = sheet.players['b']!;
    expect(a.touches, 2);
    expect(a.throws, 2);
    expect(a.completionPct, 1); // a drop isn't the thrower's fault
    expect(b.catchPct, 0.5);
    expect(sheet.players['c']!.catchPct, isNull);
  });

  test('point side and holder follow turnovers', () {
    const point = StatPoint(
      line: line,
      startedOn: Side.offense,
      actions: [
        StatAction(StatKind.pickup, playerId: 'a'),
        StatAction(StatKind.catch_, playerId: 'b', throwerId: 'a'),
      ],
    );
    expect(point.side, Side.offense);
    expect(point.holder, 'b');
    final turned = point.copyWith(
      actions: [
        ...point.actions,
        const StatAction(StatKind.throwaway, playerId: 'b'),
      ],
    );
    expect(turned.side, Side.defense);
    expect(turned.holder, isNull);
  });

  test('O efficiency and break rate, scaled up for involvement', () {
    final sheet = StatSheet.fromPoints([
      // Hold: a picks up, a → b, b → c goal.
      const StatPoint(
        line: line,
        startedOn: Side.offense,
        result: PointResult.weScored,
        actions: [
          StatAction(StatKind.pickup, playerId: 'a'),
          StatAction(StatKind.catch_, playerId: 'b', throwerId: 'a'),
          StatAction(StatKind.goal, playerId: 'c', throwerId: 'b'),
        ],
      ),
      // O point they score.
      const StatPoint(
        line: line,
        startedOn: Side.offense,
        result: PointResult.theyScored,
      ),
      // Break: d hand blocks, d picks up, d → e goal.
      const StatPoint(
        line: line,
        startedOn: Side.defense,
        result: PointResult.weScored,
        actions: [
          StatAction(StatKind.handBlock, playerId: 'd'),
          StatAction(StatKind.pickup, playerId: 'd'),
          StatAction(StatKind.goal, playerId: 'e', throwerId: 'd'),
        ],
      ),
      // D point in progress: not counted yet.
      const StatPoint(line: line, startedOn: Side.defense),
    ]);
    expect(sheet.team.oPoints, 2);
    expect(sheet.team.holds, 1);
    expect(sheet.team.oEfficiency, 0.5);
    expect(sheet.team.breakRate, 1);

    final p = sheet.players;
    expect(p['g']!.oEfficiency, 0.5);
    expect(p['g']!.oRating, closeTo(0.5, 1e-9)); // on the field, no touches
    // c: hold with a goal and a touch: (1 + 0.5 + 0.1) over 2 O points.
    expect(p['c']!.oRating, closeTo(0.8, 1e-9));
    // b: catch + assist: (1 + 0.5 + 0.1) / 2.
    expect(p['b']!.oRating, closeTo(0.8, 1e-9));
    // d: break + hand block + assist + touch: 1 + 1 + 0.5 + 0.1.
    expect(p['d']!.dEfficiency, 1);
    expect(p['d']!.dRating, closeTo(2.6, 1e-9));
    expect(p['a']!.dRating, closeTo(1, 1e-9));
    expect(p['a']!.pointsD, 2, reason: 'in-progress point still played');
    expect(p['a']!.finishedD, 1);
  });

  test(
    'point credit: no touch cap, nothing unless we score, turnovers cost',
    () {
      final busy = Involvement()..touches = 12;
      expect(busy.credit(scored: true), closeTo(2.2, 1e-9));
      final blocker = Involvement()..handBlocks = 1;
      expect(blocker.credit(scored: false), 0);
      final sloppy = Involvement()
        ..touches = 3
        ..goals = 1
        ..throwaways = 1;
      // 1 + 0.5 goal + 0.3 touches − 0.75 throwaway.
      expect(sloppy.credit(scored: true), closeTo(1.05, 1e-9));
      final costly = Involvement()
        ..throwaways = 1
        ..drops = 1;
      expect(costly.credit(scored: false), closeTo(-1.5, 1e-9));
    },
  );

  test('games and tournaments survive a save and load', () {
    final game = StatsGame(
      id: 'g1',
      opponent: 'Rival',
      date: DateTime(2026, 10, 28, 18),
      gameTo: 13,
      tournamentId: 't1',
      eventId: 'e1',
      finished: true,
      timeoutsPerHalf: 3,
      timeouts: const [GameTimeout(ours: false, half: 2, point: 4, action: 1)],
      lines: const [
        StatLine(id: 'l1', name: 'O', players: line, side: Side.offense),
        StatLine(id: 'l2', name: 'Any', players: line),
      ],
      points: const [
        StatPoint(
          line: line,
          startedOn: Side.defense,
          result: PointResult.weScored,
          actions: [
            StatAction(
              StatKind.pull,
              playerId: 'a',
              hangTimeMs: 5400,
              outOfBounds: true,
            ),
            StatAction(StatKind.sub, playerId: 'h', subOutId: 'b'),
            StatAction(StatKind.goal, playerId: 'c', throwerId: 'h'),
          ],
        ),
        StatPoint(line: line, startedOn: Side.offense),
      ],
    );
    final back = StatsGame.fromMap('g1', game.toMap());
    expect(back.toMap(), game.toMap());
    expect(back.points.first.actions.first.hangTimeMs, 5400);
    expect(back.points.last.result, isNull);
    expect(back.lines.last.side, isNull);
    expect(back.timeouts.single.ours, isFalse);

    final t = StatsTournament(
      id: 't1',
      name: 'Regionals',
      startDate: DateTime(2026, 10, 1),
      eventId: 'e2',
      roster: line,
      lines: game.lines,
    );
    expect(StatsTournament.fromMap('t1', t.toMap()).toMap(), t.toMap());
  });
}
