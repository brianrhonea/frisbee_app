import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:frisbee_app/domain/models/direct_message.dart';
import 'package:frisbee_app/domain/models/invite_code.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/team_post.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/teams/view_models/invite_code_viewmodel.dart';
import 'package:frisbee_app/ui/teams/view_models/invite_members_viewmodel.dart';
import 'package:frisbee_app/ui/teams/view_models/join_link_viewmodel.dart';
import 'package:frisbee_app/ui/teams/view_models/team_home_viewmodel.dart';
import 'package:frisbee_app/ui/teams/view_models/teams_viewmodel.dart';
import 'package:frisbee_app/ui/teams/widgets/invite_code_card.dart';
import 'package:frisbee_app/ui/teams/widgets/join_link_screen.dart';
import 'package:frisbee_app/utils/result.dart';

import '../testing/fakes.dart';

void main() {
  late FakeTeamRepository teams;
  late FakeAuthRepository auth;

  setUp(() {
    teams = FakeTeamRepository();
    auth = FakeAuthRepository(user: testUser);
  });

  Team makeGroup({
    Map<String, TeamRole> members = const {'owner': TeamRole.owner},
    bool requiresApproval = true,
  }) => Team(
    id: 'g1',
    name: 'Friends',
    division: Division.mixed,
    level: CompetitionLevel.pickup,
    ownerId: 'owner',
    members: members,
    memberNames: {for (final uid in members.keys) uid: uid},
    kind: TeamKind.community,
    requiresApproval: requiresApproval,
  );

  group('private groups', () {
    TeamHomeViewModel homeVm(FakeTeamPostRepository posts) => TeamHomeViewModel(
      teamId: 'g1',
      teamRepository: teams,
      eventRepository: FakeEventRepository(),
      teamPostRepository: posts,
      authRepository: auth,
      filePicker: FakeFilePickerService(),
    );

    final publicPost = TeamPost(
      id: 'p1',
      title: '',
      body: 'Hi',
      authorId: 'owner',
      authorName: 'O',
      isPublic: true,
      createdAt: DateTime(2026, 10, 1),
    );

    test('outsiders see the listing only, not posts', () async {
      final g = makeGroup();
      teams.listings['g1'] = TeamListing.of(g);
      final posts = FakeTeamPostRepository()..posts['g1'] = [publicPost];
      final vm = homeVm(posts);
      await pumpEventQueue();
      expect(vm.isPrivateToMe, isTrue);
      expect(vm.posts, isEmpty);
      vm.dispose();
    });

    test('an open group still shows outsiders its public posts', () async {
      final g = makeGroup(requiresApproval: false);
      teams.listings['g1'] = TeamListing.of(g);
      final posts = FakeTeamPostRepository()..posts['g1'] = [publicPost];
      final vm = homeVm(posts);
      await pumpEventQueue();
      expect(vm.isPrivateToMe, isFalse);
      expect(vm.posts.map((p) => p.id), ['p1']);
      vm.dispose();
    });
  });

  group('invites', () {
    test('organizers find people and invite them', () async {
      final g = makeGroup(
        members: {'owner': TeamRole.owner, testUser.uid: TeamRole.captain},
      );
      teams.teams['g1'] = g;
      final people = FakeDirectMessageRepository()
        ..profiles.addAll(const [
          UserProfile(uid: 'sam', name: 'Sam Lee'),
          UserProfile(uid: 'owner', name: 'Sandy Owner'),
        ]);
      final vm = InviteMembersViewModel(
        team: g,
        teamRepository: teams,
        directMessageRepository: people,
        authRepository: auth,
        debounce: Duration.zero,
      );

      vm.search('s');
      expect(vm.searching, isFalse, reason: 'too short to search');
      vm.search('sa');
      expect(vm.searching, isTrue);
      await pumpEventQueue();
      expect(vm.results.map((p) => p.uid), ['sam', 'owner']);
      expect(vm.isMember('owner'), isTrue);
      expect(vm.isMember('sam'), isFalse);

      expect(
        vm.link.toString(),
        'https://frisbee-app-brianrhonea.web.app/g/g1',
        reason: "groups have no code; the link opens the group's page",
      );

      await vm.invite.execute(vm.results.first);
      expect(vm.invite.completed, isTrue);
      expect(vm.wasInvited('sam'), isTrue);
      final sent = teams.invites['sam']!.single;
      expect(sent.teamName, 'Friends');
      expect(sent.isCommunity, isTrue);
      expect(sent.invitedByName, testUser.label);
      // And the link, as a direct message.
      final dm = people.messages[Conversation.idFor(testUser.uid, 'sam')]!;
      expect(
        dm.single.text,
        'Join Friends on Stall 10: https://frisbee-app-brianrhonea.web.app/g/g1',
      );

      await vm.invite.execute(vm.results.last);
      expect(vm.invite.error, isTrue, reason: 'already a member');
      vm.dispose();
    });

    test("a team's link is made on demand and expires", () async {
      final t = teamWith({testUser.uid: TeamRole.owner});
      teams.teams['t1'] = t;
      final vm = InviteMembersViewModel(
        team: t,
        teamRepository: teams,
        directMessageRepository: FakeDirectMessageRepository(),
        authRepository: auth,
      );
      // Nothing is minted until the link is copied, shared or sent.
      expect(vm.link, isNull);
      expect(teams.inviteCodes, isEmpty);
      expect(vm.expiry, InviteLinkExpiry.week);

      await vm.createLink.execute();
      final token = vm.link!.pathSegments.last;
      expect(
        vm.link.toString(),
        'https://frisbee-app-brianrhonea.web.app/join/$token',
      );
      expect(vm.shareText, 'Join Team on Stall 10: ${vm.link}');
      expect(teams.linkExpiries[token], InviteLinkExpiry.week);
      expect(
        vm.linkExpiresAt!.difference(DateTime.now()).inHours,
        closeTo(7 * 24, 1),
      );
      // Copying again reuses it.
      await vm.createLink.execute();
      expect(teams.inviteCodes, hasLength(1));

      // A different expiry makes a new link next time.
      vm.setExpiry(InviteLinkExpiry.hour);
      expect(vm.link, isNull);
      await vm.createLink.execute();
      final hourToken = vm.link!.pathSegments.last;
      expect(hourToken, isNot(token));
      expect(teams.linkExpiries[hourToken], InviteLinkExpiry.hour);
      expect(await teams.resolveInviteCode(hourToken), isA<Ok<String>>());
      vm.dispose();
    });

    test('an expired link no longer joins', () async {
      teams.teams['t1'] = teamWith({'owner': TeamRole.owner});
      teams.inviteCodes['OLD'] = InviteCode(
        code: 'OLD',
        teamId: 't1',
        expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      expect(await teams.resolveInviteCode('OLD'), isA<Error<String>>());
      expect(await teams.joinTeam('OLD', testUser), isA<Error<String>>());
      expect(teams.teams['t1']!.roleOf(testUser.uid), isNull);
    });

    test("a link that can't be made says why", () async {
      final t = teamWith({testUser.uid: TeamRole.owner});
      teams.teams['t1'] = t;
      teams.mintError = Exception('permission-denied');
      final vm = InviteMembersViewModel(
        team: t,
        teamRepository: teams,
        directMessageRepository: FakeDirectMessageRepository(),
        authRepository: auth,
      );
      await vm.createLink.execute();
      expect(vm.createLink.error, isTrue);
      expect(vm.link, isNull);
      vm.dispose();
    });

    TeamsViewModel teamsVm() =>
        TeamsViewModel(teamRepository: teams, authRepository: auth);

    test('the invitee accepts and joins without a code', () async {
      final g = makeGroup();
      teams.teams['g1'] = g;
      await teams.inviteToTeam(g, testUser.uid, testUser);
      final vm = teamsVm();
      await pumpEventQueue();
      expect(vm.invites.single.teamName, 'Friends');

      await vm.acceptInvite.execute(vm.invites.single);
      await pumpEventQueue();
      expect(vm.acceptInvite.completed, isTrue);
      expect(vm.invites, isEmpty);
      expect(vm.groups.single.roleOf(testUser.uid), TeamRole.player);
      vm.dispose();
    });

    test('the invitee declines', () async {
      final g = makeGroup();
      teams.teams['g1'] = g;
      await teams.inviteToTeam(g, testUser.uid, testUser);
      final vm = teamsVm();
      await pumpEventQueue();

      await vm.declineInvite.execute(vm.invites.single);
      await pumpEventQueue();
      expect(vm.invites, isEmpty);
      expect(vm.all, isEmpty);
      vm.dispose();
    });
  });

  group('invite links', () {
    JoinLinkViewModel linkVm(String code) => JoinLinkViewModel(
      code: code,
      teamRepository: teams,
      authRepository: auth,
    );

    test('a link names a listed team and joins it', () async {
      final t = teamWith({'owner': TeamRole.owner});
      teams.teams['t1'] = t;
      teams.listings['t1'] = TeamListing.of(t);
      final vm = linkVm('CODEt1');
      await pumpEventQueue();
      expect(vm.loaded, isTrue);
      expect(vm.error, isNull);
      expect(vm.teamName, 'Team');
      expect(vm.alreadyMember, isFalse);

      await vm.join.execute();
      expect((vm.join.result as Ok<String>).value, 't1');
      await pumpEventQueue();
      expect(teams.teams['t1']!.roleOf(testUser.uid), TeamRole.player);
      expect(vm.alreadyMember, isTrue);
      vm.dispose();
    });

    test("members just open the team; old codes don't work", () async {
      teams.teams['t1'] = teamWith({
        'owner': TeamRole.owner,
        testUser.uid: TeamRole.player,
      });
      final member = linkVm('CODEt1');
      await pumpEventQueue();
      expect(member.alreadyMember, isTrue);
      expect(member.teamName, isNull, reason: 'unlisted: "a team"');
      await member.join.execute();
      expect((member.join.result as Ok<String>).value, 't1');
      member.dispose();

      final stale = linkVm('OLD123');
      await pumpEventQueue();
      expect(stale.loaded, isTrue);
      expect(stale.error, isNotNull);
      stale.dispose();
    });

    testWidgets('the link screen joins and opens the team', (tester) async {
      final t = teamWith({'owner': TeamRole.owner});
      teams.teams['t1'] = t;
      teams.listings['t1'] = TeamListing.of(t);
      final vm = linkVm('CODEt1');
      addTearDown(vm.dispose);
      final router = GoRouter(
        initialLocation: '/join/CODEt1',
        routes: [
          GoRoute(
            path: '/join/:code',
            builder: (_, _) => JoinLinkScreen(viewModel: vm),
          ),
          GoRoute(
            path: '/teams/:id',
            builder: (_, state) => Text('Team ${state.pathParameters['id']}'),
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      );
      await tester.pumpAndSettle();
      expect(find.text("You're invited to join Team"), findsOneWidget);

      await tester.tap(find.text('Join Team'));
      await tester.pumpAndSettle();
      expect(find.text('Team t1'), findsOneWidget);
    });

    testWidgets('a dead link says so', (tester) async {
      final vm = linkVm('NOPE12');
      addTearDown(vm.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: JoinLinkScreen(viewModel: vm),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text("This invite link doesn't work anymore"),
        findsOneWidget,
      );
    });
  });

  group('rotating invite code', () {
    InviteCodeViewModel codeVm() => InviteCodeViewModel(
      teamId: 't1',
      teamRepository: teams,
      authRepository: auth,
    );

    testWidgets('mints nothing until shown, then a new code every 30s', (
      tester,
    ) async {
      teams.teams['t1'] = teamWith({
        'owner': TeamRole.owner,
        testUser.uid: TeamRole.coach,
      });
      final vm = codeVm();
      addTearDown(vm.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: InviteCodeCard(viewModel: vm)),
        ),
      );
      expect(find.text('Show code'), findsOneWidget);
      expect(teams.inviteCodes, isEmpty);

      await tester.tap(find.text('Show code'));
      await tester.pump();
      final first = vm.code!;
      expect(find.text(first), findsOneWidget);
      expect(find.text('New code in 30s'), findsOneWidget);
      // Each code works a while past its turn on screen.
      expect(
        teams.inviteCodes[first]!.expiresAt.difference(DateTime.now()),
        greaterThan(const Duration(seconds: 40)),
      );

      await tester.pump(const Duration(seconds: 10));
      expect(find.text('New code in 20s'), findsOneWidget);
      await tester.pump(const Duration(seconds: 20));
      await tester.pump();
      final second = vm.code!;
      expect(second, isNot(first));
      expect(find.text(second), findsOneWidget);
      expect(find.text('New code in 30s'), findsOneWidget);

      await tester.tap(find.byTooltip('Hide code'));
      await tester.pump();
      expect(find.text('Show code'), findsOneWidget);
      await tester.pump(const Duration(minutes: 2));
      expect(teams.inviteCodes, hasLength(2), reason: 'hidden: no more codes');
    });

    testWidgets("a code that can't be made says why", (tester) async {
      teams.teams['t1'] = teamWith({testUser.uid: TeamRole.owner});
      teams.mintError = Exception('Not allowed');
      final vm = codeVm();
      addTearDown(vm.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: InviteCodeCard(viewModel: vm)),
        ),
      );
      await tester.tap(find.text('Show code'));
      await tester.pump();
      expect(vm.showing, isFalse);
      expect(find.text('Show code'), findsOneWidget);
      expect(find.textContaining('Not allowed'), findsOneWidget);
    });

    test('a community admin invites to its team without a link', () async {
      final people = FakeDirectMessageRepository()
        ..profiles.add(const UserProfile(uid: 'sam', name: 'Sam Lee'));
      final vm = InviteMembersViewModel(
        team: teamWith(const {'owner': TeamRole.owner}),
        teamRepository: teams,
        directMessageRepository: people,
        authRepository: auth,
        withLink: false,
        debounce: Duration.zero,
      );
      vm.search('sam');
      await pumpEventQueue();
      await vm.invite.execute(vm.results.single);
      expect(vm.invite.result, isA<Ok<void>>());
      expect(vm.link, isNull);
      expect(teams.invites['sam']!.single.teamId, vm.team.id);
      final dm = people.messages[Conversation.idFor(testUser.uid, 'sam')]!;
      expect(
        dm.single.text,
        'I invited you to join Team on Stall 10. Accept it from your Teams '
        'tab.',
      );
      vm.dispose();
    });

    test("inviting someone to a team sends a fresh link", () async {
      final t = teamWith({testUser.uid: TeamRole.owner});
      teams.teams['t1'] = t;
      final people = FakeDirectMessageRepository()
        ..profiles.add(const UserProfile(uid: 'sam', name: 'Sam Lee'));
      final vm = InviteMembersViewModel(
        team: t,
        teamRepository: teams,
        directMessageRepository: people,
        authRepository: auth,
        debounce: Duration.zero,
      )..setExpiry(InviteLinkExpiry.day);
      vm.search('sam');
      await pumpEventQueue();
      await vm.invite.execute(vm.results.single);
      final token = vm.link!.pathSegments.last;
      expect(teams.linkExpiries[token], InviteLinkExpiry.day);
      final dm = people.messages[Conversation.idFor(testUser.uid, 'sam')]!;
      expect(dm.single.text, 'Join Team on Stall 10: ${vm.link}');
      vm.dispose();
    });
  });
}
