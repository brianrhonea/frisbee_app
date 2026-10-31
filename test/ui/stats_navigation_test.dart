import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/stats/mock_stats_repository.dart';
import 'package:frisbee_app/domain/models/stats.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/ui/stats/view_models/game_tracker_viewmodel.dart';
import 'package:frisbee_app/ui/stats/view_models/stats_viewmodel.dart';
import 'package:frisbee_app/ui/stats/view_models/tournament_viewmodel.dart';
import 'package:frisbee_app/ui/stats/widgets/game_screen.dart';
import 'package:frisbee_app/ui/stats/widgets/stats_tab.dart';
import 'package:frisbee_app/ui/stats/widgets/tournament_screen.dart';
import 'package:frisbee_app/utils/result.dart';
import 'package:go_router/go_router.dart';

import '../testing/fakes.dart';

void main() {
  late MockStatsRepository stats;
  late FakeTeamRepository teams;

  setUp(() {
    teams = FakeTeamRepository()
      ..teams['t1'] = teamWith({'u1': TeamRole.owner});
    stats = MockStatsRepository(teamRepository: teams);
  });

  Future<void> app(
    WidgetTester tester,
    String tournamentId, {
    String start = '/t',
  }) async {
    tester.view.physicalSize = const Size(380, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: start,
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => StatsTab(
            viewModel: StatsViewModel(
              teamId: 't1',
              statsRepository: stats,
              eventRepository: FakeEventRepository(),
              teamRepository: teams,
              authRepository: FakeAuthRepository(user: testUser),
            ),
          ),
          routes: [
            GoRoute(
              path: 'teams/:teamId/stats/tournaments/:tournamentId',
              builder: (_, state) => TournamentScreen(
                viewModel: TournamentViewModel(
                  teamId: 't1',
                  tournamentId: state.pathParameters['tournamentId']!,
                  statsRepository: stats,
                  teamRepository: teams,
                  authRepository: FakeAuthRepository(user: testUser),
                ),
              ),
            ),
            GoRoute(
              path: 't',
              builder: (_, _) => TournamentScreen(
                viewModel: TournamentViewModel(
                  teamId: 't1',
                  tournamentId: tournamentId,
                  statsRepository: stats,
                  teamRepository: teams,
                  authRepository: FakeAuthRepository(user: testUser),
                ),
              ),
            ),
            GoRoute(
              path: 'teams/:teamId/stats/games/:gameId',
              builder: (_, state) => GameScreen(
                viewModel: GameTrackerViewModel(
                  teamId: 't1',
                  gameId: state.pathParameters['gameId']!,
                  statsRepository: stats,
                  teamRepository: teams,
                  authRepository: FakeAuthRepository(user: testUser),
                ),
              ),
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
  }

  Future<String> newTournament() async {
    final players = await stats.watchPlayers('t1').first;
    final r = await stats.saveTournament(
      't1',
      StatsTournament(
        id: '',
        name: 'Regionals',
        startDate: DateTime(2026, 10, 28),
        roster: [for (final p in players) p.id],
      ),
    );
    return (r as Ok<String>).value;
  }

  testWidgets('tapping a folder opens the tournament page', (tester) async {
    await app(tester, '', start: '/');
    await tester.tap(find.text('Fall Classic'));
    await tester.pumpAndSettle();
    expect(find.text('Roster & lines'), findsOneWidget);
    expect(find.text('vs Sockeye'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Game / tournament'), findsOneWidget);
  });

  testWidgets('add a game to a new tournament', (tester) async {
    await app(tester, await newTournament());
    await tester.tap(find.text('Add game'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Rival');
    await tester.pump();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('vs Rival'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Back returns to the tournament, not the team page.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Regionals'), findsOneWidget);
    expect(find.text('vs Rival'), findsOneWidget);
  });

  testWidgets('line builder can be closed', (tester) async {
    await app(tester, await newTournament());
    await tester.tap(find.text('Roster & lines'));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.text('New line'),
      find.byType(ListView).last,
      const Offset(0, -300),
    );
    await tester.tap(find.text('New line'));
    await tester.pumpAndSettle();
    expect(find.text('Pick 7 more'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Pick 7 more'), findsNothing);
  });
}
