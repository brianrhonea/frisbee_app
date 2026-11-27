// Sprint 4 (B6): the team page's Message button opens a sheet: the team
// chat for members, and the staff to message directly. Parity: website
// team page.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/auth/auth_repository.dart';
import 'package:frisbee_app/data/repositories/team/team_repository.dart';
import 'package:frisbee_app/domain/models/direct_message.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/routing/routes.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/teams/view_models/team_home_viewmodel.dart';
import 'package:frisbee_app/ui/teams/widgets/team_home_screen.dart';
import 'package:frisbee_app/ui/teams/widgets/team_message_sheet.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../testing/fakes.dart';
import '../ui_harness/harness.dart';

void main() {
  late FakeTeamRepository teams;
  late FakeAuthRepository auth;
  late FakeDirectMessageRepository dms;
  final now = DateTime(2026, 10, 30, 12);

  Team team(Map<String, TeamRole> members) => teamWith(members).copyWith(
    memberNames: const {
      'owner': 'Olive',
      'coach': 'Cody',
      'u1': 'Alex',
      'p1': 'Pat',
    },
  );

  void add(Team t) {
    teams.teams[t.id] = t;
    teams.listings[t.id] = TeamListing.of(t);
  }

  setUp(() {
    teams = FakeTeamRepository();
    auth = FakeAuthRepository(user: testUser);
    dms = FakeDirectMessageRepository();
  });

  TeamHomeViewModel homeVm() {
    final vm = TeamHomeViewModel(
      teamId: 't1',
      teamRepository: teams,
      eventRepository: FakeEventRepository(),
      teamPostRepository: FakeTeamPostRepository(),
      authRepository: auth,
      filePicker: FakeFilePickerService(),
      chatRepository: FakeChatRepository(),
      directMessageRepository: dms,
      clock: () => now,
    );
    addTearDown(vm.dispose);
    return vm;
  }

  Future<GoRouter> pump(
    WidgetTester tester,
    TeamHomeViewModel vm, {
    GoldenTheme theme = GoldenTheme.light,
  }) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => TeamHomeScreen(viewModel: vm),
        ),
        GoRoute(
          path: '/messages/:id',
          builder: (_, s) => Text('Conversation ${s.pathParameters['id']}'),
        ),
        GoRoute(
          path: '/teams/:id',
          builder: (_, s) =>
              Text('Team page ${s.uri.queryParameters['section']}'),
        ),
      ],
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<TeamRepository>.value(value: teams),
          ChangeNotifierProvider<AuthRepository>.value(value: auth),
        ],
        child: MaterialApp.router(
          theme: theme == GoldenTheme.dark ? AppTheme.dark : AppTheme.light,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  Finder headerMessage() => find.widgetWithText(OutlinedButton, 'Message');

  Finder inSheet(Finder f) =>
      find.descendant(of: find.byType(TeamMessageSheet), matching: f);

  group('staff the user can message', () {
    test('a member gets the staff but not themselves', () async {
      add(
        team({
          'owner': TeamRole.owner,
          'coach': TeamRole.coach,
          testUser.uid: TeamRole.captain,
          'p1': TeamRole.player,
        }),
      );
      final vm = homeVm();
      await pumpEventQueue();
      expect([for (final o in vm.messageableStaff) o.uid], ['owner', 'coach']);
      expect(vm.showsMessage, isTrue);
    });

    test('an outsider gets the staff the team page has', () async {
      add(team({'owner': TeamRole.owner, 'coach': TeamRole.coach}));
      final vm = homeVm();
      await pumpEventQueue();
      expect(vm.isMember, isFalse);
      expect([for (final o in vm.messageableStaff) o.uid], ['owner', 'coach']);
      expect(vm.showsMessage, isTrue);
    });

    test('an outsider where no staff is readable has no Message', () async {
      // Only the listing is public; the team itself is members-only.
      final t = team({'owner': TeamRole.owner});
      teams.listings[t.id] = TeamListing.of(t);
      final vm = homeVm();
      await pumpEventQueue();
      expect(vm.messageableStaff, isEmpty);
      expect(vm.showsMessage, isFalse);
    });

    test(
      'an outsider of a private group has no staff and no Message',
      () async {
        add(team({'owner': TeamRole.owner, 'coach': TeamRole.coach}));
        teams.privateRosters.add('t1');
        final vm = homeVm();
        await pumpEventQueue();
        expect(vm.messageableStaff, isEmpty);
        expect(vm.showsMessage, isFalse);
      },
    );

    test('a member does not ask the roster endpoint', () async {
      add(team({'owner': TeamRole.owner, testUser.uid: TeamRole.player}));
      final vm = homeVm();
      await pumpEventQueue();
      expect(teams.staffCalls, isEmpty);
      expect([for (final o in vm.messageableStaff) o.uid], ['owner']);
    });

    test('a signed-out visitor has no Message', () async {
      add(team({'owner': TeamRole.owner}));
      auth = FakeAuthRepository();
      final vm = homeVm();
      await pumpEventQueue();
      expect(vm.showsMessage, isFalse);
    });
  });

  group('the sheet', () {
    testWidgets('a member sees Team chat first, then the staff', (
      tester,
    ) async {
      add(
        team({
          'owner': TeamRole.owner,
          'coach': TeamRole.coach,
          testUser.uid: TeamRole.player,
        }),
      );
      await pump(tester, homeVm());
      await tester.tap(headerMessage());
      await tester.pumpAndSettle();
      expect(inSheet(find.text('Team chat')), findsOneWidget);
      expect(inSheet(find.text('Olive')), findsOneWidget);
      expect(inSheet(find.text('Cody')), findsOneWidget);
      // Team chat is above the staff.
      expect(
        tester.getTopLeft(inSheet(find.text('Team chat'))).dy,
        lessThan(tester.getTopLeft(inSheet(find.text('Olive'))).dy),
      );
      // Not themselves.
      expect(inSheet(find.text('Alex')), findsNothing);
      expect(inSheet(find.byKey(const ValueKey('message-owner'))), findsOne);

      await tester.tap(inSheet(find.text('Team chat')));
      await tester.pumpAndSettle();
      expect(find.text('Team page chat'), findsOneWidget);
    });

    testWidgets('Message on a staff member opens a conversation', (
      tester,
    ) async {
      add(team({'owner': TeamRole.owner, testUser.uid: TeamRole.player}));
      await pump(tester, homeVm());
      await tester.tap(headerMessage());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('message-owner')));
      await tester.pumpAndSettle();
      expect(
        find.text('Conversation ${Conversation.idFor(testUser.uid, 'owner')}'),
        findsOneWidget,
      );
    });

    testWidgets('an outsider sees the staff and no Team chat', (tester) async {
      add(team({'owner': TeamRole.owner, 'coach': TeamRole.coach}));
      await pump(tester, homeVm());
      expect(headerMessage(), findsOneWidget);
      await tester.tap(headerMessage());
      await tester.pumpAndSettle();
      expect(inSheet(find.text('Team chat')), findsNothing);
      expect(inSheet(find.text('Olive')), findsOneWidget);
      expect(inSheet(find.text('Cody')), findsOneWidget);
    });

    testWidgets("a refused message shows the server's error", (tester) async {
      add(team({'owner': TeamRole.owner, testUser.uid: TeamRole.player}));
      dms.policies['owner'] = MessagePolicy.nobody;
      final router = await pump(tester, homeVm());
      await tester.tap(headerMessage());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('message-owner')));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('Olive'), findsWidgets);
      // Still on the team page.
      expect(
        router.routeInformationProvider.value.uri.path,
        isNot(startsWith('/messages')),
      );
      expect(Routes.conversation('x'), startsWith('/messages'));
    });

    testWidgets('a member with no staff to message still gets Team chat', (
      tester,
    ) async {
      add(team({testUser.uid: TeamRole.owner, 'p1': TeamRole.player}));
      await pump(tester, homeVm());
      await tester.tap(headerMessage());
      await tester.pumpAndSettle();
      expect(inSheet(find.text('Team chat')), findsOneWidget);
      expect(inSheet(find.text('Staff')), findsNothing);
    });

    for (final theme in GoldenTheme.values) {
      testWidgets('meets guidelines, ${theme.name}', (tester) async {
        add(
          team({
            'owner': TeamRole.owner,
            'coach': TeamRole.coach,
            testUser.uid: TeamRole.player,
          }),
        );
        await pump(tester, homeVm(), theme: theme);
        await tester.tap(headerMessage());
        await tester.pumpAndSettle();
        await expectAccessible(tester);
      });
    }
  });
}
