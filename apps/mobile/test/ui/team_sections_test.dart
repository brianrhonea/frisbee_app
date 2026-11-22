// New teams start simple (redesign F21): Feed, Schedule, Chat and Roster;
// the owner turns Playbook, Videos, Stats and Meetings on in Settings ›
// Sections.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:frisbee_app/data/repositories/auth/auth_repository.dart';
import 'package:frisbee_app/data/repositories/event/event_repository.dart';
import 'package:frisbee_app/data/repositories/team/team_repository.dart';
import 'package:frisbee_app/data/repositories/team/team_hints_repository.dart';
import 'package:frisbee_app/data/repositories/team/team_repository_firebase.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/schedule/widgets/team_events_tab.dart';
import 'package:frisbee_app/ui/teams/view_models/team_detail_viewmodel.dart';
import 'package:frisbee_app/ui/teams/view_models/team_home_viewmodel.dart';
import 'package:frisbee_app/ui/teams/view_models/team_settings_viewmodel.dart';
import 'package:frisbee_app/ui/teams/widgets/team_home_screen.dart';
import 'package:frisbee_app/ui/teams/widgets/team_section_screen.dart';
import 'package:frisbee_app/ui/teams/widgets/team_settings_screen.dart';
import 'package:frisbee_app/utils/result.dart';

import '../testing/fakes.dart';

const _newTeam = NewTeam(
  name: 'Haze',
  division: Division.open,
  level: CompetitionLevel.college,
);

void main() {
  group('what a new team stores', () {
    test('a team writes Playbook, Videos, Stats and Meetings off', () {
      final docs = newTeamDocs('t1', _newTeam, testUser, createdAt: 0);
      expect(docs['teams/t1']!['sections'], {
        'playbook': false,
        'videos': false,
        'stats': false,
        'meetings': false,
      });
      // Not on the public listing.
      expect(docs['teamDirectory/t1'], isNot(contains('sections')));
    });

    test('communities and organizations store none (unchanged)', () {
      for (final kind in [TeamKind.community, TeamKind.organization]) {
        final docs = newTeamDocs(
          't1',
          NewTeam(
            name: 'Pickup',
            division: Division.mixed,
            level: CompetitionLevel.pickup,
            kind: kind,
          ),
          testUser,
          createdAt: 0,
        );
        expect(docs['teams/t1'], isNot(contains('sections')));
      }
    });

    test('a team from before the switches (nothing stored) has them all', () {
      final old = Team.fromMap('t1', {'name': 'Old', 'ownerId': 'o'});
      expect(OptionalSection.values.every(old.hasSection), isTrue);
      final mixed = Team.fromMap('t1', {
        'name': 'Mixed',
        'sections': {'playbook': true, 'stats': false},
      });
      expect(mixed.sectionsOff, {OptionalSection.stats});
    });

    test('a created team has only Feed, Schedule, Chat and Roster '
        '(Tournaments under More)', () async {
      final teams = FakeTeamRepository();
      final id = (await teams.createTeam(_newTeam, testUser) as Ok).value;
      final team = teams.teams[id]!;
      final sections = TeamSection.forTeam(team);
      expect(sections, [
        TeamSection.events,
        TeamSection.chat,
        TeamSection.roster,
        TeamSection.tournaments,
        TeamSection.members,
      ]);
      expect(TeamTab.forSections(sections), [
        TeamTab.feed,
        TeamTab.schedule,
        TeamTab.chat,
        TeamTab.roster,
        TeamTab.more,
      ]);
      expect(TeamTab.moreSections(sections), [TeamSection.tournaments]);
    });

    test('a section turned on is back in its place', () {
      final team = teamWith({
        'u1': TeamRole.owner,
      }).copyWith(sectionsOff: {OptionalSection.videos});
      expect(TeamSection.forTeam(team), [
        TeamSection.events,
        TeamSection.chat,
        TeamSection.roster,
        TeamSection.playbook,
        TeamSection.stats,
        TeamSection.tournaments,
        TeamSection.members,
      ]);
    });
  });

  group('team page', () {
    late FakeTeamRepository teams;
    late TeamHintsRepositoryMemory hints;
    late FakeAuthRepository auth;
    final now = DateTime(2026, 11, 20, 12);

    setUp(() {
      teams = FakeTeamRepository();
      hints = TeamHintsRepositoryMemory();
      auth = FakeAuthRepository(user: testUser);
    });

    TeamHomeViewModel homeVm() => TeamHomeViewModel(
      teamId: 't1',
      teamRepository: teams,
      eventRepository: FakeEventRepository(),
      teamPostRepository: FakeTeamPostRepository(),
      authRepository: auth,
      filePicker: FakeFilePickerService(),
      hints: hints,
      clock: () => now,
    );

    Future<void> pumpPhone(WidgetTester tester, TeamHomeViewModel vm) async {
      tester.view.physicalSize = const Size(560, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final router = GoRouter(
        initialLocation: '/teams/t1',
        routes: [
          GoRoute(
            path: '/teams/:teamId',
            builder: (_, state) => TeamHomeScreen(
              viewModel: vm,
              section: TeamSection.fromPath(
                state.uri.queryParameters['section'],
              ),
              more: state.uri.queryParameters['section'] == TeamTab.morePath,
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthRepository>.value(value: auth),
            Provider<TeamRepository>.value(value: teams),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a new team shows no Playbook, Videos or Stats until one is '
        'turned on', (tester) async {
      await teams.createTeam(_newTeam, testUser);
      final vm = homeVm();
      addTearDown(vm.dispose);
      await pumpPhone(tester, vm);

      for (final t in ['Feed', 'Schedule', 'Chat', 'Roster', 'More']) {
        expect(find.text(t), findsOneWidget);
      }
      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, 'Tournaments'), findsOneWidget);
      for (final s in ['Playbook', 'Videos', 'Stats']) {
        expect(find.widgetWithText(ListTile, s), findsNothing);
      }

      expect(
        await teams.setSections('t1', {OptionalSection.playbook: true}),
        isA<Ok<void>>(),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, 'Playbook'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Videos'), findsNothing);

      await teams.setSections('t1', {OptionalSection.playbook: false});
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, 'Playbook'), findsNothing);
    });

    testWidgets('the owner of a new team gets a hint, until dismissed', (
      tester,
    ) async {
      await teams.createTeam(_newTeam, testUser);
      final vm = homeVm();
      addTearDown(vm.dispose);
      await pumpPhone(tester, vm);

      const hint =
          'Turn on Playbook, Videos, Stats or Meetings in Settings › '
          'Sections.';
      expect(vm.showSectionsHint, isTrue);
      expect(find.text(hint), findsOneWidget);
      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pumpAndSettle();
      expect(find.text(hint), findsNothing);
      expect(await hints.sectionsHintDismissed('t1'), isTrue);

      // Remembered for the next visit.
      final again = homeVm();
      addTearDown(again.dispose);
      await tester.pump();
      expect(again.showSectionsHint, isFalse);
    });

    test(
      'no hint once a section is on, for others, or on an old team',
      () async {
        await teams.createTeam(_newTeam, testUser);
        var vm = homeVm();
        await pumpEventQueue();
        expect(vm.showSectionsHint, isTrue);
        await teams.setSections('t1', {OptionalSection.stats: true});
        await pumpEventQueue();
        expect(vm.showSectionsHint, isFalse);
        vm.dispose();

        // A player on a new team.
        teams.teams['t1'] = teamWith({
          'o': TeamRole.owner,
          'u1': TeamRole.player,
        }).copyWith(sectionsOff: OptionalSection.values.toSet());
        vm = homeVm();
        await pumpEventQueue();
        expect(vm.showSectionsHint, isFalse);
        vm.dispose();

        // An owner whose team is months old.
        teams.teams['t1'] = Team(
          id: 't1',
          name: 'Team',
          division: Division.mixed,
          level: CompetitionLevel.college,
          ownerId: 'u1',
          members: const {'u1': TeamRole.owner},
          createdAt: now.subtract(const Duration(days: 90)),
          sectionsOff: OptionalSection.values.toSet(),
        );
        vm = homeVm();
        await pumpEventQueue();
        expect(vm.showSectionsHint, isFalse);
        vm.dispose();
      },
    );

    testWidgets('the owner opens the menu, Settings, turns Playbook on, and '
        'it is under More', (tester) async {
      await teams.createTeam(_newTeam, testUser);
      final vm = homeVm();
      addTearDown(vm.dispose);
      await pumpPhone(tester, vm);
      await tester.tap(find.byTooltip('More').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Team settings'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('section-playbook')));
      await tester.pumpAndSettle();
      expect(teams.sectionChanges, [
        {OptionalSection.playbook: true},
      ]);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, 'Playbook'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Videos'), findsNothing);
    });

    Future<bool> menuHasSettings(WidgetTester tester) async {
      final vm = homeVm();
      addTearDown(vm.dispose);
      await pumpPhone(tester, vm);
      await tester.tap(find.byTooltip('More').first);
      await tester.pumpAndSettle();
      return find.text('Settings').evaluate().isNotEmpty;
    }

    testWidgets('a coach has Settings too (the public page switch); '
        'a player has none', (tester) async {
      teams.teams['t1'] = teamWith({
        'o': TeamRole.owner,
        testUser.uid: TeamRole.coach,
      }).copyWith(sectionsOff: OptionalSection.values.toSet());
      expect(await menuHasSettings(tester), isTrue);
    });

    testWidgets('a player has no Settings in the menu', (tester) async {
      teams.teams['t1'] = teamWith({
        'o': TeamRole.owner,
        testUser.uid: TeamRole.player,
      }).copyWith(sectionsOff: OptionalSection.values.toSet());
      expect(await menuHasSettings(tester), isFalse);
    });

    testWidgets("nor does a community's owner (no sections to switch)", (
      tester,
    ) async {
      await teams.createTeam(
        const NewTeam(
          name: 'Pickup',
          division: Division.mixed,
          level: CompetitionLevel.pickup,
          kind: TeamKind.community,
        ),
        testUser,
      );
      expect(teams.teams['t1']!.sectionsOff, isEmpty);
      expect(await menuHasSettings(tester), isFalse);
    });

    group('Meetings', () {
      Future<void> pumpSchedule(WidgetTester tester) async {
        final events = FakeEventRepository();
        final vm = TeamDetailViewModel(
          teamId: 't1',
          teamRepository: teams,
          playRepository: FakePlayRepository(),
          eventRepository: events,
          authRepository: auth,
        );
        addTearDown(vm.dispose);
        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => Scaffold(body: TeamEventsTab(viewModel: vm)),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<AuthRepository>.value(value: auth),
              Provider<TeamRepository>.value(value: teams),
              Provider<EventRepository>.value(value: events),
            ],
            child: MaterialApp.router(
              theme: AppTheme.light,
              routerConfig: router,
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      testWidgets('off: New adds an event straight away', (tester) async {
        await teams.createTeam(_newTeam, testUser);
        await pumpSchedule(tester);
        await tester.tap(find.text('New'));
        await tester.pumpAndSettle();
        expect(find.text('Meeting'), findsNothing);
        expect(find.text('New event'), findsOneWidget);
      });

      testWidgets('on: New asks Event or Meeting', (tester) async {
        await teams.createTeam(_newTeam, testUser);
        await teams.setSections('t1', {OptionalSection.meetings: true});
        await pumpSchedule(tester);
        await tester.tap(find.text('New'));
        await tester.pumpAndSettle();
        expect(find.text('Meeting'), findsOneWidget);
        expect(find.text('Event'), findsOneWidget);
      });
    });
  });

  group('Settings › Sections', () {
    late FakeTeamRepository teams;

    setUp(() => teams = FakeTeamRepository());

    Future<TeamSettingsViewModel> pump(
      WidgetTester tester, {
      String uid = 'u1',
    }) async {
      final vm = TeamSettingsViewModel(
        teamId: 't1',
        teamRepository: teams,
        authRepository: FakeAuthRepository(
          user: AppUser(uid: uid, email: '$uid@x.test', displayName: uid),
        ),
      );
      addTearDown(vm.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: TeamSettingsScreen(viewModel: vm),
        ),
      );
      await tester.pumpAndSettle();
      return vm;
    }

    SwitchListTile tile(WidgetTester tester, OptionalSection s) => tester
        .widget<SwitchListTile>(find.byKey(ValueKey('section-${s.name}')));

    testWidgets('a card of switches, each with what it is for', (tester) async {
      await teams.createTeam(_newTeam, testUser);
      await pump(tester);
      expect(find.text('SECTIONS'), findsOneWidget);
      for (final s in OptionalSection.values) {
        expect(find.text(s.label), findsOneWidget);
        expect(find.text(s.description), findsOneWidget);
        expect(tile(tester, s).value, isFalse);
      }
    });

    testWidgets('the owner turns one on, and back off', (tester) async {
      await teams.createTeam(_newTeam, testUser);
      await pump(tester);

      await tester.tap(find.byKey(const ValueKey('section-videos')));
      await tester.pumpAndSettle();
      expect(teams.sectionChanges.last, {OptionalSection.videos: true});
      expect(tile(tester, OptionalSection.videos).value, isTrue);
      expect(teams.teams['t1']!.hasSection(OptionalSection.videos), isTrue);
      expect(teams.teams['t1']!.hasSection(OptionalSection.stats), isFalse);

      await tester.tap(find.byKey(const ValueKey('section-videos')));
      await tester.pumpAndSettle();
      expect(teams.sectionChanges.last, {OptionalSection.videos: false});
      expect(tile(tester, OptionalSection.videos).value, isFalse);
    });

    testWidgets('others see the switches but can not change them', (
      tester,
    ) async {
      teams.teams['t1'] = teamWith({
        'o': TeamRole.owner,
        'coach': TeamRole.coach,
      }).copyWith(sectionsOff: {OptionalSection.meetings});
      await pump(tester, uid: 'coach');
      expect(tile(tester, OptionalSection.playbook).value, isTrue);
      expect(tile(tester, OptionalSection.meetings).value, isFalse);
      expect(tile(tester, OptionalSection.meetings).onChanged, isNull);
      expect(
        find.text('Only the owner can turn sections on or off.'),
        findsOneWidget,
      );
    });
  });
}
