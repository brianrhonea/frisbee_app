import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:frisbee_app/data/services/firestore_utils.dart';
import 'package:frisbee_app/domain/models/player_profile.dart';
import 'package:frisbee_app/domain/models/roster_player.dart';
import 'package:frisbee_app/domain/models/stats.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/routing/routes.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/core/ui/slide_over_page.dart';
import 'package:frisbee_app/ui/explore/view_models/player_search_viewmodel.dart';
import 'package:frisbee_app/ui/explore/widgets/explore_screen.dart';
import 'package:frisbee_app/ui/profile/view_models/player_profile_viewmodel.dart';
import 'package:frisbee_app/ui/profile/view_models/profile_viewmodel.dart';
import 'package:frisbee_app/ui/profile/widgets/profile_screen.dart';
import 'package:frisbee_app/ui/settings/widgets/settings_screen.dart';
import 'package:frisbee_app/ui/teams/view_models/team_search_viewmodel.dart';

import '../testing/fakes.dart';
import '../testing/moderation_fakes.dart';

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
    test('an unlinked user has no spot and nothing to claim', () async {
      final vm = profileOf(testUser.uid);
      await pumpEventQueue();
      expect(vm.isMe, isTrue);
      // Only a team admin links people to roster spots.
      expect(vm.linkedSpots, isEmpty);
      expect(vm.totals.isEmpty, isTrue);
      vm.dispose();
    });

    test('a spot an admin links to you counts its stats and publishes '
        'them', () async {
      final vm = profileOf(testUser.uid);
      await pumpEventQueue();
      // The admin's link call, as the team's roster does it.
      await teams.linkPlayer('t1', 'r1', testUser.uid);
      await pumpEventQueue();

      expect(vm.linkedSpots.single.team.id, 't1');
      expect(vm.linkedSpots.single.player.id, 'r1');
      expect(vm.totals.games, 1);
      expect(vm.totals.goals, 1);
      expect(vm.totals.completions, 1);
      expect(vm.seasons, ['2026']);
      expect(vm.primaryTeam?.number, 17);
      expect(vm.summary.games.single.won, isTrue);
      expect(profiles.published.last.seasons['2026']?.goals, 1);
      expect(profiles.published.last.teamSeasons['t1']?['2026']?.goals, 1);
      vm.dispose();
    });

    test('what is published reads back the same, so it is not '
        'published again', () async {
      final vm = profileOf(testUser.uid);
      await pumpEventQueue();
      await teams.linkPlayer('t1', 'r1', testUser.uid);
      await pumpEventQueue();
      final sent = vm.summary;
      expect(sent.games, isNotEmpty);
      // As ProfileRepositoryFirebase writes it, and as Firestore hands it
      // back (dates come back as Timestamps).
      Object? stored(Object? v) => switch (v) {
        DateTime d => Timestamp.fromDate(d),
        Map m => m.map((k, v) => MapEntry('$k', stored(v))),
        List l => l.map(stored).toList(),
        _ => v,
      };
      final doc = stored({
        'name': 'Alex Smith',
        'teams': [for (final t in sent.teams) t.toMap()],
        'stats': {for (final e in sent.seasons.entries) e.key: e.value.toMap()},
        'teamStats': {
          for (final t in sent.teamSeasons.entries)
            t.key: {for (final e in t.value.entries) e.key: e.value.toMap()},
        },
        'games': [for (final g in sent.games) g.toMap()],
      });
      final back = PlayerProfile.fromMap(
        testUser.uid,
        plainData(doc! as Map<String, dynamic>),
      ).summary;
      expect(sent.teamSeasons, isNotEmpty);
      expect(back.sameAs(sent), isTrue);
      vm.dispose();
    });

    test(
      'hiding teams keeps per-team stats out of what is published',
      () async {
        final vm = profileOf(testUser.uid);
        await pumpEventQueue();
        await teams.linkPlayer('t1', 'r1', testUser.uid);
        await pumpEventQueue();
        expect(profiles.published.last.teamSeasons, isNotEmpty);
        await vm.saveDetails.execute(
          const ProfileDetails(visibility: ProfileVisibility(teams: false)),
        );
        await pumpEventQueue();
        final last = profiles.published.last;
        expect(last.seasons['2026']?.goals, 1);
        expect(last.teamSeasons, isEmpty);
        vm.dispose();
      },
    );

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
      expect(vm.linkedSpots, isEmpty);
      vm.dispose();
    });

    test(
      'the Team filter narrows the numbers and seasons to one team',
      () async {
        profiles.put(
          PlayerProfile(
            uid: 'p2',
            name: 'Pat',
            summary: ProfileSummary(
              teams: const [
                ProfileTeam(id: 't1', name: 'Riptide'),
                ProfileTeam(id: 't2', name: 'Sol'),
                ProfileTeam(id: 't3', name: 'No stats'),
              ],
              seasons: {
                '2025': const StatTotals(games: 2, goals: 3),
                '2026': const StatTotals(games: 3, goals: 5),
              },
              teamSeasons: {
                't1': {
                  '2025': const StatTotals(games: 2, goals: 3),
                  '2026': const StatTotals(games: 1, goals: 1),
                },
                't2': {'2026': const StatTotals(games: 2, goals: 4)},
              },
            ),
          ),
        );
        final vm = profileOf('p2');
        await pumpEventQueue();
        expect(
          [for (final t in vm.statsChoice.options) t.name],
          ['Riptide', 'Sol'],
        );
        expect(vm.totals.goals, 8);

        vm.selectSeason('2025');
        vm.selectStatsTeam('t2');
        // Sol has no 2025, so the season falls back to every season.
        expect(vm.seasons, ['2026']);
        expect(vm.season, isNull);
        expect(vm.totals.goals, 4);
        expect(vm.career.games, 2);

        vm.selectStatsTeam('t1');
        vm.selectSeason('2025');
        expect(vm.totals.goals, 3);

        vm.selectStatsTeam(null);
        expect(vm.totals.goals, 3);
        expect(vm.career.goals, 8);
        vm.dispose();
      },
    );

    test('one team with stats: no Team filter', () async {
      profiles.put(
        PlayerProfile(
          uid: 'p2',
          name: 'Pat',
          summary: ProfileSummary(
            teams: const [
              ProfileTeam(id: 't1', name: 'Riptide'),
              ProfileTeam(id: 't2', name: 'Sol'),
            ],
            seasons: {'2026': const StatTotals(games: 1, goals: 1)},
            teamSeasons: {
              't1': {'2026': const StatTotals(games: 1, goals: 1)},
              // A team that isn't on their published teams isn't offered.
              'gone': {'2026': const StatTotals(games: 1, goals: 1)},
            },
          ),
        ),
      );
      final vm = profileOf('p2');
      await pumpEventQueue();
      expect(vm.statsChoice.options, isEmpty);
      vm.selectStatsTeam('t1');
      expect(vm.statsChoice.teamId, isNull);
      vm.dispose();
    });

    testWidgets('the Team menu sits beside the season menu', (tester) async {
      tester.view.physicalSize = const Size(1400, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      profiles.put(
        PlayerProfile(
          uid: 'p2',
          name: 'Pat',
          summary: ProfileSummary(
            teams: const [
              ProfileTeam(id: 't1', name: 'Riptide'),
              ProfileTeam(id: 't2', name: 'Sol'),
            ],
            seasons: {'2026': const StatTotals(games: 3, goals: 5)},
            teamSeasons: {
              't1': {'2026': const StatTotals(games: 1, goals: 1)},
              't2': {'2026': const StatTotals(games: 2, goals: 4)},
            },
          ),
        ),
      );
      final vm = profileOf('p2');
      addTearDown(vm.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: PlayerProfileScreen(viewModel: vm),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stats').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('All teams').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sol').last);
      await tester.pumpAndSettle();
      expect(vm.statsChoice.teamId, 't2');
      expect(find.text('Season by season · Sol'), findsOneWidget);
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

  testWidgets('Stall 10 staff have a badge by their name', (tester) async {
    profiles.put(const PlayerProfile(uid: 'p2', name: 'Pat'));
    profiles.put(const PlayerProfile(uid: 'p3', name: 'Quinn'));
    final mod = FakeModerationRepository()..staff.add('p2');
    PlayerProfileViewModel vmOf(String uid) => PlayerProfileViewModel(
      uid: uid,
      profileRepository: profiles,
      authRepository: auth,
      teamRepository: teams,
      statsRepository: stats,
      directMessageRepository: FakeDirectMessageRepository(),
      moderationRepository: mod,
    );
    for (final (uid, badge) in [('p2', findsOneWidget), ('p3', findsNothing)]) {
      final vm = vmOf(uid);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: PlayerProfileScreen(viewModel: vm, key: ValueKey(uid)),
        ),
      );
      await tester.pumpAndSettle();
      expect(vm.isStaff, badge == findsOneWidget);
      expect(find.text('STALL 10 STAFF'), badge);
      vm.dispose();
    }
  });

  testWidgets('teams of more than one kind are colored and filter by kind', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    profiles.put(
      const PlayerProfile(
        uid: 'p2',
        name: 'Pat',
        summary: ProfileSummary(
          teams: [
            ProfileTeam(id: 't1', name: 'Riptide'),
            ProfileTeam(id: 't2', name: 'Sol'),
            ProfileTeam(
              id: 'g1',
              name: 'Denver Pickup',
              kind: TeamKind.community,
            ),
          ],
        ),
      ),
    );
    final vm = profileOf('p2');
    addTearDown(vm.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: PlayerProfileScreen(viewModel: vm),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Teams').first);
    await tester.pumpAndSettle();
    expect(find.text('All 3'), findsOneWidget);
    expect(find.text('Teams 2'), findsOneWidget);
    expect(find.text('Pickup communities 1'), findsOneWidget);
    expect(find.text('Team'), findsNWidgets(2));
    expect(find.text('Pickup'), findsOneWidget);

    await tester.tap(find.text('Pickup communities 1'));
    await tester.pumpAndSettle();
    expect(find.text('Denver Pickup'), findsOneWidget);
    expect(find.text('Riptide'), findsNothing);

    // One kind only: nothing to filter.
    vm.setTeamKindFilter(null);
    profiles.put(
      const PlayerProfile(
        uid: 'p2',
        name: 'Pat',
        summary: ProfileSummary(
          teams: [
            ProfileTeam(id: 't1', name: 'Riptide'),
            ProfileTeam(id: 't2', name: 'Sol'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(vm.filtersTeams, isFalse);
    expect(find.text('All 2'), findsNothing);
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

  testWidgets('the gear opens Settings over the profile; General sets the '
      'theme', (tester) async {
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final theme = FakeThemeRepository();
    ProfileViewModel settings() => ProfileViewModel(
      authRepository: auth,
      themeRepository: theme,
      notificationRepository: FakeNotificationRepository(),
      directMessageRepository: FakeDirectMessageRepository(),
    );
    final vm = profileOf(testUser.uid);
    addTearDown(vm.dispose);
    final router = GoRouter(
      initialLocation: Routes.profile,
      routes: [
        GoRoute(
          path: Routes.profile,
          builder: (_, _) => PlayerProfileScreen(viewModel: vm),
        ),
        GoRoute(
          path: Routes.settings,
          pageBuilder: (context, state) => slideOverPage(
            context,
            state.pageKey,
            SettingsScreen(viewModel: settings()),
            panelOnWide: true,
          ),
          routes: [
            GoRoute(
              path: 'general',
              pageBuilder: (context, state) => slideOverPage(
                context,
                state.pageKey,
                GeneralSettingsScreen(viewModel: settings()),
                panelOnWide: true,
                dim: false,
              ),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ListenableBuilder(
        listenable: theme,
        builder: (_, _) => MaterialApp.router(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: theme.themeMode,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Edit profile'), findsOneWidget);
    // No claim prompt any more: an admin links you to a roster spot.
    expect(find.text("I'm Alex Smith"), findsNothing);
    expect(find.text('Appearance'), findsNothing, reason: 'not on the profile');

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    // A panel down the right edge, the profile still behind it.
    expect(tester.getSize(find.byType(SettingsScreen)).width, 440);
    expect(find.byType(PlayerProfileScreen), findsOneWidget);

    await tester.tap(find.text('General'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(theme.themeMode, ThemeMode.dark);
    final context = tester.element(find.byType(GeneralSettingsScreen));
    expect(Theme.of(context).brightness, Brightness.dark);

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(theme.themeMode, ThemeMode.light);

    // Back to Settings, which shows the choice.
    // (Settings' own back arrow is under General's panel.)
    await tester.tap(find.byType(BackButton).last);
    await tester.pumpAndSettle();
    expect(find.byType(GeneralSettingsScreen), findsNothing);
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'General'),
        matching: find.text('Light'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('edit profile saves details and keeps visibility', (
    tester,
  ) async {
    profiles.put(
      PlayerProfile(
        uid: testUser.uid,
        name: 'Test User',
        details: const ProfileDetails(
          visibility: ProfileVisibility(stats: false),
        ),
      ),
    );
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
    expect(find.widgetWithText(SwitchListTile, 'Stats'), findsNothing);
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

  group('roster spot on the profile', () {
    Future<void> pumpProfile(
      WidgetTester tester,
      PlayerProfileViewModel vm,
    ) async {
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: PlayerProfileScreen(viewModel: vm),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('an unlinked player is never asked to claim a spot', (
      tester,
    ) async {
      // Alex Smith's name matches an unlinked spot: it used to be offered.
      final vm = profileOf(testUser.uid);
      addTearDown(vm.dispose);
      await pumpProfile(tester, vm);
      expect(find.textContaining('Link your stats'), findsNothing);
      expect(find.text('Which player on the roster is you?'), findsNothing);
      expect(find.textContaining("I'm "), findsNothing);
      expect(find.text('Roster spots'), findsNothing);
    });

    testWidgets('a linked player sees the spot and can unlink', (tester) async {
      teams.roster['t1'] = const [
        RosterPlayer(id: 'r1', name: 'Alex Smith', number: 17, userId: 'u1'),
      ];
      final vm = profileOf(testUser.uid);
      addTearDown(vm.dispose);
      await pumpProfile(tester, vm);
      expect(find.text('Roster spots'), findsOneWidget);
      expect(find.text('Alex Smith · #17'), findsOneWidget);
      await tester.tap(find.text('Unlink'));
      await tester.pumpAndSettle();
      expect(find.text('Unlink from Team?'), findsOneWidget);
      // Backing out changes nothing.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(teams.links, isEmpty);
      await tester.tap(find.text('Unlink'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Unlink'));
      await tester.pumpAndSettle();
      expect(teams.links.single, ('t1', 'r1', null));
      expect(vm.linkedSpots, isEmpty);
      expect(find.text('Roster spots'), findsNothing);
    });

    testWidgets("someone else's profile shows no roster spots", (tester) async {
      profiles.put(PlayerProfile(uid: 'p2', name: 'Pat'));
      final vm = profileOf('p2');
      addTearDown(vm.dispose);
      await pumpProfile(tester, vm);
      expect(find.text('Roster spots'), findsNothing);
      expect(find.text('Unlink'), findsNothing);
    });
  });

  testWidgets('the profile shows the @username under the name', (tester) async {
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    auth = FakeAuthRepository(user: testUser.withUsername('alex_7'));
    final vm = profileOf(testUser.uid);
    addTearDown(vm.dispose);
    await tester.pumpWidget(
      MaterialApp(home: PlayerProfileScreen(viewModel: vm)),
    );
    await tester.pumpAndSettle();
    expect(find.text('@alex_7'), findsOneWidget);

    profiles.put(
      const PlayerProfile(uid: 'p2', name: 'Pat Lee', username: 'patlee'),
    );
    final other = profileOf('p2');
    addTearDown(other.dispose);
    await tester.pumpWidget(
      MaterialApp(home: PlayerProfileScreen(viewModel: other)),
    );
    await tester.pumpAndSettle();
    expect(find.text('@patlee'), findsOneWidget);
  });

  testWidgets('one search finds players and teams', (tester) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    profiles.put(
      const PlayerProfile(uid: 'p2', name: 'Riley Pike', username: 'rpike'),
    );
    final teamSearch = TeamSearchViewModel(
      teamRepository: teams,
      authRepository: auth,
    );
    final players = PlayerSearchViewModel(profileRepository: profiles);
    addTearDown(teamSearch.dispose);
    addTearDown(players.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ExploreScreen(
          viewModel: teamSearch,
          players: players,
          initialQuery: 'ri',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Riley Pike'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Events'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Teams'));
    await tester.pumpAndSettle();
    expect(find.text('Riley Pike'), findsNothing, reason: 'Teams only');
  });
}
