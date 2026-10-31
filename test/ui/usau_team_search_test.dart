import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/notification/notification_repository.dart';
import 'package:frisbee_app/data/repositories/auth/auth_repository.dart';
import 'package:frisbee_app/data/repositories/chat/chat_repository.dart';
import 'package:frisbee_app/data/repositories/direct_message/direct_message_repository.dart';
import 'package:frisbee_app/data/repositories/event/event_repository.dart';
import 'package:frisbee_app/data/repositories/playbook/play_repository.dart';
import 'package:frisbee_app/data/repositories/ranking/ranking_repository.dart';
import 'package:frisbee_app/data/repositories/stats/mock_stats_repository.dart';
import 'package:frisbee_app/data/repositories/stats/stats_repository.dart';
import 'package:frisbee_app/data/repositories/team/team_repository.dart';
import 'package:frisbee_app/data/repositories/theme/theme_repository.dart';
import 'package:frisbee_app/data/repositories/tournament/tournament_repository.dart';
import 'package:frisbee_app/data/repositories/usau_team/usau_team_repository.dart';
import 'package:frisbee_app/data/services/file_picker_service.dart';
import 'package:frisbee_app/domain/models/ranking.dart';
import 'package:frisbee_app/domain/models/usau_team.dart';
import 'package:frisbee_app/routing/router.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/rankings/widgets/usau_team_screen.dart';
import 'package:frisbee_app/ui/teams/view_models/usau_team_search_viewmodel.dart';
import 'package:frisbee_app/ui/teams/widgets/team_search_screen.dart';
import 'package:frisbee_app/ui/teams/widgets/teams_screen.dart';
import 'package:frisbee_app/ui/teams/widgets/usau_team_search_screen.dart';
import 'package:frisbee_app/utils/result.dart';
import 'package:provider/provider.dart';

import '../testing/fakes.dart';

const _divisions = [
  RankingDivision(
    key: 'club-mixed',
    label: 'Club Mixed',
    entries: [
      RankingEntry(rank: 1, teamName: 'Seattle BFG', teamUrl: 'u-bfg'),
      RankingEntry(rank: 4, teamName: 'Ring of Fire', teamUrl: 'u-ring'),
      RankingEntry(rank: 9, teamName: 'Fire Ring Club', teamUrl: 'u-frc'),
      RankingEntry(rank: 12, teamName: 'No Link', teamUrl: ''),
    ],
  ),
  RankingDivision(
    key: 'college-women',
    label: 'College Women',
    entries: [RankingEntry(rank: 2, teamName: 'Ring Women', teamUrl: 'u-rw')],
  ),
];

class _Usau implements UsauTeamRepository {
  @override
  Future<Result<UsauTeam>> getTeam(String url) async =>
      Result.ok(UsauTeam(name: 'Ring of Fire', url: url, roster: const []));
}

void main() {
  group('UsauTeamSearchViewModel', () {
    Future<UsauTeamSearchViewModel> load() async {
      final vm = UsauTeamSearchViewModel(
        rankingRepository: FakeRankingRepository(_divisions),
      );
      await pumpEventQueue();
      return vm;
    }

    test('matches by name across divisions, exact first then rank', () async {
      final vm = await load();
      expect(vm.results, isEmpty);
      expect(vm.divisions, ['Club Mixed', 'College Women']);

      vm.setQuery('ring');
      expect(vm.results.map((c) => c.entry.teamName), [
        'Ring Women',
        'Ring of Fire',
        'Fire Ring Club',
      ]);

      vm.setQuery('Ring of fire');
      expect(vm.results.first.entry.teamName, 'Ring of Fire');

      // Teams without a page link can't be opened, so they're left out.
      vm.setQuery('no link');
      expect(vm.results, isEmpty);
    });

    test('filters by ranking list', () async {
      final vm = await load();
      vm
        ..setQuery('ring')
        ..setDivision('Club Mixed');
      expect(vm.results.map((c) => c.division).toSet(), {'Club Mixed'});
      vm.setDivision(null);
      expect(vm.results, hasLength(3));
    });
  });

  testWidgets('Teams search opens a USA Ultimate team and back returns', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final auth = FakeAuthRepository(user: testUser);
    final teams = FakeTeamRepository();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthRepository>.value(value: auth),
          Provider<TeamRepository>.value(value: teams),
          ChangeNotifierProvider<ThemeRepository>.value(
            value: FakeThemeRepository(),
          ),
          Provider<PlayRepository>.value(value: FakePlayRepository()),
          Provider<NotificationRepository>.value(
            value: FakeNotificationRepository(),
          ),
          Provider<DirectMessageRepository>.value(
            value: FakeDirectMessageRepository(),
          ),
          Provider<ChatRepository>.value(value: FakeChatRepository()),
          Provider<FilePickerService>.value(value: FakeFilePickerService()),
          Provider<EventRepository>.value(value: FakeEventRepository()),
          Provider<StatsRepository>.value(
            value: MockStatsRepository(teamRepository: teams),
          ),
          Provider<TournamentRepository>.value(
            value: FakeTournamentRepository(const []),
          ),
          Provider<RankingRepository>.value(
            value: FakeRankingRepository(_divisions),
          ),
          Provider<UsauTeamRepository>.value(value: _Usau()),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light,
          routerConfig: router(auth),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Teams').last);
    await tester.pumpAndSettle();
    expect(find.byType(TeamsScreen), findsOneWidget);

    await tester.tap(find.byTooltip('Find a team'));
    await tester.pumpAndSettle();
    expect(find.byType(TeamSearchScreen), findsOneWidget);

    await tester.tap(find.text('Search USA Ultimate rankings'));
    await tester.pumpAndSettle();
    expect(find.byType(UsauTeamSearchScreen), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'ring of');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ring of Fire'));
    await tester.pumpAndSettle();
    expect(find.byType(UsauTeamScreen), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(UsauTeamSearchScreen), findsOneWidget);
    expect(find.text('Ring of Fire'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(TeamSearchScreen), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(TeamsScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
