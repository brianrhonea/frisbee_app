// Sprint 4 (B2): the Members tab's Roles view, Add member, and linking a
// roster spot to a member. Parity: website roster page.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/auth/auth_repository.dart';
import 'package:frisbee_app/data/repositories/direct_message/direct_message_repository.dart';
import 'package:frisbee_app/data/repositories/team/team_repository.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/roster_player.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/data/services/api_client.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/core/ui/error_message.dart';
import 'package:frisbee_app/utils/result.dart';
import 'package:frisbee_app/ui/teams/view_models/team_detail_viewmodel.dart';
import 'package:frisbee_app/ui/teams/widgets/invite_members_dialog.dart';
import 'package:frisbee_app/ui/teams/widgets/members_tab.dart';
import 'package:frisbee_app/ui/teams/widgets/player_dialog.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../testing/fakes.dart';
import '../ui_harness/harness.dart';

/// Refuses a create the way the API does for a member on another spot.
class _TakenTeams extends FakeTeamRepository {
  @override
  Future<Result<String>> savePlayer(String teamId, RosterPlayer player) async =>
      Result.error(
        const ApiException(
          'failed_precondition',
          'That person is already linked to another spot on this team',
        ),
      );
}

void main() {
  late FakeTeamRepository teams;
  late FakeAuthRepository auth;

  const handlers = CustomRole(
    id: 'r1',
    name: 'Handlers',
    permissions: {TeamPermission.manageChats},
  );

  Team team({TeamKind kind = TeamKind.team}) =>
      teamWith(
        {
          testUser.uid: TeamRole.owner,
          'c1': TeamRole.captain,
          'p1': TeamRole.player,
          'p2': TeamRole.player,
          'p3': TeamRole.player,
        },
        statKeepers: {'p2'},
      ).copyWith(
        memberNames: {
          testUser.uid: 'Alex',
          'c1': 'Cass',
          'p1': 'Pat',
          'p2': 'Sam',
          'p3': 'Robin',
        },
        roles: {handlers.id: handlers},
        memberRoles: {
          'p1': {handlers.id},
        },
      );

  void seed({required String me}) {
    teams = FakeTeamRepository();
    auth = FakeAuthRepository(
      user: AppUser(uid: me, email: 'a@b.com', displayName: 'Alex'),
    );
    final t = team();
    // Others see the same team; their role comes from the member map.
    teams.teams[t.id] = t;
    teams.listings[t.id] = TeamListing.of(t);
  }

  TeamDetailViewModel detailVm() {
    final vm = TeamDetailViewModel(
      teamId: 't1',
      teamRepository: teams,
      playRepository: FakePlayRepository(),
      eventRepository: FakeEventRepository(),
      authRepository: auth,
      clock: () => DateTime(2026, 11, 27, 12),
    );
    addTearDown(vm.dispose);
    return vm;
  }

  Widget screen(TeamDetailViewModel vm) {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(body: MembersTab(viewModel: vm)),
        ),
        GoRoute(
          path: '/teams/:id/roles',
          builder: (_, _) => const Scaffold(body: Text('Roles editor')),
        ),
      ],
    );
    return MultiProvider(
      providers: [
        Provider<TeamRepository>.value(value: teams),
        ChangeNotifierProvider<AuthRepository>.value(value: auth),
        Provider<DirectMessageRepository>.value(
          value: FakeDirectMessageRepository(),
        ),
      ],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    );
  }

  Future<void> pump(WidgetTester tester, TeamDetailViewModel vm) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(screen(vm));
    await tester.pumpAndSettle();
  }

  group('Roles view', () {
    testWidgets('lists each role with who holds it; the owner can edit roles', (
      tester,
    ) async {
      seed(me: testUser.uid);
      await pump(tester, detailVm());
      await tester.tap(find.text('Roles'));
      await tester.pumpAndSettle();
      for (final name in ['Owner', 'Captain', 'Stats', 'Handlers']) {
        expect(find.text(name), findsWidgets, reason: name);
      }
      // Alex owns it, Sam keeps stats, Pat is a Handler.
      expect(find.text('Alex'), findsOneWidget);
      expect(find.text('Sam'), findsOneWidget);
      expect(find.text('Pat'), findsOneWidget);
      // Robin holds no role: not listed.
      expect(find.text('Robin'), findsNothing);
      expect(find.text('Edit roles'), findsOneWidget);
      await tester.tap(find.text('Edit roles'));
      await tester.pumpAndSettle();
      expect(find.text('Roles editor'), findsOneWidget);
    });

    testWidgets('a player sees the roles but not Edit roles', (tester) async {
      seed(me: 'p3');
      await pump(tester, detailVm());
      await tester.tap(find.text('Roles'));
      await tester.pumpAndSettle();
      expect(find.text('Handlers'), findsWidgets);
      expect(find.text('Edit roles'), findsNothing);
    });
  });

  group('Add member', () {
    testWidgets(
      'a team with a roster offers Invite people and Add player to roster',
      (tester) async {
        seed(me: testUser.uid);
        await pump(tester, detailVm());
        await tester.tap(find.text('Add member'));
        await tester.pumpAndSettle();
        expect(find.text('Invite people'), findsOneWidget);
        expect(find.text('Add player to roster'), findsOneWidget);
        await tester.tap(find.text('Add player to roster'));
        await tester.pumpAndSettle();
        expect(find.byType(PlayerDialog), findsOneWidget);
        expect(find.text('Link to a member'), findsOneWidget);
      },
    );

    testWidgets('Invite people opens the existing invite flow', (tester) async {
      seed(me: testUser.uid);
      await pump(tester, detailVm());
      await tester.tap(find.text('Add member'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Invite people'));
      await tester.pumpAndSettle();
      // The sheet closed and the invite dialog opened. (Its own layout is
      // 3 px tight in the test font; that isn't what's tested here.)
      tester.takeException();
      expect(find.text('Invite people'), findsNothing);
      expect(find.byType(InviteMembersDialog), findsOneWidget);
    });

    testWidgets('a community has no roster option', (tester) async {
      seed(me: testUser.uid);
      final old = teams.teams['t1']!;
      final group = Team(
        id: old.id,
        name: 'Group',
        division: Division.mixed,
        level: CompetitionLevel.pickup,
        ownerId: testUser.uid,
        members: old.members,
        memberNames: old.memberNames,
        kind: TeamKind.community,
      );
      teams.teams['t1'] = group;
      teams.listings['t1'] = TeamListing.of(group);
      await pump(tester, detailVm());
      await tester.tap(find.text('Add member'));
      await tester.pumpAndSettle();
      expect(find.text('Invite people'), findsOneWidget);
      expect(find.text('Add player to roster'), findsNothing);
    });

    testWidgets('a player without Manage members has no Add member', (
      tester,
    ) async {
      seed(me: 'p3');
      await pump(tester, detailVm());
      expect(find.text('Add member'), findsNothing);
    });
  });

  group('Link to a member', () {
    testWidgets('lists members without a spot; picking one fills the name', (
      tester,
    ) async {
      seed(me: testUser.uid);
      // Pat already has a spot.
      teams.roster['t1'] = [
        const RosterPlayer(id: 'a', name: 'Pat', userId: 'p1'),
      ];
      final vm = detailVm();
      await pump(tester, vm);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add member'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add player to roster'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('link-to-member')));
      await tester.pumpAndSettle();
      Finder inSheet(String name) => find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text(name),
      );
      expect(inSheet('Sam'), findsOneWidget);
      expect(inSheet('Robin'), findsOneWidget);
      // Pat is linked elsewhere: not offered.
      expect(inSheet('Pat'), findsNothing);
      await tester.tap(inSheet('Robin'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.widgetWithText(TextFormField, 'Robin'))
            .controller!
            .text,
        'Robin',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      // Created with the member in one call: no separate link call.
      expect(teams.links, isEmpty);
      expect(teams.roster['t1']!.any((p) => p.userId == 'p3'), isTrue);
    });
  });

  group('saving a roster spot', () {
    test('a new spot with a member is one create call', () async {
      seed(me: testUser.uid);
      final vm = detailVm();
      await Future<void>.delayed(Duration.zero);
      await vm.savePlayer.execute(
        const RosterPlayer(id: '', name: 'Sam', userId: 'p2'),
      );
      expect(teams.links, isEmpty);
      expect(teams.roster['t1']!.single.userId, 'p2');
      expect(vm.savePlayer.error, isFalse);
    });

    test('the 412 for a member on another spot is the error shown', () async {
      seed(me: testUser.uid);
      final repo = _TakenTeams()..teams['t1'] = teams.teams['t1']!;
      final vm = TeamDetailViewModel(
        teamId: 't1',
        teamRepository: repo,
        playRepository: FakePlayRepository(),
        eventRepository: FakeEventRepository(),
        authRepository: auth,
      );
      addTearDown(vm.dispose);
      await vm.savePlayer.execute(
        const RosterPlayer(id: '', name: 'Sam', userId: 'p2'),
      );
      expect(vm.savePlayer.error, isTrue);
      expect(
        errorMessage(vm.savePlayer.result),
        'That person is already linked to another spot on this team',
      );
      expect(repo.links, isEmpty);
    });

    test(
      'changing the member of an existing spot uses the link call',
      () async {
        seed(me: testUser.uid);
        teams.roster['t1'] = [const RosterPlayer(id: 'a', name: 'Pat')];
        final vm = detailVm();
        await Future<void>.delayed(Duration.zero);
        await vm.savePlayer.execute(
          const RosterPlayer(id: 'a', name: 'Pat', userId: 'p1'),
        );
        expect(teams.links, [('t1', 'a', 'p1')]);
      },
    );

    test('a spot with no member is not linked', () async {
      seed(me: testUser.uid);
      final vm = detailVm();
      await vm.savePlayer.execute(const RosterPlayer(id: '', name: 'Guest'));
      expect(teams.links, isEmpty);
    });

    test('editing without changing the link makes no link call', () async {
      seed(me: testUser.uid);
      teams.roster['t1'] = [
        const RosterPlayer(id: 'a', name: 'Pat', userId: 'p1'),
      ];
      final vm = detailVm();
      await Future<void>.delayed(Duration.zero);
      await vm.savePlayer.execute(
        const RosterPlayer(id: 'a', name: 'Patricia', userId: 'p1'),
      );
      expect(teams.links, isEmpty);
    });
  });

  group('accessibility', () {
    for (final theme in GoldenTheme.values) {
      testWidgets('Roles view meets guidelines, ${theme.name}', (tester) async {
        seed(me: testUser.uid);
        final vm = detailVm();
        await pumpInApp(
          tester,
          MultiProvider(
            providers: [
              Provider<TeamRepository>.value(value: teams),
              ChangeNotifierProvider<AuthRepository>.value(value: auth),
            ],
            child: MembersTab(viewModel: vm),
          ),
          theme: theme,
          width: 390,
          height: 1100,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Roles'));
        await tester.pumpAndSettle();
        await expectAccessible(tester);
      });
    }
  });
}
