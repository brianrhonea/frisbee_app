import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/team_event.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/schedule/view_models/event_detail_viewmodel.dart';
import 'package:frisbee_app/ui/schedule/widgets/event_detail_screen.dart';

import '../testing/fakes.dart';
import '../testing/group_tournament_fakes.dart';

/// F7 on a team event's page: the note under the answer, its save, its
/// failure, and how it shows in Responses.
void main() {
  late FakeTeamRepository teams;
  late FakeEventRepository events;

  setUp(() {
    teams = FakeTeamRepository();
    events = FakeEventRepository();
    teams.teams['t1'] = teamWith({
      'owner': TeamRole.owner,
      testUser.uid: TeamRole.player,
    });
    events.events['e1'] = TeamEvent(
      id: 'e1',
      title: 'Thursday practice',
      startsAt: DateTime.now().add(const Duration(days: 2)),
      rsvps: {testUser.uid: RsvpStatus.going},
    );
  });

  Future<EventDetailViewModel> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final vm = EventDetailViewModel(
      teamId: 't1',
      eventId: 'e1',
      eventRepository: events,
      teamRepository: teams,
      authRepository: FakeAuthRepository(user: testUser),
      tournamentRepository: FakeGroupTournamentRepository(),
    );
    addTearDown(vm.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: EventDetailScreen(viewModel: vm),
      ),
    );
    await tester.pumpAndSettle();
    return vm;
  }

  testWidgets('a note saves cleaned, shows in Responses and Save goes', (
    tester,
  ) async {
    await pump(tester);
    final field = find.widgetWithText(TextField, 'Add a note (optional)');
    await tester.ensureVisible(field);
    await tester.enterText(field, '  Late   15 min ');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(events.events['e1']!.noteOf(testUser.uid), 'Late 15 min');
    // The saved note matches what was typed once cleaned: nothing to save.
    expect(find.text('Save'), findsNothing);
    final quoted = find.textContaining(
      '“Late 15 min”',
      findRichText: true,
      skipOffstage: false,
    );
    expect(quoted, findsOneWidget);
  });

  testWidgets('a note that fails to save says so', (tester) async {
    events.failNotes = true;
    await pump(tester);
    final field = find.widgetWithText(TextField, 'Add a note (optional)');
    await tester.ensureVisible(field);
    await tester.enterText(field, 'Late 15 min');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(events.events['e1']!.noteOf(testUser.uid), isEmpty);
    expect(find.byType(SnackBar), findsOneWidget);
  });
}
