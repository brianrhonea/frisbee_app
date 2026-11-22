// The "Public team page" switch (redesign F12): admins turn it off in team
// Settings › Visibility; then people outside the team see only its card.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/data/repositories/team/team_hints_repository.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/team_event.dart';
import 'package:frisbee_app/ui/teams/view_models/team_home_viewmodel.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/teams/view_models/team_settings_viewmodel.dart';
import 'package:frisbee_app/ui/teams/widgets/team_settings_screen.dart';

import '../testing/fakes.dart';

void main() {
  group('the stored switch', () {
    test('a team is public unless it says false', () {
      expect(Team.fromMap('t1', {'name': 'Old'}).publicPage, isTrue);
      expect(
        Team.fromMap('t1', {'name': 'Off', 'publicPage': false}).publicPage,
        isFalse,
      );
    });

    test('the listing carries it only when off, as the API writes it', () {
      final team = teamWith({'o': TeamRole.owner});
      expect(TeamListing.of(team).toMap(), isNot(contains('publicPage')));
      final off = TeamListing.of(team.copyWith(publicPage: false));
      expect(off.toMap()['publicPage'], isFalse);
      expect(
        TeamListing.fromMap('t1', off.toMap()).publicPage,
        isFalse,
        reason: 'read back from the directory',
      );
    });

    test('a listing out of step is republished', () {
      final team = teamWith({'o': TeamRole.owner});
      expect(TeamListing.of(team).sameAs(team), isTrue);
      expect(
        TeamListing.of(team).sameAs(team.copyWith(publicPage: false)),
        isFalse,
      );
    });

    test("outsiders see only the card of a team whose page is off, "
        "as a private group's", () {
      final team = teamWith({'o': TeamRole.owner});
      expect(TeamListing.of(team).hidesPage, isFalse);
      expect(
        TeamListing.of(team.copyWith(publicPage: false)).hidesPage,
        isTrue,
      );
      expect(
        TeamListing.of(team.copyWith(requiresApproval: true)).hidesPage,
        isFalse,
        reason: "a team's approval doesn't make it private",
      );
    });
  });

  group("an outsider's view of the team page", () {
    final now = DateTime(2026, 11, 20, 12);

    Future<TeamHomeViewModel> outsider({required bool publicPage}) async {
      final teams = FakeTeamRepository();
      final events = FakeEventRepository();
      final team = teamWith({'o': TeamRole.owner});
      // Only the listing: the rules keep the team doc to members.
      teams.listings['t1'] = TeamListing.of(
        team.copyWith(publicPage: publicPage),
      );
      events.events['e1'] = TeamEvent(
        id: 'e1',
        title: 'Open tryouts',
        startsAt: now.add(const Duration(days: 2)),
        isPublic: true,
      );
      final vm = TeamHomeViewModel(
        teamId: 't1',
        teamRepository: teams,
        eventRepository: events,
        teamPostRepository: FakeTeamPostRepository(),
        authRepository: FakeAuthRepository(user: testUser),
        filePicker: FakeFilePickerService(),
        hints: TeamHintsRepositoryMemory(),
        clock: () => now,
      );
      addTearDown(vm.dispose);
      await pumpEventQueue();
      return vm;
    }

    test('sees its public events while the page is on', () async {
      final vm = await outsider(publicPage: true);
      expect(vm.isPrivateToMe, isFalse);
      expect(vm.upcomingEvents.map((e) => e.title), ['Open tryouts']);
    });

    test('sees only its card while the page is off: no events or posts '
        'are read', () async {
      final vm = await outsider(publicPage: false);
      expect(vm.isPrivateToMe, isTrue);
      expect(vm.upcomingEvents, isEmpty);
      expect(vm.posts, isEmpty);
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

    SwitchListTile tile(WidgetTester tester) => tester.widget<SwitchListTile>(
      find.byKey(const ValueKey('public-page')),
    );

    testWidgets('an admin turns the public page off, and back on', (
      tester,
    ) async {
      teams.teams['t1'] = teamWith({
        'o': TeamRole.owner,
        'coach': TeamRole.coach,
      });
      final vm = await pump(tester, uid: 'coach');
      expect(find.text('VISIBILITY'), findsOneWidget);
      expect(find.text('Public team page'), findsOneWidget);
      expect(find.text(publicPageDescription), findsOneWidget);
      expect(tile(tester).value, isTrue);
      expect(vm.canManage, isTrue);

      await tester.tap(find.byKey(const ValueKey('public-page')));
      await tester.pumpAndSettle();
      expect(teams.publicPageChanges, [false]);
      expect(teams.teams['t1']!.publicPage, isFalse);
      expect(tile(tester).value, isFalse);

      await tester.tap(find.byKey(const ValueKey('public-page')));
      await tester.pumpAndSettle();
      expect(teams.publicPageChanges, [false, true]);
      expect(tile(tester).value, isTrue);
    });

    testWidgets('a player sees it but can not change it', (tester) async {
      teams.teams['t1'] = teamWith({
        'o': TeamRole.owner,
        'p': TeamRole.player,
      }).copyWith(publicPage: false);
      await pump(tester, uid: 'p');
      expect(tile(tester).value, isFalse);
      expect(tile(tester).onChanged, isNull);
      expect(
        find.text("Only the team's admins can change this."),
        findsOneWidget,
      );
    });

    testWidgets('a community has no switch: it approves who joins instead', (
      tester,
    ) async {
      teams.teams['t1'] = Team(
        id: 't1',
        name: 'Pickup',
        division: Division.mixed,
        level: CompetitionLevel.pickup,
        ownerId: 'o',
        members: const {'o': TeamRole.owner},
        kind: TeamKind.community,
      );
      await pump(tester, uid: 'o');
      expect(find.byKey(const ValueKey('public-page')), findsNothing);
    });
  });
}
