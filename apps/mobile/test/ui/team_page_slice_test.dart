// The team page's stat tiles (F18), roster lines and invites pending
// (F23) and More's subtitles, Manage and Leave (F28). The website's side
// of the same rules is in packages/shared (team_page.test.ts) and the API
// (roster_lines.test.ts).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/auth/auth_repository.dart';
import 'package:frisbee_app/data/repositories/team/team_repository.dart';
import 'package:frisbee_app/domain/models/chat.dart';
import 'package:frisbee_app/domain/models/pending_invite.dart';
import 'package:frisbee_app/domain/models/roster_player.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/team_event.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/teams/view_models/team_detail_viewmodel.dart';
import 'package:frisbee_app/ui/teams/view_models/team_home_viewmodel.dart';
import 'package:frisbee_app/ui/teams/widgets/members_tab.dart';
import 'package:frisbee_app/ui/teams/widgets/roster_tab.dart';
import 'package:frisbee_app/ui/teams/widgets/team_home_screen.dart';
import 'package:provider/provider.dart';

import '../testing/fakes.dart';

void main() {
  late FakeTeamRepository teams;
  late FakeEventRepository events;
  late FakeAuthRepository auth;
  late FakeChatRepository chats;
  final now = DateTime(2026, 10, 30, 12);

  setUp(() {
    teams = FakeTeamRepository();
    events = FakeEventRepository()
      ..events['e1'] = TeamEvent(
        id: 'e1',
        title: 'Practice',
        startsAt: now.add(const Duration(days: 1)),
        rsvps: const {
          'a': RsvpStatus.going,
          'b': RsvpStatus.maybe,
          'c': RsvpStatus.going,
        },
      );
    auth = FakeAuthRepository(user: testUser);
    chats = FakeChatRepository();
  });

  void addTeam(Map<String, TeamRole> members) {
    final team = teamWith(members);
    teams.teams[team.id] = team;
    teams.listings[team.id] = TeamListing.of(team);
  }

  TeamHomeViewModel homeVm() => TeamHomeViewModel(
    teamId: 't1',
    teamRepository: teams,
    eventRepository: events,
    teamPostRepository: FakeTeamPostRepository(),
    authRepository: auth,
    filePicker: FakeFilePickerService(),
    chatRepository: chats,
    clock: () => now,
  );

  TeamDetailViewModel detailVm() => TeamDetailViewModel(
    teamId: 't1',
    teamRepository: teams,
    playRepository: FakePlayRepository(),
    eventRepository: events,
    authRepository: auth,
    clock: () => now,
  );

  Future<void> pumpWide(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<TeamRepository>.value(value: teams),
          ChangeNotifierProvider<AuthRepository>.value(value: auth),
        ],
        child: MaterialApp(theme: AppTheme.light, home: child),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('stat tiles', () {
    void seedRooms() {
      chats
        ..rooms['general'] = ChatRoom.general()
        ..rooms['rides'] = const ChatRoom(
          id: 'rides',
          name: 'Carpool',
          readRoles: {ChatAudience.everyone},
          writeRoles: {ChatAudience.everyone},
        )
        // Coaches only: never counted for a player.
        ..rooms['staff'] = const ChatRoom(
          id: 'staff',
          name: 'Staff',
          readRoles: {'coach'},
          writeRoles: {'coach'},
        )
        ..stampRoom('general', now)
        ..stampRoom('rides', now)
        ..stampRoom('staff', now);
      // General read since its last message; Carpool not.
      chats.reads[testUser.uid] = {
        't1': {'general': now.add(const Duration(minutes: 1))},
      };
    }

    test('count Going to the next event and rooms with new messages', () async {
      addTeam({'owner': TeamRole.owner, testUser.uid: TeamRole.player});
      seedRooms();
      final vm = homeVm();
      addTearDown(vm.dispose);
      await pumpEventQueue();
      expect(vm.nextEvent?.id, 'e1');
      expect(vm.nextGoing, 2);
      expect(vm.newInChat, 1);
    });

    testWidgets('show under the header, saying what they count', (
      tester,
    ) async {
      addTeam({'owner': TeamRole.owner, testUser.uid: TeamRole.player});
      seedRooms();
      final vm = homeVm();
      addTearDown(vm.dispose);
      await pumpWide(tester, TeamHomeScreen(viewModel: vm));
      expect(find.text('going'), findsOneWidget);
      expect(find.text('new in chat'), findsOneWidget);
      expect(find.bySemanticsLabel('2 going to Practice'), findsOneWidget);
      expect(find.bySemanticsLabel('1 room has new messages'), findsOneWidget);
    });
  });

  group('More', () {
    testWidgets('rows say what is there; admins get Manage team; '
        'others get Leave with its confirm', (tester) async {
      addTeam({'owner': TeamRole.owner, testUser.uid: TeamRole.coach});
      final vm = homeVm();
      addTearDown(vm.dispose);
      await pumpWide(tester, TeamHomeScreen(viewModel: vm, more: true));
      expect(find.text('Plays and whiteboards'), findsOneWidget);
      expect(find.text('Game film and highlights'), findsOneWidget);
      expect(find.text('Manage team'), findsOneWidget);
      expect(find.text('Details, sections and visibility'), findsOneWidget);
      await tester.tap(find.text('Leave team'));
      await tester.pumpAndSettle();
      expect(find.text('Leave Team?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });

    testWidgets("the owner can't leave from More, and is told why", (
      tester,
    ) async {
      addTeam({testUser.uid: TeamRole.owner});
      final vm = homeVm();
      addTearDown(vm.dispose);
      await pumpWide(tester, TeamHomeScreen(viewModel: vm, more: true));
      expect(find.text('Leave team'), findsNothing);
      expect(find.textContaining("Owners can't leave"), findsOneWidget);
      expect(find.text('Manage team'), findsOneWidget);
    });

    testWidgets('players get no Manage row', (tester) async {
      addTeam({'owner': TeamRole.owner, testUser.uid: TeamRole.player});
      final vm = homeVm();
      addTearDown(vm.dispose);
      await pumpWide(tester, TeamHomeScreen(viewModel: vm, more: true));
      expect(find.text('Manage team'), findsNothing);
      expect(find.text('Leave team'), findsOneWidget);
    });
  });

  group('roster', () {
    Widget rosterOf(TeamDetailViewModel vm) => Scaffold(
      body: ListenableBuilder(
        listenable: vm,
        builder: (_, _) =>
            vm.team == null ? const SizedBox() : RosterTab(viewModel: vm),
      ),
    );

    testWidgets('shows roles, groups by line, and admins edit lines', (
      tester,
    ) async {
      addTeam({
        testUser.uid: TeamRole.owner,
        'cap': TeamRole.coach,
        'sam': TeamRole.player,
      });
      teams.roster['t1'] = [
        const RosterPlayer(
          id: 'p1',
          name: 'Cam',
          number: 1,
          userId: 'cap',
          line: RosterLine.o,
        ),
        const RosterPlayer(id: 'p2', name: 'Sam', number: 2, userId: 'sam'),
      ];
      final vm = detailVm();
      addTearDown(vm.dispose);
      await pumpWide(tester, rosterOf(vm));

      expect(find.text('O-LINE · 1'), findsOneWidget);
      expect(find.text('UNASSIGNED · 1'), findsOneWidget);
      // The coach's role on their row; a plain player's isn't tagged.
      expect(find.text('Coach'), findsOneWidget);

      await tester.tap(find.text('Edit lines'));
      await tester.pumpAndSettle();
      final samRow = find.ancestor(
        of: find.text('Sam'),
        matching: find.byType(ListTile),
      );
      await tester.tap(find.descendant(of: samRow, matching: find.text('D')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save lines'));
      await tester.pumpAndSettle();

      expect(teams.lineChanges, [
        {'p2': RosterLine.d},
      ]);
      expect(find.text('D-LINE · 1'), findsOneWidget);
      expect(find.text('UNASSIGNED · 1'), findsNothing);
      expect(find.text('Edit lines'), findsOneWidget);
    });

    testWidgets('players see lines but no Edit lines', (tester) async {
      addTeam({'owner': TeamRole.owner, testUser.uid: TeamRole.player});
      teams.roster['t1'] = [
        const RosterPlayer(id: 'p1', name: 'Cam', line: RosterLine.both),
      ];
      final vm = detailVm();
      addTearDown(vm.dispose);
      await pumpWide(tester, rosterOf(vm));
      expect(find.text('BOTH LINES · 1'), findsOneWidget);
      expect(find.text('Edit lines'), findsNothing);
    });

    test('editing a player keeps their line', () async {
      addTeam({testUser.uid: TeamRole.owner});
      teams.roster['t1'] = [
        const RosterPlayer(id: 'p1', name: 'Cam', line: RosterLine.d),
      ];
      final vm = detailVm();
      addTearDown(vm.dispose);
      await pumpEventQueue();
      vm.togglePaid(vm.roster.single);
      await pumpEventQueue();
      expect(teams.roster['t1']!.single.line, RosterLine.d);
      expect(teams.roster['t1']!.single.paid, isTrue);
    });
  });

  group('invites pending', () {
    Widget membersOf(TeamDetailViewModel vm) => Scaffold(
      body: ListenableBuilder(
        listenable: vm,
        builder: (_, _) =>
            vm.team == null ? const SizedBox() : MembersTab(viewModel: vm),
      ),
    );

    testWidgets('admins see who is invited and withdraw an invite', (
      tester,
    ) async {
      addTeam({testUser.uid: TeamRole.owner});
      teams.pending['t1'] = [
        PendingInvite(
          uid: 'nina',
          name: 'Nina New',
          invitedByName: 'Olive',
          invitedAt: DateTime(2026, 11, 2),
        ),
      ];
      final vm = detailVm();
      addTearDown(vm.dispose);
      await pumpWide(tester, membersOf(vm));
      // TeamSectionBody asks when Members opens.
      vm.loadInvites.execute();
      await tester.pumpAndSettle();

      expect(find.text('INVITES PENDING · 1'), findsOneWidget);
      expect(find.text('Nina New'), findsOneWidget);
      expect(find.text('Invited by Olive · Nov 2'), findsOneWidget);
      await tester.tap(find.text('Withdraw'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Withdraw'));
      await tester.pumpAndSettle();
      expect(find.text('Nina New'), findsNothing);
      expect(teams.pending['t1'], isEmpty);
    });

    testWidgets('players see no invites', (tester) async {
      addTeam({'owner': TeamRole.owner, testUser.uid: TeamRole.player});
      teams.pending['t1'] = [const PendingInvite(uid: 'n', name: 'Nina New')];
      final vm = detailVm();
      addTearDown(vm.dispose);
      await pumpWide(tester, membersOf(vm));
      vm.loadInvites.execute();
      await tester.pumpAndSettle();
      expect(find.textContaining('INVITES PENDING'), findsNothing);
      expect(find.text('Nina New'), findsNothing);
    });
  });
}
