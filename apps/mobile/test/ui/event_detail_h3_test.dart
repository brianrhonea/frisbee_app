import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/team_event.dart';
import 'package:frisbee_app/ui/core/ui/cover_header.dart';
import 'package:frisbee_app/ui/core/ui/layout.dart' show DateBadge;
import 'package:frisbee_app/ui/schedule/view_models/event_detail_viewmodel.dart';
import 'package:frisbee_app/ui/schedule/widgets/event_detail_screen.dart';

import '../testing/fakes.dart';
import '../testing/group_tournament_fakes.dart';
import '../ui_harness/harness.dart';

/// H3: an event's page with a cover, Going / Maybe / Not going and the
/// attendee count. Parity: website event page.
void main() {
  late FakeTeamRepository teams;
  late FakeEventRepository events;

  setUp(() {
    teams = FakeTeamRepository();
    events = FakeEventRepository();
    teams.teams['t1'] = teamWith({
      'owner': TeamRole.owner,
      'p2': TeamRole.player,
      testUser.uid: TeamRole.player,
    });
    events.events['e1'] = TeamEvent(
      id: 'e1',
      title: 'Thursday practice',
      startsAt: DateTime(2026, 12, 3, 18),
      location: 'Riverside Field 2',
      notes: 'Bring both jerseys.',
      rsvps: {'p2': RsvpStatus.going},
    );
  });

  Widget screen() {
    final vm = EventDetailViewModel(
      teamId: 't1',
      eventId: 'e1',
      eventRepository: events,
      teamRepository: teams,
      authRepository: FakeAuthRepository(user: testUser),
      tournamentRepository: FakeGroupTournamentRepository(),
    );
    addTearDown(vm.dispose);
    return EventDetailScreen(viewModel: vm);
  }

  testWidgets('cover, details, count and the three answers', (tester) async {
    await pumpInApp(tester, screen(), width: 390, height: 1400);
    await tester.pumpAndSettle();
    expect(find.byType(CoverHeader), findsNothing);
    expect(find.byType(DateBadge), findsOneWidget);
    expect(find.text('Thursday practice'), findsWidgets);
    expect(find.text('Riverside Field 2'), findsOneWidget);
    expect(find.text('1 person going'), findsOneWidget);
    for (final label in ['Going', 'Maybe', "Can't go"]) {
      expect(find.text(label), findsWidgets, reason: label);
    }
  });

  testWidgets('tapping Going answers and updates the count', (tester) async {
    await pumpInApp(tester, screen(), width: 390, height: 1400);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Going').first);
    await tester.pumpAndSettle();
    expect(events.events['e1']!.rsvpOf(testUser.uid), RsvpStatus.going);
    expect(find.text('2 people going'), findsOneWidget);
  });

  for (final theme in GoldenTheme.values) {
    testWidgets('meets accessibility guidelines, ${theme.name}', (
      tester,
    ) async {
      await pumpInApp(tester, screen(), theme: theme, width: 390, height: 1400);
      await tester.pumpAndSettle();
      await expectAccessible(tester);
    });
  }

  testWidgets('fits at text scale 2.0', (tester) async {
    await expectNoOverflowWithLargeText(
      tester,
      screen(),
      width: 390,
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
        'event_h3',
        widths: const [GoldenWidth.phone, GoldenWidth.tablet],
        height: 1100,
      );
    },
  );
}
