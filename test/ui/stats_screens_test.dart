import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/stats/mock_stats_repository.dart';
import 'package:frisbee_app/domain/models/stats.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/team_event.dart';
import 'package:frisbee_app/ui/stats/view_models/game_tracker_viewmodel.dart';
import 'package:frisbee_app/ui/stats/view_models/stats_viewmodel.dart';
import 'package:frisbee_app/ui/stats/widgets/game_screen.dart';
import 'package:frisbee_app/ui/stats/widgets/stats_tab.dart';
import 'package:frisbee_app/utils/result.dart';

import '../testing/fakes.dart';

void main() {
  late MockStatsRepository stats;
  late FakeTeamRepository teams;

  setUp(() {
    teams = FakeTeamRepository()
      ..teams['t1'] = teamWith({'u1': TeamRole.owner});
    stats = MockStatsRepository(teamRepository: teams);
  });

  Future<void> phone(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(380, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: child));
    await tester.pumpAndSettle();
  }

  testWidgets('stats tab shows folders, games and the add button', (
    tester,
  ) async {
    final vm = StatsViewModel(
      teamId: 't1',
      statsRepository: stats,
      eventRepository: FakeEventRepository(),
      teamRepository: teams,
      authRepository: FakeAuthRepository(user: testUser),
    );
    await phone(tester, StatsTab(viewModel: vm));
    expect(find.text('Fall Classic'), findsOneWidget);
    expect(find.text('vs Alumni scrimmage'), findsOneWidget);
    expect(find.text('Game / tournament'), findsOneWidget);

    await tester.tap(find.text('How stats work'));
    await tester.pumpAndSettle();
    expect(find.text('Legend'), findsOneWidget);
    expect(find.text('Hand Blocks'), findsOneWidget, reason: 'legend');
    await tester.dragUntilVisible(
      find.text('Team O Efficiency'),
      find.byType(ListView).last,
      const Offset(0, -300),
    );
    await tester.tap(find.text('Team O Efficiency'));
    await tester.pumpAndSettle();
    expect(find.text('O points we scored'), findsOneWidget);
    expect(find.text('O points played'), findsOneWidget);
    final tile = find.textContaining('The defender guarding the thrower');
    await tester.dragUntilVisible(
      tile,
      find.byType(ListView).last,
      const Offset(0, -400),
    );
    expect(find.text('Number of hand blocks'), findsNothing);
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.text('Number of hand blocks'), findsOneWidget);
    expect(find.text('* Each one is +2 on plus/minus.'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    // Folders open the tournament page; games aren't listed inline.
    expect(find.text('Open folder'), findsNothing);
    expect(find.text('vs Sockeye'), findsNothing);
  });

  testWidgets('tracker plays an O point at phone width', (tester) async {
    final games = await stats.watchGames('t1').first;
    final live = games.firstWhere((g) => !g.finished);
    final vm = GameTrackerViewModel(
      teamId: 't1',
      gameId: live.id,
      statsRepository: stats,
      teamRepository: teams,
      authRepository: FakeAuthRepository(user: testUser),
    );
    await phone(tester, GameScreen(viewModel: vm));
    // Receive this point so it starts on O.
    vm.setSide(Side.offense);
    await tester.pumpAndSettle();
    expect(find.text('Pick 7 more'), findsOneWidget);
    await tester.tap(find.text('Last O line'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start point'));
    await tester.pumpAndSettle();
    final line = vm.currentPoint!.line;
    await tester.tap(find.text(vm.nameOf(line[0])).first);
    await tester.tap(find.text(vm.nameOf(line[1])).first);
    await tester.pumpAndSettle();
    final before = vm.game!.ourScore;
    await tester.tap(find.text('Score'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Tap who caught it'), findsOneWidget);
    await tester.tap(find.text(vm.nameOf(line[2])).first);
    await tester.pumpAndSettle();
    expect(vm.game!.ourScore, before + 1);

    // After we score, the lineup card is back for a D point and starting
    // it opens the pull timer.
    expect(find.text('We scored! Now we pull.'), findsOneWidget);
    await tester.tap(find.text('Last D line'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start point & pull'));
    await tester.pumpAndSettle();
    expect(find.text("Who's pulling?"), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(vm.canPull, isTrue);
  });

  testWidgets('new game can create its schedule event', (tester) async {
    final events = FakeEventRepository();
    final vm = StatsViewModel(
      teamId: 't1',
      statsRepository: stats,
      eventRepository: events,
      teamRepository: teams,
      authRepository: FakeAuthRepository(user: testUser),
    );
    await phone(tester, StatsTab(viewModel: vm));
    await tester.tap(find.text('Game / tournament'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New game'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No events yet. Create one'));
    await tester.pumpAndSettle();
    expect(find.text('Scrimmage'), findsOneWidget);
    await tester.tap(find.text('Add to schedule'));
    await tester.pumpAndSettle();

    final saved = events.events.values.single;
    expect(saved.title, 'Scrimmage');
    expect(saved.type, EventType.practice);
    expect(find.textContaining('Scrimmage · Practice'), findsOneWidget);
  });

  test('a game linked to an event starts with its lines', () async {
    final events = FakeEventRepository();
    final vm = StatsViewModel(
      teamId: 't1',
      statsRepository: stats,
      eventRepository: events,
      teamRepository: teams,
      authRepository: FakeAuthRepository(user: testUser),
    );
    await vm.createEvent.execute((
      title: 'Practice',
      type: EventType.practice,
      startsAt: DateTime(2026, 10, 28, 18),
    ));
    final event = (vm.createEvent.result! as Ok<TeamEvent>).value;
    final players = await stats.watchPlayers('t1').first;
    await stats.saveGame(
      't1',
      StatsGame(
        id: '',
        opponent: 'Scrimmage 1',
        date: event.startsAt,
        eventId: event.id,
        lines: [
          StatLine(
            id: 'l1',
            name: 'Blue',
            players: [for (final p in players.take(7)) p.id],
          ),
        ],
      ),
    );
    await pumpEventQueue();
    expect(vm.linkableEvents(EventType.game).map((e) => e.id), [event.id]);
    await vm.createGame.execute((
      opponent: 'Scrimmage 2',
      date: event.startsAt,
      gameTo: 11,
      timeoutsPerHalf: 2,
      event: event,
    ));
    final id = (vm.createGame.result! as Ok<String>).value;
    final game = (await stats.watchGames('t1').first).firstWhere(
      (g) => g.id == id,
    );
    expect(game.lines.single.name, 'Blue');
    vm.dispose();
  });

  testWidgets('game has a Lines tab to build lines', (tester) async {
    final games = await stats.watchGames('t1').first;
    final scrimmage = games.firstWhere((g) => g.tournamentId == null);
    final vm = GameTrackerViewModel(
      teamId: 't1',
      gameId: scrimmage.id,
      statsRepository: stats,
      teamRepository: teams,
      authRepository: FakeAuthRepository(user: testUser),
    );
    await phone(tester, GameScreen(viewModel: vm));
    await tester.tap(find.text('Lines'));
    await tester.pumpAndSettle();
    expect(find.text('No lines yet'), findsOneWidget);
    expect(find.text('Import lines'), findsOneWidget);
    await tester.tap(find.text('Import lines'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fall Classic'));
    await tester.pumpAndSettle();
    expect(find.text('Imported 2 lines'), findsOneWidget);
    expect(vm.savedLines, hasLength(2));
  });

  testWidgets('point log tags plays and shows timeouts', (tester) async {
    final games = await stats.watchGames('t1').first;
    final done = games.firstWhere((g) => g.over);
    final vm = GameTrackerViewModel(
      teamId: 't1',
      gameId: done.id,
      statsRepository: stats,
      teamRepository: teams,
      authRepository: FakeAuthRepository(user: testUser),
    );
    await phone(tester, GameScreen(viewModel: vm));
    expect(find.textContaining('Timeouts · Us 2'), findsOneWidget);
    await tester.tap(find.text('Points'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining(RegExp(r'^(PULL|PICKUP|CATCH|GOAL|BREAK)$')),
      findsWidgets,
    );
    expect(
      find.textContaining(RegExp(r'^(Score|Break|Opp score) · ')),
      findsWidgets,
    );
    await tester.dragUntilVisible(
      find.textContaining('HALFTIME'),
      find.byType(ListView).last,
      const Offset(0, -300),
    );
    expect(find.textContaining('HALFTIME'), findsOneWidget);
  });
}
