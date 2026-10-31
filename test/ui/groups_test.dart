import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/team_event.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/groups/widgets/group_map.dart';
import 'package:frisbee_app/ui/teams/view_models/team_detail_viewmodel.dart';
import 'package:frisbee_app/ui/teams/view_models/team_home_viewmodel.dart';
import 'package:frisbee_app/ui/teams/view_models/team_search_viewmodel.dart';
import 'package:frisbee_app/ui/teams/view_models/teams_viewmodel.dart';
import 'package:frisbee_app/ui/teams/widgets/members_tab.dart';
import 'package:frisbee_app/ui/teams/widgets/team_home_screen.dart';
import 'package:frisbee_app/ui/teams/widgets/team_section_screen.dart';

import '../testing/fakes.dart';

void main() {
  late FakeTeamRepository teams;
  late FakeAuthRepository auth;

  const location = GroupLocation(
    address: 'City Park, Denver',
    latitude: 39.75,
    longitude: -104.95,
  );

  setUp(() {
    debugDisableMapTiles = true;
    teams = FakeTeamRepository();
    auth = FakeAuthRepository(user: testUser);
  });

  tearDown(() => debugDisableMapTiles = false);

  Team makeGroup({
    Map<String, TeamRole> members = const {'owner': TeamRole.owner},
    bool requiresApproval = false,
    GroupLocation? location,
  }) => Team(
    id: 'g1',
    name: 'Sunday Pickup',
    division: Division.mixed,
    level: CompetitionLevel.pickup,
    city: 'Denver',
    ownerId: 'owner',
    members: members,
    memberNames: {for (final uid in members.keys) uid: uid},
    kind: TeamKind.community,
    description: 'Every Sunday at 10.',
    requiresApproval: requiresApproval,
    location: location,
  );

  void addGroup(Team g) {
    teams.teams[g.id] = g;
    teams.listings[g.id] = TeamListing.of(g);
  }

  TeamHomeViewModel homeVm() => TeamHomeViewModel(
    teamId: 'g1',
    teamRepository: teams,
    eventRepository: FakeEventRepository(),
    teamPostRepository: FakeTeamPostRepository(),
    authRepository: auth,
    filePicker: FakeFilePickerService(),
  );

  group('models', () {
    test('groups round-trip their fields; teams store none', () {
      final g = makeGroup(requiresApproval: true, location: location);
      final listing = TeamListing.of(g);
      final map = listing.toMap();
      expect(map['kind'], 'community');
      expect(map['location'], {
        'address': 'City Park, Denver',
        'lat': 39.75,
        'lng': -104.95,
      });
      final back = TeamListing.fromMap('g1', map);
      expect(back.sameAs(g), isTrue);
      expect(back.subtitle, 'Community group · Denver');

      expect(g.toEditableMap().containsKey('kind'), isFalse);
      expect(g.toEditableMap()['requiresApproval'], isTrue);

      final team = teamWith({'owner': TeamRole.owner});
      expect(team.toEditableMap().keys, ['name', 'division', 'level', 'city']);
      expect(TeamListing.of(team).toMap().containsKey('kind'), isFalse);
    });

    test('group roles are owner, organizer and member', () {
      expect(TeamRole.rolesFor(TeamKind.community), [
        TeamRole.owner,
        TeamRole.captain,
        TeamRole.player,
      ]);
      expect(TeamRole.captain.labelFor(TeamKind.community), 'Organizer');
      expect(TeamRole.player.labelFor(TeamKind.community), 'Member');
      expect(TeamRole.captain.labelFor(TeamKind.team), 'Captain');
    });

    test('groups schedule pickup; tournaments ask who is attending', () {
      expect(
        EventType.editableFor(community: true),
        contains(EventType.pickup),
      );
      expect(
        EventType.editableFor(community: true),
        isNot(contains(EventType.practice)),
      );
      expect(
        EventType.editableFor(community: false),
        isNot(contains(EventType.pickup)),
      );
      expect(RsvpStatus.going.labelFor(EventType.tournament), 'Attending');
      expect(
        RsvpStatus.maybe.labelFor(EventType.tournament),
        'Planning to attend',
      );
      expect(
        RsvpStatus.notGoing.labelFor(EventType.tournament),
        'Not able to make it :(',
      );
      expect(RsvpStatus.going.labelFor(EventType.pickup), 'Going');
    });
  });

  group('joining', () {
    test('anyone joins an open group', () async {
      addGroup(makeGroup());
      final vm = homeVm();
      await pumpEventQueue();
      expect(vm.isMember, isFalse);
      expect(vm.isGroup, isTrue);

      await vm.joinGroup.execute();
      await pumpEventQueue();
      expect(vm.joinGroup.completed, isTrue);
      expect(vm.isMember, isTrue);
      expect(vm.myRole, TeamRole.player);
      vm.dispose();
    });

    test('approval groups take a request, which can be withdrawn', () async {
      addGroup(makeGroup(requiresApproval: true));
      final vm = homeVm();
      await pumpEventQueue();

      await vm.joinGroup.execute();
      await pumpEventQueue();
      expect(vm.isMember, isFalse);
      expect(vm.requestPending, isTrue);
      expect(teams.joinRequests['g1']!.single.name, testUser.label);

      await vm.cancelJoinRequest.execute();
      await pumpEventQueue();
      expect(vm.requestPending, isFalse);
      vm.dispose();
    });

    test('organizers approve and decline requests', () async {
      addGroup(
        makeGroup(
          requiresApproval: true,
          members: {'owner': TeamRole.owner, testUser.uid: TeamRole.captain},
        ),
      );
      teams.joinRequests['g1'] = [
        const GroupJoinRequest(uid: 'a', name: 'Ann'),
        const GroupJoinRequest(uid: 'b', name: 'Bo'),
      ];
      final vm = TeamDetailViewModel(
        teamId: 'g1',
        teamRepository: teams,
        playRepository: FakePlayRepository(),
        eventRepository: FakeEventRepository(),
        authRepository: auth,
      );
      await pumpEventQueue();
      expect(vm.joinRequests.map((r) => r.name), ['Ann', 'Bo']);
      // Groups have no invite code.
      expect(teams.inviteWatches, isEmpty);

      await vm.approveJoinRequest.execute(vm.joinRequests.first);
      await vm.declineJoinRequest.execute('b');
      await pumpEventQueue();
      expect(vm.joinRequests, isEmpty);
      expect(vm.team!.roleOf('a'), TeamRole.player);
      expect(vm.team!.roleOf('b'), isNull);
      vm.dispose();
    });

    test('members see no requests', () async {
      addGroup(
        makeGroup(
          requiresApproval: true,
          members: {'owner': TeamRole.owner, testUser.uid: TeamRole.player},
        ),
      );
      teams.joinRequests['g1'] = [const GroupJoinRequest(uid: 'a', name: 'A')];
      final vm = TeamDetailViewModel(
        teamId: 'g1',
        teamRepository: teams,
        playRepository: FakePlayRepository(),
        eventRepository: FakeEventRepository(),
        authRepository: auth,
      );
      await pumpEventQueue();
      expect(vm.joinRequests, isEmpty);
      vm.dispose();
    });
  });

  group('lists and search', () {
    test('my teams and groups are listed apart', () async {
      teams.teams['t1'] = teamWith({
        'owner': TeamRole.owner,
        testUser.uid: TeamRole.player,
      });
      addGroup(
        makeGroup(
          members: {'owner': TeamRole.owner, testUser.uid: TeamRole.player},
        ),
      );
      final vm = TeamsViewModel(teamRepository: teams, authRepository: auth);
      await pumpEventQueue();
      expect(vm.teams.map((t) => t.id), ['t1']);
      expect(vm.groups.map((t) => t.id), ['g1']);
      vm.dispose();
    });

    test('search filters teams and groups', () async {
      final team = teamWith({'owner': TeamRole.owner});
      teams.listings['t1'] = TeamListing.of(
        Team(
          id: 't1',
          name: 'Sunday Cutters',
          division: team.division,
          level: team.level,
          ownerId: 'owner',
          members: team.members,
        ),
      );
      addGroup(makeGroup());
      final vm = TeamSearchViewModel(
        teamRepository: teams,
        authRepository: auth,
      );
      await vm.search.execute('sunday');
      expect(vm.results.length, 2);
      vm.setKind(TeamKind.community);
      expect(vm.results.single.name, 'Sunday Pickup');
      vm.setKind(TeamKind.team);
      expect(vm.results.single.name, 'Sunday Cutters');
      vm.dispose();
    });
  });

  group('screens', () {
    Future<void> pumpHome(WidgetTester tester, TeamHomeViewModel vm) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: TeamHomeScreen(viewModel: vm),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('outsiders see the description, map and Join', (tester) async {
      addGroup(makeGroup(location: location));
      await pumpHome(tester, homeVm());

      expect(find.text('Every Sunday at 10.'), findsOneWidget);
      expect(find.byType(GroupMapCard), findsOneWidget);
      expect(find.text('City Park, Denver'), findsOneWidget);
      expect(find.text('Join'), findsOneWidget);

      await tester.tap(find.text('Join'));
      await tester.pumpAndSettle();
      // Now a member: the group's sections, without the team-only ones.
      expect(find.text('Events'), findsOneWidget);
      expect(find.text('Chat'), findsOneWidget);
      expect(find.text('Members'), findsOneWidget);
      for (final s in [
        TeamSection.roster,
        TeamSection.playbook,
        TeamSection.videos,
        TeamSection.stats,
      ]) {
        expect(find.text(s.label), findsNothing);
      }
      expect(find.text('You: Member · 2 members'), findsOneWidget);
    });

    testWidgets('approval groups show Ask to join, then pending', (
      tester,
    ) async {
      addGroup(makeGroup(requiresApproval: true));
      await pumpHome(tester, homeVm());

      expect(find.byType(GroupMapCard), findsNothing);
      await tester.tap(find.text('Ask to join'));
      await tester.pumpAndSettle();
      expect(find.text('Cancel request'), findsOneWidget);
      expect(find.textContaining('Request sent'), findsOneWidget);
    });

    testWidgets('organizers approve requests on the members page', (
      tester,
    ) async {
      addGroup(
        makeGroup(
          requiresApproval: true,
          members: {'owner': TeamRole.owner, testUser.uid: TeamRole.captain},
        ),
      );
      teams.joinRequests['g1'] = [
        const GroupJoinRequest(uid: 'a', name: 'Ann'),
      ];
      final vm = TeamDetailViewModel(
        teamId: 'g1',
        teamRepository: teams,
        playRepository: FakePlayRepository(),
        eventRepository: FakeEventRepository(),
        authRepository: auth,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: ListenableBuilder(
              listenable: vm,
              builder: (_, _) => vm.team == null
                  ? const SizedBox()
                  : MembersTab(viewModel: vm),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 person wants to join'), findsOneWidget);
      expect(find.text('Organizer'), findsWidgets);
      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();
      expect(find.text('1 person wants to join'), findsNothing);
      expect(find.text('Ann'), findsOneWidget);
      expect(find.text('Member'), findsOneWidget);
    });
  });
}
