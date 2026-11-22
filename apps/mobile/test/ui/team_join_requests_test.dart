// Team join requests (redesign F26): admins turn on "Allow join requests"
// in team Settings › Visibility; signed-in outsiders then get "Request to
// join" on the team's page, and member managers approve or decline in the
// Members tab. The website's TeamNav/TeamSettings tests say the same.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/team/team_hints_repository.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/teams/view_models/team_detail_viewmodel.dart';
import 'package:frisbee_app/ui/teams/view_models/team_home_viewmodel.dart';
import 'package:frisbee_app/ui/teams/view_models/team_settings_viewmodel.dart';
import 'package:frisbee_app/ui/teams/widgets/team_settings_screen.dart';

import '../testing/fakes.dart';

void main() {
  group('the stored switch', () {
    test('off unless stored as true', () {
      expect(Team.fromMap('t1', {'name': 'Old'}).allowJoinRequests, isFalse);
      expect(
        Team.fromMap('t1', {
          'name': 'On',
          'allowJoinRequests': true,
        }).allowJoinRequests,
        isTrue,
      );
    });

    test('the listing carries it only when on, as the API writes it', () {
      final team = teamWith({'o': TeamRole.owner});
      expect(
        TeamListing.of(team).toMap(),
        isNot(contains('allowJoinRequests')),
      );
      expect(TeamListing.of(team).takesRequests, isFalse);
      final on = TeamListing.of(team.copyWith(allowJoinRequests: true));
      expect(on.toMap()['allowJoinRequests'], isTrue);
      expect(TeamListing.fromMap('t1', on.toMap()).takesRequests, isTrue);
      expect(
        TeamListing.of(team).sameAs(team.copyWith(allowJoinRequests: true)),
        isFalse,
        reason: 'a listing out of step is republished',
      );
    });

    test("a league's team never takes requests", () {
      final team = Team(
        id: 't1',
        name: 'Drafted',
        division: Division.mixed,
        level: CompetitionLevel.league,
        ownerId: 'o',
        members: const {'o': TeamRole.owner},
        leagueId: 'l1',
        allowJoinRequests: true,
      );
      expect(TeamListing.of(team).takesRequests, isFalse);
    });
  });

  group("an outsider's view of a team page", () {
    Future<(TeamHomeViewModel, FakeTeamRepository)> outsider({
      required bool requests,
    }) async {
      final teams = FakeTeamRepository();
      teams.listings['t1'] = TeamListing.of(
        teamWith({'o': TeamRole.owner}).copyWith(allowJoinRequests: requests),
      );
      final vm = TeamHomeViewModel(
        teamId: 't1',
        teamRepository: teams,
        eventRepository: FakeEventRepository(),
        teamPostRepository: FakeTeamPostRepository(),
        authRepository: FakeAuthRepository(user: testUser),
        filePicker: FakeFilePickerService(),
        hints: TeamHintsRepositoryMemory(),
      );
      addTearDown(vm.dispose);
      await pumpEventQueue();
      return (vm, teams);
    }

    test('asks to join a team that takes requests, then cancels', () async {
      final (vm, teams) = await outsider(requests: true);
      expect(vm.requestPending, isFalse);
      await vm.joinGroup.execute();
      await pumpEventQueue();
      expect(teams.joinRequests['t1']!.single.uid, testUser.uid);
      expect(vm.requestPending, isTrue);
      expect(vm.isMember, isFalse, reason: 'an admin still has to approve');

      await vm.cancelJoinRequest.execute();
      await pumpEventQueue();
      expect(teams.joinRequests['t1'], isEmpty);
      expect(vm.requestPending, isFalse);
    });

    test(
      'a team that takes members by invite only refuses a request',
      () async {
        final (vm, teams) = await outsider(requests: false);
        await vm.joinGroup.execute();
        expect(vm.joinGroup.error, isTrue);
        expect(teams.joinRequests['t1'], isNull);
      },
    );
  });

  group('the Members tab', () {
    Future<TeamDetailViewModel> detail(Team team, String uid) async {
      final teams = FakeTeamRepository();
      teams.teams['t1'] = team;
      teams.joinRequests['t1'] = [
        const GroupJoinRequest(uid: 'ann', name: 'Ann'),
      ];
      final vm = TeamDetailViewModel(
        teamId: 't1',
        teamRepository: teams,
        playRepository: FakePlayRepository(),
        eventRepository: FakeEventRepository(),
        authRepository: FakeAuthRepository(
          user: AppUser(uid: uid, email: '$uid@x.test', displayName: uid),
        ),
      );
      addTearDown(vm.dispose);
      await pumpEventQueue();
      return vm;
    }

    final team = teamWith({
      'o': TeamRole.owner,
      'coach': TeamRole.coach,
      'p': TeamRole.player,
    });

    test(
      'member managers see the requests while the team takes them',
      () async {
        final vm = await detail(
          team.copyWith(allowJoinRequests: true),
          'coach',
        );
        expect(vm.joinRequests.map((r) => r.name), ['Ann']);
      },
    );

    test('nobody watches them while the switch is off', () async {
      final vm = await detail(team, 'coach');
      expect(vm.joinRequests, isEmpty);
    });

    test('players never see them', () async {
      final vm = await detail(team.copyWith(allowJoinRequests: true), 'p');
      expect(vm.joinRequests, isEmpty);
    });
  });

  group('Settings › Visibility', () {
    late FakeTeamRepository teams;

    setUp(() => teams = FakeTeamRepository());

    Future<TeamSettingsViewModel> pump(
      WidgetTester tester, {
      required String uid,
    }) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final vm = TeamSettingsViewModel(
        teamId: 't1',
        teamRepository: teams,
        authRepository: FakeAuthRepository(
          user: AppUser(uid: uid, email: '$uid@x.test', displayName: uid),
        ),
      );
      addTearDown(vm.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: TeamSettingsScreen(viewModel: vm),
        ),
      );
      await tester.pumpAndSettle();
      return vm;
    }

    const key = ValueKey('allow-join-requests');
    SwitchListTile tile(WidgetTester tester) =>
        tester.widget<SwitchListTile>(find.byKey(key));

    testWidgets('an admin turns requests on; off asks first', (tester) async {
      teams.teams['t1'] = teamWith({
        'o': TeamRole.owner,
        'coach': TeamRole.coach,
      });
      await pump(tester, uid: 'coach');
      expect(find.text('Allow join requests'), findsOneWidget);
      expect(find.text(allowJoinRequestsDescription), findsOneWidget);
      expect(tile(tester).value, isFalse, reason: 'off by default');

      await tester.tap(find.byKey(key));
      await tester.pumpAndSettle();
      expect(teams.allowJoinRequestsChanges, [true]);
      expect(tile(tester).value, isTrue);

      await tester.tap(find.byKey(key));
      await tester.pumpAndSettle();
      expect(find.text('Stop taking join requests?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(teams.allowJoinRequestsChanges, [true]);

      await tester.tap(find.byKey(key));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Turn off'));
      await tester.pumpAndSettle();
      expect(teams.allowJoinRequestsChanges, [true, false]);
      expect(tile(tester).value, isFalse);
    });

    testWidgets('a player sees it but can not change it', (tester) async {
      teams.teams['t1'] = teamWith({
        'o': TeamRole.owner,
        'p': TeamRole.player,
      }).copyWith(allowJoinRequests: true);
      await pump(tester, uid: 'p');
      expect(tile(tester).value, isTrue);
      expect(tile(tester).onChanged, isNull);
    });

    testWidgets("a league's team has no switch", (tester) async {
      teams.teams['t1'] = Team(
        id: 't1',
        name: 'Drafted',
        division: Division.mixed,
        level: CompetitionLevel.league,
        ownerId: 'o',
        members: const {'o': TeamRole.owner},
        leagueId: 'l1',
      );
      await pump(tester, uid: 'o');
      expect(find.byKey(key), findsNothing);
    });
  });
}
