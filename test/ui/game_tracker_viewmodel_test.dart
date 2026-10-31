import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/stats/mock_stats_repository.dart';
import 'package:frisbee_app/domain/models/stats.dart';
import 'package:frisbee_app/domain/models/roster_player.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/ui/stats/view_models/game_tracker_viewmodel.dart';
import 'package:frisbee_app/ui/stats/widgets/player_chooser.dart';
import 'package:frisbee_app/utils/result.dart';

import '../testing/fakes.dart';

void main() {
  late MockStatsRepository stats;
  late FakeTeamRepository teams;

  setUp(() {
    teams = FakeTeamRepository()
      ..teams['t1'] = teamWith({'u1': TeamRole.owner});
  });

  /// A new, empty standalone game. The team has no roster, so the mock
  /// uses its sample players.
  Future<GameTrackerViewModel> tracker({int gameTo = 15}) async {
    stats = MockStatsRepository(teamRepository: teams);
    final r = await stats.saveGame(
      't1',
      StatsGame(id: '', opponent: 'Test', date: DateTime(2026), gameTo: gameTo),
    );
    final vm = GameTrackerViewModel(
      teamId: 't1',
      gameId: (r as Ok<String>).value,
      statsRepository: stats,
      teamRepository: teams,
      authRepository: FakeAuthRepository(user: testUser),
    );
    await pumpEventQueue();
    return vm;
  }

  List<String> seven(GameTrackerViewModel vm) =>
      vm.available.take(7).map((p) => p.id).toList();

  /// Pickup by [ids][0], pass to [ids][1], then Score to [ids][2].
  void scorePoint(GameTrackerViewModel vm, List<String> ids) {
    vm.useLine(ids);
    if (vm.side == Side.defense) vm.weGotIt();
    vm.tapPlayer(ids[0]);
    vm.tapPlayer(ids[1]);
    vm.arm(StatKind.goal);
    vm.tapPlayer(ids[2]);
  }

  test('mock seeds sample tournaments and games', () async {
    stats = MockStatsRepository(teamRepository: teams);
    expect(await stats.watchTournaments('t1').first, hasLength(1));
    final games = await stats.watchGames('t1').first;
    expect(games.where((g) => g.over), hasLength(3));
  });

  test('a line needs exactly seven players', () async {
    final vm = await tracker();
    expect(vm.currentPoint, isNull);
    vm.useLine(seven(vm).take(6).toList());
    expect(vm.currentPoint, isNull);
    vm.useLine(seven(vm));
    expect(vm.currentPoint!.line, hasLength(7));
    expect(vm.side, Side.offense);
  });

  test('Score is armed, then credits the thrower and the receiver', () async {
    final vm = await tracker();
    final ids = seven(vm);
    vm.useLine(ids);
    vm.arm(StatKind.goal);
    expect(vm.armed, isNull, reason: 'nobody has the disc yet');
    vm.tapPlayer(ids[0]); // pickup
    vm.tapPlayer(ids[1]); // catch
    expect(vm.passChain, ids.take(2).toList());
    vm.arm(StatKind.goal);
    vm.tapPlayer(ids[1]); // holder can't catch their own throw
    expect(vm.armed, StatKind.goal);
    vm.tapPlayer(ids[2]);

    expect(vm.game!.ourScore, 1);
    expect(vm.currentPoint, isNull);
    expect(vm.nextSide, Side.defense, reason: 'we pull after scoring');
    final sheet = vm.sheet.players;
    expect(sheet[ids[1]]!.assists, 1);
    expect(sheet[ids[1]]!.plusMinus, 1);
    expect(sheet[ids[2]]!.goals, 1);
    expect(sheet[ids[2]]!.plusMinus, 1);
    expect(sheet[ids[1]]!.touches, 1);
  });

  test('drop -1 to the receiver flips us to D', () async {
    final vm = await tracker();
    final ids = seven(vm);
    vm.useLine(ids);
    vm.tapPlayer(ids[0]);
    vm.arm(StatKind.drop);
    vm.tapPlayer(ids[3]);
    expect(vm.side, Side.defense);
    expect(vm.sheet.players[ids[3]]!.plusMinus, -1);
    expect(vm.sheet.players[ids[3]]!.catchPct, 0);
  });

  test('pull records hang time and out of bounds, stays on D', () async {
    final vm = await tracker();
    final ids = seven(vm);
    scorePoint(vm, ids);
    vm.useLine(ids);
    expect(vm.side, Side.defense);
    expect(vm.canPull, isTrue);
    vm.recordPull(
      ids[6],
      hangTime: const Duration(milliseconds: 5400),
      outOfBounds: true,
    );
    expect(vm.canPull, isFalse);
    expect(vm.side, Side.defense);
    final puller = vm.sheet.players[ids[6]]!;
    expect(puller.pulls, 1);
    expect(puller.pullsOutOfBounds, 1);
    expect(puller.avgHangTime, closeTo(5.4, 1e-9));
    expect(vm.lastPuller, ids[6]);
  });

  test(
    'D: hand block +2 or their turnover puts us on O for a pickup',
    () async {
      final vm = await tracker();
      final ids = seven(vm);
      vm.setSide(Side.defense);
      vm.useLine(ids);
      vm.arm(StatKind.beat);
      vm.tapPlayer(ids[4]);
      expect(vm.side, Side.defense);
      vm.arm(StatKind.handBlock);
      vm.tapPlayer(ids[5]);
      expect(vm.side, Side.offense);
      expect(vm.holder, isNull);
      expect(vm.sheet.players[ids[5]]!.plusMinus, 2);
      expect(vm.sheet.players[ids[4]]!.plusMinus, -1);

      vm.tapPlayer(ids[0]); // pickup
      vm.throwaway();
      expect(vm.sheet.players[ids[0]]!.plusMinus, -1);
      expect(vm.side, Side.defense);
      vm.weGotIt();
      expect(vm.side, Side.offense);
    },
  );

  test('opponent score works any time, even between points', () async {
    final vm = await tracker();
    vm.theyScored();
    expect(vm.game!.theirScore, 1);
    expect(vm.nextSide, Side.offense);
    vm.undo();
    expect(vm.game!.theirScore, 0);
    expect(vm.points, isEmpty);
  });

  test('substitution swaps a player mid-point; both get the point', () async {
    final vm = await tracker();
    final ids = seven(vm);
    vm.useLine(ids);
    final bench = vm.bench.first.id;
    vm.tapPlayer(ids[0]);
    vm.substitute(ids[3], bench);
    expect(vm.onField, contains(bench));
    expect(vm.onField, isNot(contains(ids[3])));
    vm.tapPlayer(bench);
    vm.arm(StatKind.goal);
    vm.tapPlayer(ids[1]);
    expect(vm.sheet.players[bench]!.assists, 1);
    expect(vm.sheet.players[bench]!.pointsPlayed, 1);
    expect(vm.sheet.players[ids[3]]!.pointsPlayed, 1);
  });

  test('reaching game point locks tracking; raising it reopens', () async {
    final vm = await tracker(gameTo: 2);
    final ids = seven(vm);
    scorePoint(vm, ids);
    scorePoint(vm, ids);
    expect(vm.game!.ourScore, 2);
    expect(vm.over, isTrue);
    expect(vm.game!.won, isTrue);
    vm.useLine(ids);
    expect(vm.currentPoint, isNull);
    vm.theyScored();
    expect(vm.game!.theirScore, 0);

    vm.setGameTo(3);
    expect(vm.over, isFalse);
    vm.useLine(ids);
    expect(vm.currentPoint, isNotNull);
  });

  test('undo reopens a scored point with the thrower holding', () async {
    final vm = await tracker();
    final ids = seven(vm);
    scorePoint(vm, ids);
    expect(vm.game!.ourScore, 1);

    vm.undo();
    expect(vm.game!.ourScore, 0);
    expect(vm.holder, ids[1]);
    vm.undo();
    vm.undo();
    expect(vm.currentPoint!.actions, isEmpty);
    vm.undo(); // drops the empty point
    expect(vm.points, isEmpty);
  });

  test('side is locked once the point has an action', () async {
    final vm = await tracker();
    final ids = seven(vm);
    vm.useLine(ids);
    expect(vm.canSetSide, isTrue);
    vm.tapPlayer(ids[0]);
    expect(vm.canSetSide, isFalse);
    vm.setSide(Side.defense);
    expect(vm.side, Side.offense);
  });

  test('saved lines for the next side come first', () async {
    await tracker();
    // Standalone games have no saved lines; check the sample tournament.
    final t = (await stats.watchTournaments('t1').first).single;
    expect(t.lines.map((l) => l.side), [Side.offense, Side.defense]);
  });

  test('last line is remembered per side', () async {
    final vm = await tracker();
    final ids = seven(vm);
    final others = vm.available.skip(7).take(7).map((p) => p.id).toList();
    expect(vm.lastLineFor(Side.offense), isNull);
    scorePoint(vm, ids); // O point
    scorePoint(vm, others); // D point (we pulled)
    expect(vm.lastLineFor(Side.offense), ids);
    expect(vm.lastLineFor(Side.defense), others);
  });

  test('players sort A–Z or by position, alphabetical within', () {
    const players = [
      RosterPlayer(id: '1', name: 'zed', position: PlayerPosition.handler),
      RosterPlayer(id: '2', name: 'Amy', position: PlayerPosition.cutter),
      RosterPlayer(id: '3', name: 'bo', position: PlayerPosition.handler),
    ];
    final az = sortPlayers(players, PlayerSort.name).single.$2;
    expect(az.map((p) => p.name), ['Amy', 'bo', 'zed']);
    final grouped = sortPlayers(players, PlayerSort.position);
    expect(grouped.map((g) => g.$1), [
      PlayerPosition.handler,
      PlayerPosition.cutter,
    ]);
    expect(grouped.first.$2.map((p) => p.name), ['bo', 'zed']);
  });

  test('standalone games keep their own lines', () async {
    final vm = await tracker();
    final ids = seven(vm);
    vm.saveLine('Starters', ids, side: Side.offense);
    expect(vm.linesFor(Side.offense).single.name, 'Starters');
    final id = vm.savedLines.single.id;
    vm.saveLine('Starters O', ids, id: id, side: Side.offense);
    expect(vm.savedLines.single.name, 'Starters O');
    vm.useLine(ids, saveAs: 'Also', saveSide: Side.defense);
    expect(vm.linesFor(Side.defense).first.name, 'Also');
    vm.deleteLine(id);
    expect(vm.savedLines.map((l) => l.name), ['Also']);
    await pumpEventQueue();
    final saved = (await stats.watchGames('t1').first).firstWhere(
      (g) => g.id == vm.gameId,
    );
    expect(saved.lines.map((l) => l.name), ['Also']);
  });

  test('lines import from another game, and from the linked event', () async {
    stats = MockStatsRepository(teamRepository: teams);
    final players = await stats.watchPlayers('t1').first;
    final ids = players.take(7).map((p) => p.id).toList();
    final line = StatLine(id: 'x', name: 'Practice O', players: ids);
    await stats.saveGame(
      't1',
      StatsGame(
        id: '',
        opponent: 'Scrimmage 1',
        date: DateTime(2026, 10, 1),
        eventId: 'e1',
        lines: [line],
      ),
    );
    final r = await stats.saveGame(
      't1',
      StatsGame(
        id: '',
        opponent: 'Scrimmage 2',
        date: DateTime(2026, 10, 1),
        eventId: 'e1',
      ),
    );
    final vm = GameTrackerViewModel(
      teamId: 't1',
      gameId: (r as Ok<String>).value,
      statsRepository: stats,
      teamRepository: teams,
      authRepository: FakeAuthRepository(user: testUser),
    );
    await pumpEventQueue();
    expect(vm.lineSources.first.name, 'vs Scrimmage 1');
    expect(vm.eventLinesToImport.single.name, 'Practice O');
    expect(vm.importLines(vm.eventLinesToImport), 1);
    expect(vm.savedLines.single.name, 'Practice O');
    expect(vm.eventLinesToImport, isEmpty);
    expect(vm.importLines([line]), 0, reason: 'already have it');
  });

  test('an injured holder subs out; the sub has the disc, no catch', () async {
    final vm = await tracker();
    final ids = seven(vm);
    vm.useLine(ids);
    final bench = vm.bench.first.id;
    vm.tapPlayer(ids[0]); // pickup
    vm.tapPlayer(ids[1]); // catch
    expect(vm.canSubOut(ids[1]), isTrue);
    vm.substitute(ids[1], bench);
    expect(vm.holder, bench);
    vm.arm(StatKind.goal);
    vm.tapPlayer(ids[2]);
    final sheet = vm.sheet.players;
    expect(sheet[bench]!.touches, 0, reason: 'took over without a catch');
    expect(sheet[bench]!.assists, 1);
    expect(sheet[ids[1]]!.touches, 1);
    expect(sheet[ids[1]]!.assists, 0);
  });

  test('timeouts are limited per half and reset at halftime', () async {
    final vm = await tracker(gameTo: 3); // halftime at 2
    final ids = seven(vm);
    expect(vm.timeoutsPerHalf, 2);
    vm.callTimeout(ours: true);
    vm.callTimeout(ours: true);
    expect(vm.timeoutsLeft(ours: true), 0);
    expect(vm.canCallTimeout(ours: true), isFalse);
    vm.callTimeout(ours: true);
    expect(vm.timeouts, hasLength(2));
    expect(vm.timeoutsLeft(ours: false), 2);

    vm.useLine(ids);
    vm.tapPlayer(ids[0]);
    vm.callTimeout(ours: false);
    expect(vm.timeouts.last.point, 0);
    expect(vm.timeouts.last.action, 1);
    vm.arm(StatKind.goal);
    vm.tapPlayer(ids[1]);
    scorePoint(vm, ids);
    expect(vm.half, 2);
    expect(vm.game!.halftimePoint, 1);
    expect(vm.timeoutsLeft(ours: true), 2);
    expect(vm.timeoutsLeft(ours: false), 2);

    vm.removeTimeout(vm.timeouts.first);
    expect(vm.timeouts, hasLength(2));
    vm.setTimeoutsPerHalf(1);
    expect(vm.game!.timeoutsPerHalf, 1);
  });

  test('players can view a game but not change it', () async {
    teams.teams['t1'] = teamWith({
      'boss': TeamRole.owner,
      'u1': TeamRole.player,
    });
    final vm = await tracker();
    final ids = seven(vm);
    expect(vm.canEdit, isFalse);
    vm.useLine(ids);
    expect(vm.currentPoint, isNull);
    expect(vm.canTrack, isFalse);
    vm.theyScored();
    vm.callTimeout(ours: true);
    vm.saveLine('Mine', ids);
    expect(vm.game!.theirScore, 0);
    expect(vm.timeouts, isEmpty);
    expect(vm.savedLines, isEmpty);
  });

  group('undo last', () {
    test('names what it will take back, newest first', () async {
      final vm = await tracker();
      final ids = seven(vm);
      expect(vm.undoLabel, isNull);
      vm.useLine(ids);
      expect(vm.undoLabel, 'Start of point 1');
      vm.tapPlayer(ids[0]);
      vm.tapPlayer(ids[1]);
      expect(vm.undoLabel, '${vm.nameOf(ids[0])} → ${vm.nameOf(ids[1])}');
      vm.arm(StatKind.goal);
      expect(vm.undoLabel, 'Cancel Score');
      vm.undo();
      expect(vm.armed, isNull);
      expect(vm.currentPoint!.actions, hasLength(2));
      vm.arm(StatKind.goal);
      vm.tapPlayer(ids[2]);
      expect(vm.undoLabel, startsWith('Score: '));
      expect(vm.game!.ourScore, 1);
    });

    test('a wrong tap is taken back exactly', () async {
      final vm = await tracker();
      final ids = seven(vm);
      vm.useLine(ids);
      vm.tapPlayer(ids[0]);
      vm.tapPlayer(ids[1]);
      final before = vm.currentPoint!;
      vm.throwaway(); // meant to tap a receiver
      expect(vm.side, Side.defense);
      vm.undo();
      expect(vm.side, Side.offense);
      expect(vm.holder, ids[1]);
      expect(vm.currentPoint!.actions, before.actions);
      expect(vm.sheet.players[ids[1]]!.throwaways, 0);
    });

    test('steps back through a D, then the pull', () async {
      final vm = await tracker();
      final ids = seven(vm);
      scorePoint(vm, ids);
      vm.useLine(ids); // D point
      vm.recordPull(
        ids[6],
        hangTime: const Duration(seconds: 5),
        outOfBounds: false,
      );
      vm.arm(StatKind.breakup);
      vm.tapPlayer(ids[3]);
      vm.undo();
      expect(vm.currentPoint!.actions.map((a) => a.kind), [StatKind.pull]);
      expect(vm.undoLabel, contains('pull'));
      vm.undo();
      expect(vm.currentPoint!.actions, isEmpty);
      expect(vm.canPull, isTrue);
    });

    test('takes back timeouts, they-scored and ending the game', () async {
      final vm = await tracker();
      final ids = seven(vm);
      vm.useLine(ids);
      vm.callTimeout(ours: true);
      expect(vm.undoLabel, 'Our timeout');
      vm.undo();
      expect(vm.timeouts, isEmpty);

      vm.theyScored();
      expect(vm.game!.theirScore, 1);
      vm.undo();
      expect(vm.game!.theirScore, 0);
      expect(vm.currentPoint, isNotNull);

      vm.setFinished(true);
      expect(vm.over, isTrue);
      expect(vm.canUndo, isTrue);
      vm.undo();
      expect(vm.over, isFalse);
    });

    test('a wrong final score can be undone at game point', () async {
      final vm = await tracker(gameTo: 1);
      final ids = seven(vm);
      scorePoint(vm, ids);
      expect(vm.over, isTrue);
      expect(vm.canUndo, isTrue);
      vm.undo();
      expect(vm.over, isFalse);
      expect(vm.game!.ourScore, 0);
      expect(vm.holder, ids[1]);
    });

    test('changes from before the screen opened still step back', () async {
      final first = await tracker();
      final ids = seven(first);
      first.useLine(ids);
      first.tapPlayer(ids[0]);
      first.tapPlayer(ids[1]);
      await pumpEventQueue();
      final reopened = GameTrackerViewModel(
        teamId: 't1',
        gameId: first.gameId,
        statsRepository: stats,
        teamRepository: teams,
        authRepository: FakeAuthRepository(user: testUser),
      );
      await pumpEventQueue();
      expect(reopened.undoLabel, contains('→'));
      reopened.undo();
      expect(reopened.currentPoint!.actions, hasLength(1));
    });
  });

  group('deleting a game', () {
    test('admins can; players with stats access cannot', () async {
      final vm = await tracker();
      expect(vm.canDelete, isTrue);
      await vm.deleteGame.execute();
      final games = await stats.watchGames('t1').first;
      expect(games.where((g) => g.id == vm.gameId), isEmpty);

      teams.teams['t1'] = teamWith(
        {'boss': TeamRole.owner, 'u1': TeamRole.player},
        statKeepers: {'u1'},
      );
      final keeper = await tracker();
      expect(keeper.canEdit, isTrue);
      expect(keeper.canDelete, isFalse);
    });
  });
}
