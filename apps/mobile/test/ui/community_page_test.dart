// The community page (redesign F27): the next pickup card with RSVP at
// the top, the Chat section and the Organizers section with Message. The
// website's side of the same rules is packages/shared's team_page.test.ts
// (chatSectionRooms, communityOrganizers, nextEventCardText).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/auth/auth_repository.dart';
import 'package:frisbee_app/data/repositories/team/team_repository.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/chat.dart';
import 'package:frisbee_app/domain/models/direct_message.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/team_event.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/teams/view_models/team_home_viewmodel.dart';
import 'package:frisbee_app/ui/teams/widgets/team_home_screen.dart';
import 'package:frisbee_app/utils/result.dart';
import 'package:provider/provider.dart';

import '../testing/fakes.dart';

void main() {
  late FakeTeamRepository teams;
  late FakeEventRepository events;
  late FakeAuthRepository auth;
  late FakeChatRepository chats;
  late FakeDirectMessageRepository dms;
  final now = DateTime(2026, 10, 30, 12);

  Team community(
    Map<String, TeamRole> members, {
    Map<String, Set<TeamPermission>> perms = const {},
  }) => Team(
    id: 't1',
    name: 'Riverside Pickup',
    division: Division.mixed,
    level: CompetitionLevel.club,
    kind: TeamKind.community,
    ownerId: members.entries.firstWhere((e) => e.value == TeamRole.owner).key,
    members: members,
    memberNames: const {
      'owner': 'Olive',
      'org': 'Oscar',
      'mod': 'Mona',
      'u1': 'Alex',
    },
    memberPerms: perms,
  );

  void add(Team team, {bool listed = true}) {
    teams.teams[team.id] = team;
    if (listed) teams.listings[team.id] = TeamListing.of(team);
  }

  setUp(() {
    teams = FakeTeamRepository();
    events = FakeEventRepository()
      ..events['e1'] = TeamEvent(
        id: 'e1',
        title: 'Sunday pickup',
        location: 'Riverside Park',
        startsAt: now.add(const Duration(days: 2)),
        rsvps: const {'owner': RsvpStatus.going, 'org': RsvpStatus.going},
        isPublic: true,
      );
    auth = FakeAuthRepository(user: testUser);
    chats = FakeChatRepository();
    dms = FakeDirectMessageRepository();
  });

  TeamHomeViewModel homeVm() => TeamHomeViewModel(
    teamId: 't1',
    teamRepository: teams,
    eventRepository: events,
    teamPostRepository: FakeTeamPostRepository(),
    authRepository: auth,
    filePicker: FakeFilePickerService(),
    chatRepository: chats,
    directMessageRepository: dms,
    clock: () => now,
  );

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(900, 1600),
  }) async {
    tester.view.physicalSize = size;
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

  group('next pickup card', () {
    testWidgets('members RSVP from it; picking the answer again takes it '
        'back', (tester) async {
      add(community({'owner': TeamRole.owner, 'u1': TeamRole.player}));
      final vm = homeVm();
      addTearDown(vm.dispose);
      await pump(tester, TeamHomeScreen(viewModel: vm));

      final card = find.byKey(const ValueKey('next-pickup'));
      expect(card, findsOneWidget);
      Finder inCard(Finder f) => find.descendant(of: card, matching: f);
      expect(inCard(find.text('Next pickup')), findsOneWidget);
      expect(inCard(find.text('Sunday pickup')), findsOneWidget);
      expect(inCard(find.text('Riverside Park')), findsOneWidget);
      expect(inCard(find.text('2 going')), findsOneWidget);
      expect(inCard(find.text('Needs RSVP')), findsOneWidget);
      // The pickup card takes the dark Up next card's place.
      expect(find.text('View details'), findsNothing);

      await tester.tap(inCard(find.text('Going')));
      await tester.pumpAndSettle();
      expect(events.events['e1']!.rsvpOf(testUser.uid), RsvpStatus.going);
      expect(inCard(find.text('3 going')), findsOneWidget);
      expect(inCard(find.text('Needs RSVP')), findsNothing);

      await tester.tap(inCard(find.text('Going')));
      await tester.pumpAndSettle();
      expect(events.events['e1']!.rsvpOf(testUser.uid), isNull);
      expect(inCard(find.text('Needs RSVP')), findsOneWidget);
    });

    test('answerNext swaps answers and clears the current one', () async {
      add(community({'owner': TeamRole.owner, 'u1': TeamRole.player}));
      final vm = homeVm();
      addTearDown(vm.dispose);
      await pumpEventQueue();
      expect(vm.nextNeedsRsvp, isTrue);
      vm.answerNext(RsvpStatus.maybe);
      await pumpEventQueue();
      expect(vm.myNextRsvp, RsvpStatus.maybe);
      expect(vm.nextNeedsRsvp, isFalse);
      vm.answerNext(RsvpStatus.notGoing);
      await pumpEventQueue();
      expect(vm.myNextRsvp, RsvpStatus.notGoing);
      vm.answerNext(RsvpStatus.notGoing);
      await pumpEventQueue();
      expect(vm.myNextRsvp, isNull);
    });

    testWidgets('shows on the phone page too', (tester) async {
      add(community({'owner': TeamRole.owner, 'u1': TeamRole.player}));
      final vm = homeVm();
      addTearDown(vm.dispose);
      await pump(
        tester,
        TeamHomeScreen(viewModel: vm),
        size: const Size(400, 2400),
      );
      expect(find.byKey(const ValueKey('next-pickup')), findsOneWidget);
      expect(find.text('Needs RSVP'), findsOneWidget);
    });

    testWidgets('with nothing ahead: a quiet empty state, New event for '
        'those who add events', (tester) async {
      events.events.clear();
      add(community({'owner': TeamRole.owner, 'u1': TeamRole.player}));
      final vm = homeVm();
      addTearDown(vm.dispose);
      await pump(tester, TeamHomeScreen(viewModel: vm));
      expect(find.text('No pickup scheduled'), findsOneWidget);
      expect(find.text('New event'), findsNothing);
      expect(find.byKey(const ValueKey('coming-up')), findsNothing);
    });

    testWidgets('owners get New event on the empty card', (tester) async {
      events.events.clear();
      add(community({'owner': TeamRole.owner, 'u1': TeamRole.player}));
      auth = FakeAuthRepository(
        user: const AppUser(
          uid: 'owner',
          email: 'o@b.com',
          displayName: 'Olive',
        ),
      );
      final vm = homeVm();
      addTearDown(vm.dispose);
      await pump(tester, TeamHomeScreen(viewModel: vm));
      expect(find.text('No pickup scheduled'), findsOneWidget);
      expect(find.text('New event'), findsOneWidget);
    });

    testWidgets('outsiders see the public event and Join, no answers', (
      tester,
    ) async {
      add(community({'owner': TeamRole.owner}));
      final vm = homeVm();
      addTearDown(vm.dispose);
      await pump(tester, TeamHomeScreen(viewModel: vm));
      final card = find.byKey(const ValueKey('next-pickup'));
      Finder inCard(Finder f) => find.descendant(of: card, matching: f);
      expect(inCard(find.text('Sunday pickup')), findsOneWidget);
      expect(inCard(find.textContaining('going')), findsNothing);
      expect(inCard(find.text('Needs RSVP')), findsNothing);
      expect(inCard(find.text('Join the community to RSVP.')), findsOneWidget);
      // The card's Join is the page's only one.
      expect(find.widgetWithText(FilledButton, 'Join'), findsOneWidget);
      expect(find.text('Organizers'), findsNothing);

      await tester.tap(inCard(find.widgetWithText(FilledButton, 'Join')));
      await tester.pumpAndSettle();
      expect(teams.teams['t1']!.members.containsKey(testUser.uid), isTrue);
    });

    testWidgets("outsiders with nothing public ahead keep the join card", (
      tester,
    ) async {
      events.events.clear();
      add(community({'owner': TeamRole.owner}));
      final vm = homeVm();
      addTearDown(vm.dispose);
      await pump(tester, TeamHomeScreen(viewModel: vm));
      expect(find.byKey(const ValueKey('next-pickup')), findsNothing);
      expect(find.text('No pickup scheduled'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Join'), findsOneWidget);
    });

    testWidgets("teams don't get it", (tester) async {
      final team = teamWith({'owner': TeamRole.owner, 'u1': TeamRole.player});
      add(team);
      final vm = homeVm();
      addTearDown(vm.dispose);
      await pump(tester, TeamHomeScreen(viewModel: vm));
      expect(find.byKey(const ValueKey('next-pickup')), findsNothing);
      expect(find.text('Organizers'), findsNothing);
      expect(find.text('View details'), findsOneWidget);
    });
  });

  group('chat section', () {
    testWidgets('lists the rooms the member reads, unread first, marked', (
      tester,
    ) async {
      add(community({'owner': TeamRole.owner, 'u1': TeamRole.player}));
      chats
        ..rooms['general'] = ChatRoom.general()
        ..rooms['rides'] = const ChatRoom(
          id: 'rides',
          name: 'Carpool',
          readRoles: {ChatAudience.everyone},
          writeRoles: {ChatAudience.everyone},
        )
        ..rooms['staff'] = const ChatRoom(
          id: 'staff',
          name: 'Staff',
          readRoles: {'captain'},
          writeRoles: {'captain'},
        )
        ..stampRoom('general', now)
        ..stampRoom('rides', now)
        ..stampRoom('staff', now);
      chats.reads[testUser.uid] = {
        't1': {'general': now.add(const Duration(minutes: 1))},
      };
      final vm = homeVm();
      addTearDown(vm.dispose);
      await pump(tester, TeamHomeScreen(viewModel: vm));
      expect(
        [for (final r in vm.chatSection.rooms) (r.room.id, r.unread)],
        [('rides', true), ('general', false)],
      );
      expect(find.text('Chat rooms'), findsOneWidget);
      expect(find.text('carpool'), findsOneWidget);
      expect(find.text('general'), findsOneWidget);
      expect(find.text('staff'), findsNothing);
      expect(find.byKey(const ValueKey('unread-rides')), findsOneWidget);
      expect(find.byKey(const ValueKey('unread-general')), findsNothing);
      expect(find.text('All chat'), findsOneWidget);
    });
  });

  group('organizers section', () {
    final perms = {
      'org': {
        TeamPermission.manageChats,
        TeamPermission.manageEvents,
        TeamPermission.moderate,
      },
      'mod': {TeamPermission.manageChats, TeamPermission.moderate},
    };

    testWidgets('the owner and organizers, each with Message but you', (
      tester,
    ) async {
      add(
        community({
          'owner': TeamRole.owner,
          'org': TeamRole.player,
          'mod': TeamRole.player,
          'u1': TeamRole.player,
        }, perms: perms),
      );
      final vm = homeVm();
      addTearDown(vm.dispose);
      await pump(tester, TeamHomeScreen(viewModel: vm));
      expect(find.text('Organizers'), findsOneWidget);
      expect(find.text('Olive'), findsWidgets);
      expect(find.text('OWNER'), findsWidgets);
      expect(find.text('Oscar'), findsWidgets);
      expect(find.text('ORGANIZER'), findsOneWidget);
      // A moderator only runs chat: not an organizer.
      expect(vm.organizers.map((o) => o.uid), ['owner', 'org']);
      expect(find.byKey(const ValueKey('message-owner')), findsOneWidget);
      expect(find.byKey(const ValueKey('message-org')), findsOneWidget);
      expect(find.byKey(ValueKey('message-${testUser.uid}')), findsNothing);
    });

    test('Message opens a conversation with the organizer', () async {
      add(
        community({
          'owner': TeamRole.owner,
          'org': TeamRole.player,
          'u1': TeamRole.player,
        }, perms: perms),
      );
      final vm = homeVm();
      addTearDown(vm.dispose);
      await pumpEventQueue();
      final org = vm.organizers.firstWhere((o) => o.uid == 'org');
      await vm.messageOrganizer.execute(org);
      final result = vm.messageOrganizer.result;
      expect(result, isA<Ok<String>>());
      expect(
        (result! as Ok<String>).value,
        Conversation.idFor(testUser.uid, 'org'),
      );
    });

    testWidgets('an organizer sees themselves without Message', (tester) async {
      add(community({'owner': TeamRole.owner, 'u1': TeamRole.captain}));
      final vm = homeVm();
      addTearDown(vm.dispose);
      await pump(tester, TeamHomeScreen(viewModel: vm));
      expect(find.text('Alex (you)'), findsOneWidget);
      expect(find.byKey(const ValueKey('message-owner')), findsOneWidget);
      expect(find.byKey(ValueKey('message-${testUser.uid}')), findsNothing);
    });
  });
}
