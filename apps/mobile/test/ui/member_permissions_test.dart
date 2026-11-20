// Role presets and per-person permission switches (F25). The website's
// side of the same rules is in packages/shared (role_presets.test.ts)
// and the API (membership.test.ts, "per-person permissions").
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/auth/auth_repository.dart';
import 'package:frisbee_app/data/repositories/team/team_repository.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/teams/view_models/team_detail_viewmodel.dart';
import 'package:frisbee_app/ui/teams/widgets/member_permissions_dialog.dart';
import 'package:frisbee_app/ui/teams/widgets/members_tab.dart';
import 'package:provider/provider.dart';

import '../testing/fakes.dart';

void main() {
  late FakeTeamRepository teams;
  late FakeAuthRepository auth;

  const chat = CustomRole(
    id: 'r1',
    name: 'Chat crew',
    permissions: {TeamPermission.manageChats},
  );

  setUp(() {
    teams = FakeTeamRepository();
    auth = FakeAuthRepository(user: testUser);
    final team =
        teamWith({
          testUser.uid: TeamRole.owner,
          'pat': TeamRole.player,
          'cody': TeamRole.coach,
        }).copyWith(
          memberNames: {testUser.uid: 'Alex', 'pat': 'Pat', 'cody': 'Cody'},
        );
    teams.teams[team.id] = team;
    teams.listings[team.id] = TeamListing.of(team);
  });

  TeamDetailViewModel detailVm() => TeamDetailViewModel(
    teamId: 't1',
    teamRepository: teams,
    playRepository: FakePlayRepository(),
    eventRepository: FakeEventRepository(),
    authRepository: auth,
  );

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(900, 1600);
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

  bool switchOn(WidgetTester tester, String label) => tester
      .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, label))
      .value;

  testWidgets('a preset in one tap; changing a switch makes it Custom', (
    tester,
  ) async {
    Set<TeamPermission>? saved;
    await pump(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () async => saved = await showMemberPermissions(
            context,
            team: teams.teams['t1']!,
            uid: 'pat',
          ),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Permissions for Pat'), findsOneWidget);
    // Nothing of their own yet: the Member preset.
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Member'))
          .selected,
      isTrue,
    );

    await tester.tap(find.widgetWithText(ChoiceChip, 'Captain'));
    await tester.pumpAndSettle();
    expect(switchOn(tester, 'Manage events'), isTrue);
    expect(switchOn(tester, 'Keep stats'), isTrue);
    expect(switchOn(tester, 'Manage team'), isFalse);
    expect(find.text('Custom'), findsNothing);

    // One more switch: no preset has that mix.
    await tester.tap(find.widgetWithText(SwitchListTile, 'Manage team'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ChoiceChip, 'Custom'), findsOneWidget);
    expect(find.text('Your own mix of the permissions below.'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved, {
      TeamPermission.manageTeam,
      TeamPermission.manageChats,
      TeamPermission.manageEvents,
      TeamPermission.moderate,
      TeamPermission.keepStats,
    });
  });

  testWidgets("a role's permissions are on and locked, naming the role", (
    tester,
  ) async {
    final t = teams.teams['t1']!;
    teams.teams['t1'] = t.copyWith(
      roles: {chat.id: chat},
      memberRoles: {
        'pat': {chat.id},
      },
    );
    await pump(
      tester,
      Scaffold(
        body: MemberPermissionsDialog(team: teams.teams['t1']!, uid: 'pat'),
      ),
    );
    final tile = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Manage chats'),
    );
    expect(tile.value, isTrue);
    expect(tile.onChanged, isNull);
    expect(find.textContaining('From the Chat crew role.'), findsOneWidget);
  });

  testWidgets("groups' presets keep no stats", (tester) async {
    final group = Team(
      id: 'g1',
      name: 'Pickup',
      division: Division.mixed,
      level: CompetitionLevel.pickup,
      kind: TeamKind.community,
      ownerId: testUser.uid,
      members: {testUser.uid: TeamRole.owner, 'pat': TeamRole.player},
    );
    await pump(
      tester,
      Scaffold(
        body: MemberPermissionsDialog(team: group, uid: 'pat'),
      ),
    );
    expect(find.widgetWithText(ChoiceChip, 'Moderator'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Stat keeper'), findsNothing);
    expect(find.widgetWithText(SwitchListTile, 'Keep stats'), findsNothing);
  });

  testWidgets('the owner opens Permissions from the member menu and saves; '
      'the row shows the preset', (tester) async {
    final vm = detailVm();
    addTearDown(vm.dispose);
    await pump(
      tester,
      Scaffold(
        body: ListenableBuilder(
          listenable: vm,
          builder: (_, _) =>
              vm.team == null ? const SizedBox() : MembersTab(viewModel: vm),
        ),
      ),
    );
    // Pat's menu (the coach has every permission: no Permissions item).
    expect(vm.canSetPermissions('pat'), isTrue);
    expect(vm.canSetPermissions('cody'), isFalse);
    expect(vm.canSetPermissions(testUser.uid), isFalse);
    final patRow = find.ancestor(
      of: find.text('Pat'),
      matching: find.byType(ListTile),
    );
    await tester.tap(
      find.descendant(
        of: patRow,
        matching: find.byType(PopupMenuButton<String>),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Permissions'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Coach'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(teams.permissionCalls.single.uid, 'pat');
    expect(teams.permissionCalls.single.perms, {
      TeamPermission.manageTeam,
      TeamPermission.manageMembers,
      TeamPermission.manageEvents,
      TeamPermission.keepStats,
    });
    expect(find.text('Player · Coach'), findsOneWidget);
    expect(vm.team!.has('pat', TeamPermission.manageMembers), isTrue);
  });

  testWidgets('a non-owner never sees Permissions', (tester) async {
    auth = FakeAuthRepository(
      user: const AppUser(uid: 'cody', email: 'c@d.com', displayName: 'Cody'),
    );
    final vm = detailVm();
    addTearDown(vm.dispose);
    await tester.pumpAndSettle();
    expect(vm.canSetPermissions('pat'), isFalse);
  });
}
