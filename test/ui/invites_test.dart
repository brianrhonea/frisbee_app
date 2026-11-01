import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/direct_message.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/team_post.dart';
import 'package:frisbee_app/ui/teams/view_models/invite_members_viewmodel.dart';
import 'package:frisbee_app/ui/teams/view_models/team_home_viewmodel.dart';
import 'package:frisbee_app/ui/teams/view_models/teams_viewmodel.dart';

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

      await vm.invite.execute(vm.results.first);
      expect(vm.invite.completed, isTrue);
      expect(vm.wasInvited('sam'), isTrue);
      final sent = teams.invites['sam']!.single;
      expect(sent.teamName, 'Friends');
      expect(sent.isCommunity, isTrue);
      expect(sent.invitedByName, testUser.label);

      await vm.invite.execute(vm.results.last);
      expect(vm.invite.error, isTrue, reason: 'already a member');
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
}
