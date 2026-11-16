import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/ui/core/ui/tap_outside_unfocus.dart';

void main() {
  Future<FocusNode> pump(WidgetTester tester, {Widget? beside}) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) => TapOutsideUnfocus(child: child!),
        home: Scaffold(
          body: Column(
            children: [
              TextFieldTapRegion(
                child: Row(
                  children: [
                    Expanded(child: TextField(focusNode: focus)),
                    ?beside,
                  ],
                ),
              ),
              const SizedBox(height: 300, child: Text('Elsewhere')),
            ],
          ),
        ),
      ),
    );
    return focus;
  }

  testWidgets('a tap outside the field closes the keyboard', (tester) async {
    final focus = await pump(tester);
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.tap(find.text('Elsewhere'));
    await tester.pump();
    expect(focus.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('a send button beside the field keeps it open', (tester) async {
    var sent = 0;
    final focus = await pump(
      tester,
      beside: IconButton(
        tooltip: 'Send',
        onPressed: () => sent++,
        icon: const Icon(Icons.send),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    expect(sent, 1);
    expect(focus.hasFocus, isTrue);
  });

  testWidgets('a sheet opened after dropKeyboard gives no focus back', (
    tester,
  ) async {
    final focus = await pump(tester);
    await tester.tap(find.byType(TextField));
    await tester.pump();
    final context = tester.element(find.text('Elsewhere'));
    dropKeyboard();
    final sheet = showModalBottomSheet<void>(
      context: context,
      builder: (_) => const SizedBox(height: 200, child: TextField()),
    );
    await tester.pumpAndSettle();
    // Closed by tapping the barrier, outside the sheet.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await sheet;
    expect(focus.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
  });
}
