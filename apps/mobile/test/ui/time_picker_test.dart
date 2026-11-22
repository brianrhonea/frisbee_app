import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/ui/core/ui/time_picker.dart';

// Time pickers open on the hour and minute boxes to type into, with the
// clock a tap away.
void main() {
  testWidgets('types the time, or switches to the clock', (tester) async {
    TimeOfDay? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => picked = await showTypedTimePicker(
              context: context,
              initialTime: const TimeOfDay(hour: 9, minute: 0),
            ),
            child: const Text('Pick'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Pick'));
    await tester.pumpAndSettle();

    // Hour and minute boxes, the hour focused for typing.
    final fields = find.descendant(
      of: find.byType(Dialog),
      matching: find.byType(TextField),
    );
    expect(fields, findsNWidgets(2));
    // The hour is focused, so typing goes straight into it.
    final hourInput = find.descendant(
      of: fields.first,
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(hourInput).focusNode.hasFocus, isTrue);

    await tester.enterText(fields.first, '6');
    await tester.enterText(fields.last, '45');
    // The clock is one tap away.
    await tester.tap(find.byIcon(Icons.access_time));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(TextField),
      ),
      findsNothing,
    );
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(picked?.minute, 45);
    expect(picked?.hourOfPeriod, 6);
  });
}
