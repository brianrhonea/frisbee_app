// H4: the Teams tab with list rows and role pills. Parity: website teams
// page.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/auth/auth_repository.dart';
import 'package:frisbee_app/data/repositories/team/team_repository.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/ui/core/ui/list_row.dart';
import 'package:frisbee_app/ui/core/ui/status_pill.dart';
import 'package:frisbee_app/ui/teams/view_models/teams_viewmodel.dart';
import 'package:frisbee_app/ui/teams/widgets/teams_screen.dart';
import 'package:provider/provider.dart';

import '../testing/fakes.dart';
import '../ui_harness/harness.dart';

void main() {
  late FakeTeamRepository teams;
  late FakeAuthRepository auth;

  setUp(() {
    teams = FakeTeamRepository();
    auth = FakeAuthRepository(user: testUser);
    final a = teamWith({testUser.uid: TeamRole.owner, 'x': TeamRole.player});
    final b = Team(
      id: 't2',
      name: 'Quiet Pickup',
      division: Division.mixed,
      level: CompetitionLevel.pickup,
      ownerId: 'someone',
      members: {'someone': TeamRole.owner, testUser.uid: TeamRole.player},
    );
    for (final t in [a, b]) {
      teams.teams[t.id] = t;
      teams.listings[t.id] = TeamListing.of(t);
    }
  });

  Widget screen() {
    final vm = TeamsViewModel(teamRepository: teams, authRepository: auth);
    addTearDown(vm.dispose);
    return MultiProvider(
      providers: [
        Provider<TeamRepository>.value(value: teams),
        ChangeNotifierProvider<AuthRepository>.value(value: auth),
      ],
      child: TeamsScreen(viewModel: vm),
    );
  }

  testWidgets('your teams are list rows with a role pill', (tester) async {
    await pumpInApp(tester, screen(), width: 390, height: 800);
    await tester.pumpAndSettle();
    expect(find.text('Your teams'), findsOneWidget);
    expect(find.byType(ListRow), findsNWidgets(2));
    expect(find.text('Quiet Pickup'), findsOneWidget);
    expect(find.widgetWithText(StatusPill, 'Owner'), findsOneWidget);
    expect(find.widgetWithText(StatusPill, 'Player'), findsOneWidget);
  });

  testWidgets('the subtitle stays on one line beside the role pill', (
    tester,
  ) async {
    await pumpInApp(tester, screen(), width: 360, height: 800);
    await tester.pumpAndSettle();
    final subtitle = tester.widget<Text>(find.textContaining('Mixed · Club'));
    expect(subtitle.maxLines, 1);
    expect(subtitle.overflow, TextOverflow.ellipsis);
  });

  for (final theme in GoldenTheme.values) {
    testWidgets('meets accessibility guidelines, ${theme.name}', (
      tester,
    ) async {
      await pumpInApp(tester, screen(), theme: theme, width: 390, height: 800);
      await tester.pumpAndSettle();
      await expectAccessible(tester);
    });
  }

  testWidgets('fits at text scale 2.0', (tester) async {
    await expectNoOverflowWithLargeText(
      tester,
      screen(),
      width: 390,
      height: 800,
    );
  });

  testWidgets(
    'goldens at phone and tablet widths, light and dark',
    skip: goldenSkip != null,
    (tester) async {
      await expectGoldens(
        tester,
        screen(),
        'teams_h4',
        widths: const [GoldenWidth.phone, GoldenWidth.tablet],
        height: 800,
      );
    },
  );
}
