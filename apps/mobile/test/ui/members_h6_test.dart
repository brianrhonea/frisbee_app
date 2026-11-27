// H6: the roster's Members list with role pills, and the Roles screen on
// the shared type scale. Parity: website roster page.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/auth/auth_repository.dart';
import 'package:frisbee_app/data/repositories/team/team_repository.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/ui/core/ui/status_pill.dart';
import 'package:frisbee_app/ui/teams/view_models/team_detail_viewmodel.dart';
import 'package:frisbee_app/ui/teams/widgets/members_tab.dart';
import 'package:provider/provider.dart';

import '../testing/fakes.dart';
import '../ui_harness/harness.dart';

void main() {
  final now = DateTime(2026, 10, 30, 12);
  late FakeTeamRepository teams;
  late FakeAuthRepository auth;

  setUp(() {
    teams = FakeTeamRepository();
    auth = FakeAuthRepository(user: testUser);
    final team = teamWith({
      testUser.uid: TeamRole.owner,
      'c1': TeamRole.captain,
      'p1': TeamRole.player,
      'p2': TeamRole.player,
    });
    teams.teams[team.id] = team;
    teams.listings[team.id] = TeamListing.of(team);
  });

  Widget screen() {
    final vm = TeamDetailViewModel(
      teamId: 't1',
      teamRepository: teams,
      playRepository: FakePlayRepository(),
      eventRepository: FakeEventRepository(),
      authRepository: auth,
      clock: () => now,
    );
    addTearDown(vm.dispose);
    return MultiProvider(
      providers: [
        Provider<TeamRepository>.value(value: teams),
        ChangeNotifierProvider<AuthRepository>.value(value: auth),
      ],
      child: Scaffold(body: MembersTab(viewModel: vm)),
    );
  }

  testWidgets('lists members with their role pills and the member count', (
    tester,
  ) async {
    await pumpInApp(tester, screen(), width: 390, height: 900);
    await tester.pumpAndSettle();
    expect(find.text('4 MEMBERS'), findsOneWidget);
    expect(find.byType(StatusPill), findsWidgets);
    expect(find.text('(you)', findRichText: true), findsNothing);
    expect(find.textContaining('(you)', findRichText: true), findsOneWidget);
  });

  for (final theme in GoldenTheme.values) {
    testWidgets('meets accessibility guidelines, ${theme.name}', (
      tester,
    ) async {
      await pumpInApp(tester, screen(), theme: theme, width: 390, height: 900);
      await tester.pumpAndSettle();
      await expectAccessible(tester);
    });
  }

  testWidgets('fits at text scale 2.0', (tester) async {
    await expectNoOverflowWithLargeText(
      tester,
      screen(),
      width: 390,
      height: 900,
    );
  });

  testWidgets(
    'goldens at phone and tablet widths, light and dark',
    skip: goldenSkip != null,
    (tester) async {
      await expectGoldens(
        tester,
        screen(),
        'members_h6',
        widths: const [GoldenWidth.phone, GoldenWidth.tablet],
        height: 900,
      );
    },
  );
}
