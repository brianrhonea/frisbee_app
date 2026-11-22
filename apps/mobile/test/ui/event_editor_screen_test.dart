import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:frisbee_app/domain/models/recurrence.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/schedule/view_models/event_editor_viewmodel.dart';
import 'package:frisbee_app/ui/schedule/widgets/event_editor_screen.dart';

import '../testing/fakes.dart';

void main() {
  testWidgets('editors pick a schedule; polls are team-only', (tester) async {
    // Tall enough that the whole form is laid out without scrolling.
    tester.view.physicalSize = const Size(390 * 3, 1800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final teams = FakeTeamRepository();
    teams.teams['t1'] = Team(
      id: 't1',
      name: 'Northside Flyers',
      division: Division.mixed,
      level: CompetitionLevel.club,
      ownerId: testUser.uid,
      members: {testUser.uid: TeamRole.owner},
    );
    final vm = EventEditorViewModel(
      teamId: 't1',
      eventId: null,
      eventRepository: FakeEventRepository(),
      teamRepository: teams,
      authRepository: FakeAuthRepository(user: testUser),
    );
    await tester.runAsync(pumpEventQueue);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: EventEditorScreen(viewModel: vm),
      ),
    );
    await tester.pump();

    expect(find.text('Add to'), findsOneWidget);
    expect(find.text('Northside Flyers'), findsOneWidget);
    expect(find.text('Add a poll'), findsOneWidget);
    await tester.tap(find.text('My calendar'));
    await tester.pump();
    expect(vm.isPersonal, isTrue);
    expect(find.text('Only you will see this event.'), findsOneWidget);
    expect(find.text('Add a poll'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a new event can repeat until a date; a series edit asks', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390 * 3, 1800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final teams = FakeTeamRepository();
    final events = FakeEventRepository();
    final vm = EventEditorViewModel(
      teamId: null,
      eventId: null,
      eventRepository: events,
      teamRepository: teams,
      authRepository: FakeAuthRepository(user: testUser),
      initialDay: DateTime(2026, 11, 20),
    );
    await tester.runAsync(pumpEventQueue);
    await tester.pumpWidget(_routed(EventEditorScreen(viewModel: vm)));
    await tester.pump();

    expect(find.text('Does not repeat'), findsOneWidget);
    await tester.tap(find.text('Does not repeat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weekly on Friday').last);
    await tester.pumpAndSettle();
    // Seven weeks on by default: eight Fridays.
    expect(find.text('Creates 8 events'), findsOneWidget);
    expect(find.text('Ends on'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Title'), 'Run');
    await tester.tap(find.text('Create event'));
    await tester.pumpAndSettle();
    expect(events.lastRepeat?.freq, RepeatFrequency.weekly);
    expect(events.mine[testUser.uid], hasLength(8));

    // Editing one of them: no Repeat, its repeat shown, and a choice on save.
    final second = events.mine[testUser.uid]!.values.elementAt(1);
    final edit = EventEditorViewModel(
      teamId: null,
      eventId: second.id,
      eventRepository: events,
      teamRepository: teams,
      authRepository: FakeAuthRepository(user: testUser),
    );
    await tester.runAsync(pumpEventQueue);
    await tester.pumpWidget(_routed(EventEditorScreen(viewModel: edit)));
    await tester.pump();
    expect(find.text('Does not repeat'), findsNothing);
    expect(find.textContaining('Repeats weekly until'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Save this and following events'), findsOneWidget);
    await tester.tap(find.text('Save this and following events'));
    await tester.pumpAndSettle();
    expect(events.lastScope, SeriesScope.following);
  });
}

/// [screen] under a router, so saving can open the event (any page).
Widget _routed(Widget screen) => MaterialApp.router(
  theme: AppTheme.light,
  routerConfig: GoRouter(
    routes: [GoRoute(path: '/', builder: (_, _) => screen)],
    errorBuilder: (_, _) => const Text('Opened'),
  ),
);
