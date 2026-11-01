import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/player_profile.dart';
import 'package:frisbee_app/domain/models/roster_player.dart';
import 'package:frisbee_app/domain/models/stats.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/explore/view_models/player_search_viewmodel.dart';
import 'package:frisbee_app/ui/profile/view_models/player_profile_viewmodel.dart';
import 'package:frisbee_app/ui/profile/view_models/profile_viewmodel.dart';
import 'package:frisbee_app/ui/profile/widgets/profile_screen.dart';

import '../testing/fakes.dart';

void main() {
  late FakeAuthRepository auth;
  late FakeTeamRepository teams;
  late FakeProfileRepository profiles;
  late FakeStatsRepository stats;

  final game = StatsGame(
    id: 'g1',
    opponent: 'Rival',
    date: DateTime(2026, 6, 1),
    points: const [
      StatPoint(
        line: ['r1', 'r2'],
        startedOn: Side.offense,
        actions: [
          StatAction(StatKind.catch_, playerId: 'r2', throwerId: 'r1'),
          StatAction(StatKind.goal, playerId: 'r1', throwerId: 'r2'),
        ],
        result: PointResult.weScored,
      ),
    ],
  );

  setUp(() {
    auth = FakeAuthRepository(user: testUser);
    teams = FakeTeamRepository();
    teams.teams['t1'] = teamWith({
      'owner': TeamRole.owner,
      testUser.uid: TeamRole.player,
    });
    teams.roster['t1'] = const [
      RosterPlayer(id: 'r1', name: 'Alex Smith', number: 17),
      RosterPlayer(id: 'r2', name: 'Bo', number: 3, userId: 'owner'),
      RosterPlayer(id: 'r3', name: 'Zed', number: 9),
    ];
    profiles = FakeProfileRepository();
    stats = FakeStatsRepository()..games['t1'] = [game];
  });

  PlayerProfileViewModel profileOf(String uid) => PlayerProfileViewModel(
    uid: uid,
    profileRepository: profiles,
    authRepository: auth,
    teamRepository: teams,
    statsRepository: stats,
    directMessageRepository: FakeDirectMessageRepository(),
  );

  group('own profile', () {
    test('suggests the roster spot matching your name', () async {
      final vm = profileOf(testUser.uid);
      await pumpEventQueue();
      expect(vm.isMe, isTrue);
      expect(vm.claimable.single.team.id, 't1');
      // Bo is linked to someone else; Alex matches the name.
      expect([for (final p in vm.claimable.single.players) p.id], ['r1', 'r3']);
      expect(vm.totals.isEmpty, isTrue);
      vm.dispose();
    });

    test('claiming a spot counts its stats and publishes them', () async {
      final vm = profileOf(testUser.uid);
      await pumpEventQueue();
      await vm.claim.execute(('t1', 'r1'));
      await pumpEventQueue();

      expect(teams.links.last, ('t1', 'r1', testUser.uid));
      expect(vm.claimable, isEmpty);
      expect(vm.totals.games, 1);
      expect(vm.totals.goals, 1);
      expect(vm.totals.completions, 1);
      expect(vm.seasons, ['2026']);
      expect(vm.primaryTeam?.number, 17);
      expect(vm.summary.games.single.won, isTrue);
      expect(profiles.published.last.seasons['2026']?.goals, 1);
      vm.dispose();
    });

    test('hidden parts are not published, but you still see them', () async {
      teams.roster['t1'] = const [
        RosterPlayer(id: 'r1', name: 'Alex Smith', userId: 'u1'),
      ];
      final vm = profileOf(testUser.uid);
      await pumpEventQueue();
      await vm.saveDetails.execute(
        const ProfileDetails(
          bio: 'Handler',
          school: 'State',
          visibility: ProfileVisibility(stats: false, games: false),
        ),
      );
      await pumpEventQueue();

      final last = profiles.published.last;
      expect(last.seasons, isEmpty);
      expect(last.games, isEmpty);
      expect(last.teams.single.name, 'Team');
      expect(vm.totals.goals, 1);
      expect(vm.details.school, 'State');
      vm.dispose();
    });
  });

  group("another player's profile", () {
    test('shows what they published', () async {
      profiles.put(
        PlayerProfile(
          uid: 'p2',
          name: 'Pat',
          details: const ProfileDetails(school: 'Tech'),
          summary: ProfileSummary(
            seasons: {
              '2025': const StatTotals(games: 2, goals: 3),
              '2026': const StatTotals(games: 1, goals: 1),
            },
          ),
        ),
      );
      final vm = profileOf('p2');
      await pumpEventQueue();
      expect(vm.isMe, isFalse);
      expect(vm.name, 'Pat');
      expect(vm.seasons, ['2026', '2025']);
      expect(vm.totals.goals, 4);
      vm.selectSeason('2025');
      expect(vm.totals.goals, 3);
      expect(vm.claimable, isEmpty);
      vm.dispose();
    });

    testWidgets('hidden stats read as private, and there is no Edit', (
      tester,
    ) async {
      profiles.put(
        const PlayerProfile(
          uid: 'p2',
          name: 'Pat',
          details: ProfileDetails(
            bio: 'Cutter from Tech.',
            visibility: ProfileVisibility(stats: false),
          ),
        ),
      );
      final vm = profileOf('p2');
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: PlayerProfileScreen(viewModel: vm),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Pat'), findsOneWidget);
      expect(find.text('Cutter from Tech.'), findsOneWidget);
      expect(find.text('Stats are private.'), findsOneWidget);
      expect(find.text('Message'), findsOneWidget);
      expect(find.text('Edit profile'), findsNothing);
      expect(find.text('Appearance'), findsNothing);
      vm.dispose();
    });
  });

  test('player search matches name, school and team', () async {
    profiles
      ..put(
        const PlayerProfile(
          uid: 'p2',
          name: 'Pat Lee',
          details: ProfileDetails(school: 'State University'),
          summary: ProfileSummary(
            teams: [ProfileTeam(id: 't9', name: 'Riptide')],
          ),
        ),
      )
      ..put(const PlayerProfile(uid: 'p3', name: 'Sam Ortiz'));
    final vm = PlayerSearchViewModel(profileRepository: profiles);
    Future<List<String>> find(String q) async {
      await vm.search.execute(q);
      return [for (final p in vm.results) p.uid];
    }

    expect(await find('pat'), ['p2']);
    expect(await find('state'), ['p2']);
    expect(await find('ript'), ['p2']);
    expect(await find('sam'), ['p3']);
    expect(await find('s'), isEmpty);
    expect(await find('nobody'), isEmpty);
    expect(vm.noMatches, isTrue);
    vm.dispose();
  });

  testWidgets('own profile has settings, and the theme toggle works', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final theme = FakeThemeRepository();
    final settings = ProfileViewModel(
      authRepository: auth,
      themeRepository: theme,
      notificationRepository: FakeNotificationRepository(),
    );
    final vm = profileOf(testUser.uid);
    await tester.pumpWidget(
      ListenableBuilder(
        listenable: theme,
        builder: (_, _) => MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: theme.themeMode,
          home: PlayerProfileScreen(viewModel: vm, settings: settings),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Edit profile'), findsOneWidget);
    expect(find.text("I'm Alex Smith"), findsOneWidget);

    expect(find.text('Appearance'), findsOneWidget);
    final context = tester.element(find.byType(PlayerProfileScreen));
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(theme.themeMode, ThemeMode.dark);
    expect(Theme.of(context).brightness, Brightness.dark);

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(theme.themeMode, ThemeMode.light);
    vm.dispose();
  });

  testWidgets('edit profile saves details and visibility', (tester) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final vm = profileOf(testUser.uid);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: PlayerProfileScreen(viewModel: vm),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit profile'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Bio'),
      'Deep cutter.',
    );
    await tester.enterText(find.widgetWithText(TextField, 'School'), 'State');
    await tester.tap(find.widgetWithText(SwitchListTile, 'Stats'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final saved = profiles.profiles[testUser.uid]!.details;
    expect(saved.bio, 'Deep cutter.');
    expect(saved.school, 'State');
    expect(saved.visibility.stats, isFalse);
    expect(find.text('Deep cutter.'), findsOneWidget);
    vm.dispose();
  });

  testWidgets('lays out on a phone with stats and games', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    teams.roster['t1'] = const [
      RosterPlayer(id: 'r1', name: 'Alex Smith', number: 17, userId: 'u1'),
    ];
    final vm = profileOf(testUser.uid);
    for (final brightness in [AppTheme.light, AppTheme.dark]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: brightness,
          home: PlayerProfileScreen(viewModel: vm),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('By the numbers'), findsOneWidget);
      expect(find.text('17'), findsOneWidget);
      await tester.tap(find.text('Stats'));
      await tester.pumpAndSettle();
      expect(find.text('Season by season'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Overview'));
      await tester.pumpAndSettle();
    }
    vm.dispose();
  });
}
