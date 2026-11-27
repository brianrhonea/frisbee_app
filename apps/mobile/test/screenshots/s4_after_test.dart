// Sprint 4 (wave 1, app lane): phone screenshots of the owner-feedback
// screens on fake data. Skipped unless asked for:
//   flutter test test/screenshots/s4_after_test.dart \
//     --dart-define=SCREENSHOTS=<out dir> [--dart-define=SHOT_THEME=dark]
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/auth/auth_repository.dart';
import 'package:frisbee_app/data/repositories/direct_message/direct_message_repository.dart';
import 'package:frisbee_app/data/repositories/schedule/schedule_settings_repository.dart';
import 'package:frisbee_app/data/repositories/team/team_repository.dart';
import 'package:frisbee_app/domain/models/roster_player.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/team_event.dart';
import 'package:frisbee_app/ui/explore/view_models/player_search_viewmodel.dart';
import 'package:frisbee_app/ui/explore/widgets/explore_screen.dart';
import 'package:frisbee_app/ui/profile/view_models/player_profile_viewmodel.dart';
import 'package:frisbee_app/ui/profile/widgets/profile_screen.dart';
import 'package:frisbee_app/ui/schedule/view_models/event_editor_viewmodel.dart';
import 'package:frisbee_app/ui/schedule/view_models/schedule_viewmodel.dart';
import 'package:frisbee_app/ui/schedule/widgets/event_editor_screen.dart';
import 'package:frisbee_app/ui/schedule/widgets/schedule_screen.dart';
import 'package:frisbee_app/ui/teams/view_models/team_detail_viewmodel.dart';
import 'package:frisbee_app/ui/teams/view_models/team_home_viewmodel.dart';
import 'package:frisbee_app/ui/teams/view_models/team_search_viewmodel.dart';
import 'package:frisbee_app/ui/teams/widgets/members_tab.dart';
import 'package:frisbee_app/ui/teams/widgets/team_home_screen.dart';
import 'package:provider/provider.dart';

import '../testing/fakes.dart';
import 's4_common.dart';

void main() {
  final skip = s4Out.isEmpty ? 'pass --dart-define=SCREENSHOTS=<dir>' : null;
  final me = testUser.uid;
  final now = DateTime(2026, 11, 19, 9);

  Team team({Map<String, TeamRole>? members}) => Team(
    id: 't1',
    name: 'Northside Flyers',
    division: Division.mixed,
    level: CompetitionLevel.club,
    city: 'Denver',
    ownerId: me,
    createdAt: DateTime(2019),
    members:
        members ??
        {
          me: TeamRole.owner,
          'coach': TeamRole.coach,
          'sam': TeamRole.player,
          'jo': TeamRole.player,
          'ava': TeamRole.player,
          'dev': TeamRole.player,
        },
    memberNames: {
      me: 'Test User',
      'coach': 'Riley Chen',
      'sam': 'Sam Ortiz',
      'jo': 'Jo Park',
      'ava': 'Ava Brooks',
      'dev': 'Dev Patel',
    },
    statKeepers: const {'jo'},
    roles: const {
      'h': CustomRole(
        id: 'h',
        name: 'Handlers',
        permissions: {TeamPermission.manageChats},
      ),
    },
    memberRoles: const {
      'sam': {'h'},
      'ava': {'h'},
    },
  );

  Widget providers(
    Widget app,
    FakeTeamRepository teams,
    FakeAuthRepository auth,
  ) => MultiProvider(
    providers: [
      Provider<TeamRepository>.value(value: teams),
      ChangeNotifierProvider<AuthRepository>.value(value: auth),
      Provider<DirectMessageRepository>.value(
        value: FakeDirectMessageRepository(),
      ),
    ],
    child: app,
  );

  testWidgets('month', skip: skip != null, (tester) async {
    await shotSize(tester);
    final teams = FakeTeamRepository()..teams['t1'] = team();
    final events = FakeEventRepository();
    for (final (i, (d, h, title)) in [
      (3, 18, 'Tuesday practice'),
      (5, 18, 'Thursday practice'),
      (12, 19, 'Film night'),
      (19, 18, 'Thursday practice'),
      (21, 9, 'Snowmelt Hat'),
      (24, 18, 'Team dinner'),
      (26, 18, 'Tuesday practice'),
    ].indexed) {
      events.events['e$i'] = TeamEvent(
        id: 'e$i',
        title: title,
        startsAt: DateTime(2026, 11, d, h),
        endsAt: DateTime(2026, 11, d, h + 2),
        location: 'Washington Park',
      );
    }
    events.mine[me] = {
      'run': TeamEvent(
        id: 'run',
        title: 'Tempo run',
        type: EventType.workout,
        startsAt: DateTime(2026, 11, 19, 7),
      ),
    };
    final vm = ScheduleViewModel(
      authRepository: FakeAuthRepository(user: testUser),
      teamRepository: teams,
      eventRepository: events,
      settingsRepository: ScheduleSettingsRepositoryMemory(),
      clock: () => now,
    );
    addTearDown(vm.dispose);
    await tester.pumpAndSettle();
    vm.setView(ScheduleView.month);
    await shotPump(tester, ScheduleScreen(viewModel: vm));
    // Pick an empty day: the list scrolls to the next day with events and
    // highlights it.
    await tester.tap(find.bySemanticsLabel('Friday, November 20'));
    await tester.pumpAndSettle();
    await shotCapture(tester, 'month');
  });

  group('roster', () {
    late FakeTeamRepository teams;
    late FakeAuthRepository auth;

    TeamDetailViewModel vm() {
      final v = TeamDetailViewModel(
        teamId: 't1',
        teamRepository: teams,
        playRepository: FakePlayRepository(),
        eventRepository: FakeEventRepository(),
        authRepository: auth,
        clock: () => now,
      );
      addTearDown(v.dispose);
      return v;
    }

    setUp(() {
      teams = FakeTeamRepository()..teams['t1'] = team();
      teams.listings['t1'] = TeamListing.of(teams.teams['t1']!);
      teams.roster['t1'] = const [
        RosterPlayer(id: 'a', name: 'Sam Ortiz', number: 7, userId: 'sam'),
        RosterPlayer(id: 'b', name: 'Guest Player', number: 21),
      ];
      auth = FakeAuthRepository(user: testUser);
    });

    Future<void> open(WidgetTester tester) async {
      await shotSize(tester);
      await shotPump(
        tester,
        Scaffold(body: MembersTab(viewModel: vm())),
        wrap: (app) => providers(app, teams, auth),
      );
    }

    testWidgets('members', skip: skip != null, (tester) async {
      await open(tester);
      await shotCapture(tester, 'roster-members');
    });

    testWidgets('roles', skip: skip != null, (tester) async {
      await open(tester);
      await tester.tap(find.text('Roles'));
      await tester.pumpAndSettle();
      await shotCapture(tester, 'roster-roles');
    });

    testWidgets('add member, manageTeam-only admin', skip: skip != null, (
      tester,
    ) async {
      // An admin who edits the roster but cannot manage members: Add member
      // opens the player editor directly.
      teams.teams['t1'] = teams.teams['t1']!.copyWith(
        memberPerms: {
          me: {TeamPermission.manageTeam},
        },
        members: {
          ...teams.teams['t1']!.members,
          me: TeamRole.player,
          'owner2': TeamRole.owner,
        },
      );
      await open(tester);
      await tester.tap(find.text('Add member'));
      await tester.pumpAndSettle();
      expect(find.text('Add player'), findsOneWidget);
      expect(find.text('Invite people'), findsNothing);
      await shotCapture(tester, 'roster-add-member');
    });

    testWidgets('add member and link picker', skip: skip != null, (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.text('Add member'));
      await tester.pumpAndSettle();
      await shotCapture(tester, 'roster-add-member-sheet');
      await tester.tap(find.text('Add player to roster'));
      await tester.pumpAndSettle();
      await shotCapture(tester, 'roster-add-player');
      await tester.tap(find.byKey(const ValueKey('link-to-member')));
      await tester.pumpAndSettle();
      await shotCapture(tester, 'roster-link-picker');
    });
  });

  testWidgets('teams search with Join', skip: skip != null, (tester) async {
    await shotSize(tester);
    final teams = FakeTeamRepository();
    TeamListing l(
      String id,
      String name, {
      TeamKind kind = TeamKind.team,
      bool approval = false,
      bool requests = false,
    }) => TeamListing(
      id: id,
      name: name,
      division: Division.mixed,
      level: CompetitionLevel.club,
      city: 'Denver',
      kind: kind,
      requiresApproval: approval,
      allowJoinRequests: requests,
    );
    for (final t in [
      l('a', 'Denver Open Pickup', kind: TeamKind.community),
      l(
        'b',
        'Denver Approval Pickup',
        kind: TeamKind.community,
        approval: true,
      ),
      l('c', 'Denver Flyers', requests: true),
      l('d', 'Denver Code Team'),
    ]) {
      teams.listings[t.id] = t;
      teams.teams[t.id] = Team(
        id: t.id,
        name: t.name,
        division: t.division,
        level: t.level,
        ownerId: 'owner',
        members: const {'owner': TeamRole.owner},
        kind: t.kind,
      );
    }
    final vm = TeamSearchViewModel(
      teamRepository: teams,
      authRepository: FakeAuthRepository(user: testUser),
    );
    final players = PlayerSearchViewModel(
      profileRepository: FakeProfileRepository(),
    );
    addTearDown(vm.dispose);
    addTearDown(players.dispose);
    await shotPump(tester, ExploreScreen(viewModel: vm, players: players));
    await tester.enterText(find.byType(TextField).first, 'denver');
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    await shotCapture(tester, 'teams-search');
  });

  group('profile', () {
    Future<void> profile(
      WidgetTester tester,
      String name, {
      required bool linked,
    }) async {
      await shotSize(tester);
      final auth = FakeAuthRepository(user: testUser);
      final teams = FakeTeamRepository();
      teams.teams['t1'] = team();
      teams.roster['t1'] = [
        RosterPlayer(
          id: 'r1',
          name: 'Test User',
          number: 17,
          userId: linked ? me : null,
        ),
        const RosterPlayer(id: 'r2', name: 'Sam Ortiz', number: 7),
      ];
      final vm = PlayerProfileViewModel(
        uid: me,
        profileRepository: FakeProfileRepository(),
        authRepository: auth,
        teamRepository: teams,
        statsRepository: FakeStatsRepository(),
        directMessageRepository: FakeDirectMessageRepository(),
      );
      addTearDown(vm.dispose);
      await shotPump(tester, PlayerProfileScreen(viewModel: vm));
      await tester.pumpAndSettle();
      await shotCapture(tester, name);
    }

    testWidgets('unlinked', skip: skip != null, (tester) async {
      await profile(tester, 'profile-unlinked', linked: false);
    });

    testWidgets('linked', skip: skip != null, (tester) async {
      await profile(tester, 'profile-linked', linked: true);
    });
  });

  testWidgets('overlap warning', skip: skip != null, (tester) async {
    await shotSize(tester);
    final teams = FakeTeamRepository();
    final vm = EventEditorViewModel(
      teamId: null,
      eventId: null,
      eventRepository: FakeEventRepository(),
      teamRepository: teams,
      authRepository: FakeAuthRepository(user: testUser),
      initialDay: DateTime(2026, 11, 19),
      knownEvents: () => [
        TeamEvent(
          id: 'p',
          title: 'Thursday practice',
          startsAt: DateTime(2026, 11, 19, 18),
          endsAt: DateTime(2026, 11, 19, 20),
        ),
      ],
    );
    addTearDown(vm.dispose);
    await tester.runAsync(pumpEventQueue);
    await shotPump(tester, EventEditorScreen(viewModel: vm));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Title'),
      'Film session',
    );
    await tester.tap(find.text('Create event'));
    await tester.pumpAndSettle();
    await shotCapture(tester, 'overlap-dialog');
  });

  testWidgets('team header and message sheet', skip: skip != null, (
    tester,
  ) async {
    await shotSize(tester);
    final auth = FakeAuthRepository(user: testUser);
    final teams = FakeTeamRepository();
    final t =
        team(
          members: {
            'owner': TeamRole.owner,
            'coach': TeamRole.coach,
            'cap': TeamRole.captain,
            me: TeamRole.player,
            'sam': TeamRole.player,
          },
        ).copyWith(
          memberNames: {
            'owner': 'Olive Nguyen',
            'coach': 'Riley Chen',
            'cap': 'Cass Wu',
            me: 'Test User',
            'sam': 'Sam Ortiz',
          },
        );
    teams.teams['t1'] = t;
    teams.listings['t1'] = TeamListing.of(t);
    final vm = TeamHomeViewModel(
      teamId: 't1',
      teamRepository: teams,
      eventRepository: FakeEventRepository(),
      teamPostRepository: FakeTeamPostRepository(),
      authRepository: auth,
      filePicker: FakeFilePickerService(),
      chatRepository: FakeChatRepository(),
      directMessageRepository: FakeDirectMessageRepository(),
      clock: () => now,
    );
    addTearDown(vm.dispose);
    await shotPump(
      tester,
      TeamHomeScreen(viewModel: vm),
      wrap: (app) => providers(app, teams, auth),
    );
    await shotCapture(tester, 'team-header');
    await tester.tap(find.widgetWithText(OutlinedButton, 'Message').first);
    await tester.pumpAndSettle();
    await shotCapture(tester, 'team-message-sheet');
  });

  testWidgets('outsider message sheet', skip: skip != null, (tester) async {
    await shotSize(tester);
    final auth = FakeAuthRepository(user: testUser);
    final teams = FakeTeamRepository();
    final t =
        team(
          members: {
            'owner': TeamRole.owner,
            'coach': TeamRole.coach,
            'cap': TeamRole.captain,
            'sam': TeamRole.player,
          },
        ).copyWith(
          memberNames: {
            'owner': 'Olive Nguyen',
            'coach': 'Riley Chen',
            'cap': 'Cass Wu',
            'sam': 'Sam Ortiz',
          },
        );
    teams.teams['t1'] = t;
    teams.listings['t1'] = TeamListing.of(t);
    final vm = TeamHomeViewModel(
      teamId: 't1',
      teamRepository: teams,
      eventRepository: FakeEventRepository(),
      teamPostRepository: FakeTeamPostRepository(),
      authRepository: auth,
      filePicker: FakeFilePickerService(),
      chatRepository: FakeChatRepository(),
      directMessageRepository: FakeDirectMessageRepository(),
      clock: () => now,
    );
    addTearDown(vm.dispose);
    await shotPump(
      tester,
      TeamHomeScreen(viewModel: vm),
      wrap: (app) => providers(app, teams, auth),
    );
    await tester.pumpAndSettle();
    await shotCapture(tester, 'outsider-team-header');
    await tester.tap(find.widgetWithText(OutlinedButton, 'Message').first);
    await tester.pumpAndSettle();
    await shotCapture(tester, 'outsider-message-sheet');
  });
}
