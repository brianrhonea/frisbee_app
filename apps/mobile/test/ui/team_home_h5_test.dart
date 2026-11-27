// H5: the team page with a cover and logo, event cards, a face stack of
// members and no boxes round the sections. Parity: website team page.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/auth/auth_repository.dart';
import 'package:frisbee_app/data/repositories/team/team_repository.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/team_event.dart';
import 'package:frisbee_app/ui/core/ui/avatar.dart';
import 'package:frisbee_app/ui/core/ui/cover_header.dart';
import 'package:frisbee_app/ui/core/ui/event_card.dart';
import 'package:frisbee_app/ui/teams/view_models/team_home_viewmodel.dart';
import 'package:frisbee_app/ui/teams/widgets/team_home_screen.dart';
import 'package:provider/provider.dart';

import '../testing/fakes.dart';
import '../ui_harness/harness.dart';

void main() {
  final now = DateTime(2026, 10, 30, 12);
  late FakeTeamRepository teams;
  late FakeEventRepository events;
  late FakeAuthRepository auth;

  setUp(() {
    teams = FakeTeamRepository();
    events = FakeEventRepository();
    for (var i = 1; i <= 3; i++) {
      events.events['e$i'] = TeamEvent(
        id: 'e$i',
        title: 'Practice $i',
        startsAt: now.add(Duration(days: i)),
      );
    }
    auth = FakeAuthRepository(user: testUser);
    final team = teamWith({
      'owner': TeamRole.owner,
      'a': TeamRole.player,
      testUser.uid: TeamRole.player,
    });
    teams.teams[team.id] = team;
    teams.listings[team.id] = TeamListing.of(team);
  });

  Widget screen() {
    final vm = TeamHomeViewModel(
      teamId: 't1',
      teamRepository: teams,
      eventRepository: events,
      teamPostRepository: FakeTeamPostRepository(),
      authRepository: auth,
      filePicker: FakeFilePickerService(),
      chatRepository: FakeChatRepository(),
      clock: () => now,
    );
    addTearDown(vm.dispose);
    return MultiProvider(
      providers: [
        Provider<TeamRepository>.value(value: teams),
        ChangeNotifierProvider<AuthRepository>.value(value: auth),
      ],
      child: TeamHomeScreen(viewModel: vm),
    );
  }

  testWidgets('wide: cover with the logo, tabs, event cards and a face stack', (
    tester,
  ) async {
    await pumpInApp(tester, screen(), width: 900, height: 1400);
    await tester.pumpAndSettle();
    expect(find.byType(CoverHeader), findsOneWidget);
    for (final tab in ['Feed', 'Schedule', 'Chat', 'Roster']) {
      expect(find.text(tab), findsWidgets, reason: tab);
    }
    expect(find.byType(EventCard), findsWidgets);
    expect(find.byType(AvatarStack), findsOneWidget);
    expect(find.text('Coming up'), findsOneWidget);
  });

  for (final theme in GoldenTheme.values) {
    testWidgets('wide meets accessibility guidelines, ${theme.name}', (
      tester,
    ) async {
      await pumpInApp(tester, screen(), theme: theme, width: 900, height: 1400);
      await tester.pumpAndSettle();
      await expectAccessible(tester);
    });

    testWidgets('phone meets accessibility guidelines, ${theme.name}', (
      tester,
    ) async {
      await pumpInApp(tester, screen(), theme: theme, width: 390, height: 844);
      await tester.pumpAndSettle();
      await expectAccessible(tester);
    });
  }

  testWidgets('phone fits at text scale 2.0', (tester) async {
    await expectNoOverflowWithLargeText(
      tester,
      screen(),
      width: 390,
      height: 844,
    );
  });

  testWidgets('wide fits at text scale 2.0', (tester) async {
    await expectNoOverflowWithLargeText(
      tester,
      screen(),
      width: 900,
      height: 1400,
    );
  });

  testWidgets(
    'goldens at phone and tablet widths, light and dark',
    skip: goldenSkip != null,
    (tester) async {
      await expectGoldens(
        tester,
        screen(),
        'team_home_h5',
        widths: const [GoldenWidth.phone, GoldenWidth.tablet],
        height: 1000,
      );
    },
  );
}
