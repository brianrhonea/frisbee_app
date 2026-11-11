import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
    await tester.tap(find.text('My schedule'));
    await tester.pump();
    expect(vm.isPersonal, isTrue);
    expect(find.text('Only you will see this event.'), findsOneWidget);
    expect(find.text('Add a poll'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
