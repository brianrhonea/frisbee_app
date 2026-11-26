import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/schedule/schedule_settings_repository.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/schedule/view_models/schedule_viewmodel.dart';
import 'package:frisbee_app/ui/schedule/widgets/schedule_screen.dart';
import 'package:frisbee_app/ui/teams/view_models/community_teams_viewmodel.dart';
import 'package:frisbee_app/ui/teams/view_models/team_detail_viewmodel.dart';
import 'package:frisbee_app/ui/teams/widgets/community_teams_tab.dart';
import 'package:frisbee_app/ui/teams/widgets/members_tab.dart';

import '../testing/fakes.dart';
import '../ui_harness/harness.dart';

/// Layout regressions at 360 px wide, with the 48 px Material buttons: a
/// title or name must stay whole on one line, with nothing overflowing.
void main() {
  /// A 360 px phone with the real fonts (the default test font is far
  /// wider than Inter, which would make every row look cramped).
  Future<void> phone(WidgetTester tester) async {
    await loadAppFonts(tester);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Finder buttonFor(String label) => find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
  );

  /// [text] is on one line and isn't cut short with an ellipsis.
  void expectWholeLine(WidgetTester tester, String text) {
    final finder = find.text(text);
    expect(finder, findsOneWidget, reason: '"$text" is shown');
    final p = tester.renderObject<RenderParagraph>(finder);
    final lines = p.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: text.length),
    );
    expect(lines, hasLength(1), reason: '"$text" is on one line');
    expect(p.didExceedMaxLines, isFalse);
    expect(
      p.size.width + 0.5,
      greaterThanOrEqualTo(p.getMaxIntrinsicWidth(double.infinity)),
      reason: '"$text" is not truncated',
    );
  }

  testWidgets('Schedule keeps its title with Today and New event showing', (
    tester,
  ) async {
    await phone(tester);
    final semantics = tester.ensureSemantics();
    final teams = FakeTeamRepository();
    teams.teams['t1'] = teamWith({
      'owner': TeamRole.owner,
      testUser.uid: TeamRole.player,
    });
    final vm = ScheduleViewModel(
      authRepository: FakeAuthRepository(user: testUser),
      teamRepository: teams,
      eventRepository: FakeEventRepository(),
      settingsRepository: ScheduleSettingsRepositoryMemory(),
      clock: () => DateTime(2026, 11, 19, 9),
    );
    addTearDown(vm.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ScheduleScreen(
          viewModel: vm,
          // The shell's avatar, as on the Schedule tab.
          leading: const Padding(
            padding: EdgeInsets.all(8),
            child: CircleAvatar(child: Text('A')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Today'), findsNothing, reason: 'this week');

    await tester.tap(find.byTooltip('Next week'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Today'), findsOneWidget);
    // New event is an icon here, with its tooltip as its label.
    expect(find.byTooltip('New event'), findsOneWidget);
    final node = tester.getSemantics(find.byTooltip('New event'));
    expect('${node.label} ${node.tooltip}', contains('New event'));
    expect(tester.takeException(), isNull);
    expectWholeLine(tester, 'Schedule');
    // The Today button is still a 48 px target.
    expect(tester.getSize(find.byTooltip('Today')).height, 48);

    await tester.tap(find.byTooltip('Today'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Today'), findsNothing);
    semantics.dispose();
  });

  testWidgets('a join request keeps the name on one line', (tester) async {
    await phone(tester);
    final teams = FakeTeamRepository();
    final auth = FakeAuthRepository(user: testUser);
    final members = {'owner': TeamRole.owner, testUser.uid: TeamRole.captain};
    final group = Team(
      id: 'g1',
      name: 'Sunday Pickup',
      division: Division.mixed,
      level: CompetitionLevel.pickup,
      ownerId: 'owner',
      members: members,
      memberNames: {for (final uid in members.keys) uid: uid},
      kind: TeamKind.community,
      requiresApproval: true,
    );
    teams.teams['g1'] = group;
    teams.listings['g1'] = TeamListing.of(group);
    teams.joinRequests['g1'] = [
      const GroupJoinRequest(uid: 'a', name: 'Maya Kim'),
    ];
    final vm = TeamDetailViewModel(
      teamId: 'g1',
      teamRepository: teams,
      playRepository: FakePlayRepository(),
      eventRepository: FakeEventRepository(),
      authRepository: auth,
    );
    addTearDown(vm.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ListenableBuilder(
            listenable: vm,
            builder: (_, _) =>
                vm.team == null ? const SizedBox() : MembersTab(viewModel: vm),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 person wants to join'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expectWholeLine(tester, 'Maya Kim');
    for (final label in ['Decline', 'Approve']) {
      expect(tester.getSize(buttonFor(label)).height, greaterThanOrEqualTo(48));
    }
  });

  group('organization teams', () {
    Team org() => Team(
      id: 'org',
      name: 'Tech Ultimate',
      division: Division.mixed,
      level: CompetitionLevel.college,
      ownerId: testUser.uid,
      kind: TeamKind.organization,
      members: {testUser.uid: TeamRole.owner},
      memberNames: {testUser.uid: 'Test User'},
    );

    Future<CommunityTeamsViewModel> pumpTab(
      WidgetTester tester,
      FakeTeamRepository teams,
    ) async {
      await phone(tester);
      final vm = CommunityTeamsViewModel(
        orgId: 'org',
        teamRepository: teams,
        authRepository: FakeAuthRepository(user: testUser),
      );
      addTearDown(vm.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: CommunityTeamsTab(viewModel: vm)),
        ),
      );
      await tester.pumpAndSettle();
      return vm;
    }

    testWidgets('a team the user is on keeps its name beside the menu', (
      tester,
    ) async {
      final teams = FakeTeamRepository();
      teams.teams['org'] = org().copyWith(
        linkedTeams: const {'w': LinkedTeam(id: 'w', name: 'Northside Flyers')},
      );
      teams.teams['w'] = Team(
        id: 'w',
        name: 'Northside Flyers',
        division: Division.mixed,
        level: CompetitionLevel.club,
        ownerId: testUser.uid,
        members: {testUser.uid: TeamRole.owner},
        orgId: 'org',
      );
      final vm = await pumpTab(tester, teams);
      expect(vm.isOn(vm.teams.single), isTrue);
      expect(find.text("You're on it"), findsOneWidget);
      expect(find.byTooltip('Team options'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expectWholeLine(tester, 'Northside Flyers');
    });

    testWidgets('a team asking to join keeps its details on one line', (
      tester,
    ) async {
      final teams = FakeTeamRepository();
      teams.teams['org'] = org();
      teams.linkRequests['org'] = {
        'wl': const TeamLinkRequest(
          teamId: 'wl',
          teamName: 'Whiplash Women',
          division: Division.women,
          requestedBy: 'cap',
          requestedByName: 'Cap',
        ),
      };
      await pumpTab(tester, teams);
      expect(find.text('1 team wants to join'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expectWholeLine(tester, 'Whiplash Women');
      expectWholeLine(tester, "${Division.women.label} · asked by Cap");
      for (final label in ['Decline', 'Add']) {
        expect(
          tester.getSize(buttonFor(label)).height,
          greaterThanOrEqualTo(48),
        );
      }
    });
  });
}
