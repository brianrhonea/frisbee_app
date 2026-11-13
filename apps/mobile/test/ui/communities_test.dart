import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/team_event.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/schedule/view_models/event_editor_viewmodel.dart';
import 'package:frisbee_app/ui/schedule/widgets/event_editor_screen.dart';
import 'package:frisbee_app/ui/teams/view_models/community_teams_viewmodel.dart';
import 'package:frisbee_app/ui/teams/view_models/team_community_viewmodel.dart';
import 'package:frisbee_app/ui/teams/widgets/community_teams_tab.dart';
import 'package:frisbee_app/ui/teams/widgets/team_community_sheet.dart';

import '../testing/fakes.dart';

const _member = 'm1';

/// "Tech Ultimate", owned by the test user, with one plain member.
Team _org({Map<String, CustomRole> roles = const {}}) => Team(
  id: 'org',
  name: 'Tech Ultimate',
  division: Division.mixed,
  level: CompetitionLevel.college,
  ownerId: testUser.uid,
  kind: TeamKind.organization,
  members: {testUser.uid: TeamRole.owner, _member: TeamRole.player},
  memberNames: {testUser.uid: 'Test User', _member: 'Mo'},
  roles: roles,
);

void main() {
  late FakeTeamRepository teams;
  late FakeAuthRepository auth;

  setUp(() {
    teams = FakeTeamRepository()..teams['org'] = _org();
    auth = FakeAuthRepository(user: testUser);
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(Scaffold(body: child)));
    await tester.pumpAndSettle();
  }

  Future<void> giveRole(String uid, Set<String> roleIds) async {
    final org = teams.teams['org']!;
    await teams.saveRoles(
      org,
      roles: org.roles,
      memberRoles: {...org.memberRoles, uid: roleIds},
    );
  }

  test('a role puts a member on its teams, and losing it takes them off', () {
    final org =
        _org(
          roles: const {'woof': CustomRole(id: 'woof', name: 'Woof')},
        ).copyWith(
          memberRoles: {
            _member: {'woof'},
          },
          linkedTeams: const {
            'w': LinkedTeam(id: 'w', name: 'Woof', roles: {'woof'}),
            'x': LinkedTeam(id: 'x', name: 'Whiplash', roles: {'whip'}),
          },
        );
    expect(org.teamsFor(_member), {'w'});
    expect(org.eventAudienceOf(_member), {'everyone', 'player', 'woof'});
    // The owner sees every event; teams have no audience at all.
    expect(org.eventAudienceOf(testUser.uid), isNull);
    expect(
      Team(
        id: 't',
        name: 'T',
        division: Division.open,
        level: CompetitionLevel.club,
        ownerId: 'o',
        members: const {_member: TeamRole.player},
      ).eventAudienceOf(_member),
      isNull,
    );
  });

  testWidgets('an admin makes a team with a new role; role holders join it', (
    tester,
  ) async {
    final vm = CommunityTeamsViewModel(
      orgId: 'org',
      teamRepository: teams,
      authRepository: auth,
    );
    addTearDown(vm.dispose);
    await pump(tester, CommunityTeamsTab(viewModel: vm));
    expect(find.text('No teams yet'), findsOne);

    await tester.tap(find.text('New team'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Woof');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    // The division is for good, so it's confirmed first.
    expect(find.text('Is Open the right division?'), findsOneWidget);
    await tester.tap(find.text('Yes, Open'));
    await tester.pumpAndSettle();
    // No roles yet, so the owner is offered one named after the team.
    expect(
      tester
          .widget<CheckboxListTile>(
            find.widgetWithText(CheckboxListTile, 'A new role'),
          )
          .value,
      isTrue,
    );
    await tester.tap(find.text('Create team'));
    await tester.pumpAndSettle();

    final org = teams.teams['org']!;
    final role = org.roles.values.single;
    expect(role.name, 'Woof');
    final woofId = org.linkedTeams.keys.single;
    final woof = teams.teams[woofId]!;
    expect(woof.orgId, 'org');
    expect(woof.inCommunity, isTrue);
    expect(woof.members.keys, [testUser.uid]);

    // Giving Mo the role puts them on Woof; taking it away removes them.
    await giveRole(_member, {role.id});
    expect(teams.teams[woofId]!.members[_member], TeamRole.player);
    expect(teams.teams[woofId]!.orgMembers, {_member});
    await giveRole(_member, {});
    expect(teams.teams[woofId]!.members.containsKey(_member), isFalse);
  });

  testWidgets('admins can invite people to its teams; members can\'t', (
    tester,
  ) async {
    teams.teams['org'] = _org().copyWith(
      linkedTeams: const {'w': LinkedTeam(id: 'w', name: 'Woof')},
    );
    final vm = CommunityTeamsViewModel(
      orgId: 'org',
      teamRepository: teams,
      authRepository: auth,
    );
    addTearDown(vm.dispose);
    await pump(tester, CommunityTeamsTab(viewModel: vm));
    expect(vm.canInvite, isTrue);
    await tester.tap(find.byTooltip('Team options'));
    await tester.pumpAndSettle();
    expect(find.text('Invite people'), findsOneWidget);
    final target = vm.inviteTarget(vm.teams.single);
    expect((target.id, target.name, target.orgId), ('w', 'Woof', 'org'));
    expect(target.isCommunity, isFalse);

    // A plain member has no team menu at all.
    final member = CommunityTeamsViewModel(
      orgId: 'org',
      teamRepository: teams,
      authRepository: FakeAuthRepository(
        user: const AppUser(uid: _member, email: 'm@b.com'),
      ),
    );
    addTearDown(member.dispose);
    await tester.pump();
    expect(member.canInvite, isFalse);
  });

  testWidgets('a team asks to join; the community adds it with a role', (
    tester,
  ) async {
    teams.teams['org'] = _org(
      roles: const {'whip': CustomRole(id: 'whip', name: 'Whiplash')},
    );
    teams.listings['org'] = TeamListing.of(teams.teams['org']!);
    teams.teams['wl'] = Team(
      id: 'wl',
      name: 'Whiplash',
      division: Division.women,
      level: CompetitionLevel.college,
      ownerId: 'cap',
      members: const {'cap': TeamRole.owner},
    );
    await giveRole(_member, {'whip'});

    // Whiplash's owner finds the community and asks.
    final captain = FakeAuthRepository(
      user: const AppUser(uid: 'cap', email: 'c@x.org', displayName: 'Cap'),
    );
    final sheetVm = TeamCommunityViewModel(
      teamId: 'wl',
      teamRepository: teams,
      authRepository: captain,
    );
    addTearDown(sheetVm.dispose);
    await pump(tester, TeamCommunitySheet(viewModel: sheetVm));
    await tester.enterText(find.byType(TextField), 'Tech');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ask to join').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Ask to join'));
    await tester.pumpAndSettle();
    expect(find.text('Waiting for Tech Ultimate to add the team.'), findsOne);
    expect(teams.teams['wl']!.communityPending, isTrue);

    // The community's owner adds it for the Whiplash role.
    final vm = CommunityTeamsViewModel(
      orgId: 'org',
      teamRepository: teams,
      authRepository: auth,
    );
    addTearDown(vm.dispose);
    await pump(tester, CommunityTeamsTab(viewModel: vm));
    expect(find.text('1 team wants to join'), findsOne);
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Whiplash'));
    await tester.tap(find.widgetWithText(FilledButton, 'Add team'));
    await tester.pumpAndSettle();

    final wl = teams.teams['wl']!;
    expect(wl.inCommunity, isTrue);
    expect(wl.members[_member], TeamRole.player);
    expect(find.textContaining('For Whiplash'), findsOne);
    expect(teams.teams['org']!.roles.length, 1, reason: 'no extra role made');

    // Leaving takes off the people the community added.
    await teams.leaveCommunity(teams.teams['wl']!);
    expect(teams.teams['wl']!.members.keys, ['cap']);
    expect(teams.teams['org']!.linkedTeams, isEmpty);
  });

  testWidgets('community events say which roles see them', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 1800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    teams.teams['org'] = _org(
      roles: const {'woof': CustomRole(id: 'woof', name: 'Woof')},
    );
    final events = FakeEventRepository();
    final vm = EventEditorViewModel(
      teamId: 'org',
      eventId: null,
      eventRepository: events,
      teamRepository: teams,
      authRepository: auth,
    );
    await tester.runAsync(pumpEventQueue);
    await tester.pumpWidget(_app(EventEditorScreen(viewModel: vm)));
    await tester.pump();
    expect(find.text('Who sees it'), findsOne);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Title'),
      'Woof practice',
    );
    await tester.tap(find.widgetWithText(FilterChip, 'Woof'));
    await tester.pump();
    await tester.tap(find.text('Create event'));
    await tester.pumpAndSettle();
    final saved = events.events.values.single;
    expect(saved.audience, {'woof'});
    expect(saved.toEditableMap()['audience'], ['woof']);

    // Only members holding an id in it get the event.
    final seen = await events
        .watchEvents('org', audience: {'everyone', 'player'})
        .first;
    expect(seen, isEmpty);
    expect(
      await events.watchEvents('org', audience: {'woof'}).first,
      isA<List<TeamEvent>>().having((l) => l.length, 'length', 1),
    );
  });
}

/// [home] at `/`, and a stand-in page for wherever it goes next.
Widget _app(Widget home) => MaterialApp.router(
  theme: AppTheme.light,
  routerConfig: GoRouter(
    routes: [GoRoute(path: '/', builder: (_, _) => home)],
    errorBuilder: (_, state) => Scaffold(body: Text('at ${state.uri}')),
  ),
);
