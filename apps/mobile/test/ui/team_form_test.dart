import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/teams/widgets/team_form.dart';

void main() {
  Future<List<NewTeam>> pump(WidgetTester tester, {NewTeam? initial}) async {
    final submitted = <NewTeam>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: TeamForm(
              initial: initial,
              submitLabel: initial == null ? 'Create team' : 'Save',
              onSubmit: submitted.add,
            ),
          ),
        ),
      ),
    );
    return submitted;
  }

  testWidgets('creating a team confirms the division, which is for good', (
    tester,
  ) async {
    final submitted = await pump(tester);
    expect(
      find.text("Can't be changed after the team is created."),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextFormField).first, 'Texas BQQ');
    await tester.tap(find.text('Create team'));
    await tester.pumpAndSettle();
    expect(find.text('Is Mixed the right division?'), findsOneWidget);
    expect(
      find.textContaining("You won't be able to change divisions"),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(submitted, isEmpty, reason: 'back to the form to fix it');

    await tester.tap(find.text('Create team'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create in Mixed'));
    await tester.pumpAndSettle();
    expect(submitted.single.division, Division.mixed);
    expect(submitted.single.name, 'Texas BQQ');
  });

  testWidgets("an existing team's division is locked", (tester) async {
    final submitted = await pump(
      tester,
      initial: const NewTeam(
        name: 'Texas BQQ',
        division: Division.open,
        level: CompetitionLevel.club,
      ),
    );
    expect(
      find.text('To change the division, contact support.'),
      findsOneWidget,
    );
    final dropdown = tester.widget<DropdownButton<Division>>(
      find.byType(DropdownButton<Division>),
    );
    expect(dropdown.onChanged, isNull);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    // No division question when editing.
    expect(find.textContaining('right division'), findsNothing);
    expect(submitted.single.division, Division.open);
  });
}
