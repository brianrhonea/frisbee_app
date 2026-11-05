import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/core/ui/balanced_text.dart';
import 'package:frisbee_app/ui/shell/widgets/command_palette.dart';
import 'package:frisbee_app/utils/pending_removals.dart';

void main() {
  testWidgets('removals wait out the undo window, and undo brings them back', (
    tester,
  ) async {
    {
      final committed = <String>[];
      var changes = 0;
      final r = PendingRemovals<String>(
        keyOf: (s) => s,
        commit: committed.add,
        onChange: () => changes++,
      );
      r.remove('a');
      r.remove('b');
      expect(r.visible(['a', 'b', 'c']), ['c']);
      r.undo('a');
      expect(r.visible(['a', 'b', 'c']), ['a', 'c']);
      expect(changes, 3);

      await tester.pump(PendingRemovals.undoWindow);
      expect(committed, ['b']);

      r.remove('c');
      final flushed = <String>[];
      r.flush(flushed.add);
      expect(flushed, ['c']);
      await tester.pump(PendingRemovals.undoWindow);
      expect(committed, ['b'], reason: 'flushed, not committed twice');
    }
  });

  testWidgets('balanced headlines leave no word alone on the last line', (
    tester,
  ) async {
    const style = TextStyle(fontSize: 20);
    const text = 'Find your next point on the field today';
    await tester.pumpWidget(
      const MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 380,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BalancedText(text, style: style),
                Text(text, style: style),
              ],
            ),
          ),
        ),
      ),
    );
    final texts = find.text(text);
    final balanced = tester.renderObject<RenderParagraph>(texts.first);
    final plain = tester.renderObject<RenderParagraph>(texts.last);
    // Same number of lines, but narrower, so the lines are about even.
    expect(balanced.size.height, plain.size.height);
    expect(balanced.size.width, lessThan(plain.size.width));
  });

  testWidgets('the command menu finds commands and searches', (tester) async {
    final ran = <String>[];
    PaletteCommand cmd(String label, {String keywords = ''}) => PaletteCommand(
      label: label,
      icon: Icons.circle,
      keywords: keywords,
      run: (_) => ran.add(label),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showCommandPalette(
              context,
              commands: [
                cmd('Home'),
                cmd('Rankings'),
                cmd('Notification settings', keywords: 'push mute'),
              ],
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Rankings'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'mute');
    await tester.pump();
    expect(find.text('Search Stall 10 for “mute”'), findsOneWidget);
    expect(find.text('Notification settings'), findsOneWidget);
    expect(find.text('Rankings'), findsNothing);

    // The search is first; arrow down to the match and press Enter.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(ran, ['Notification settings']);
    expect(find.byType(CommandPalette), findsNothing);
  });

  testWidgets('Ctrl K opens the menu every time, with nothing focused', (
    tester,
  ) async {
    final ran = <String>[];
    var section = -1;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: AppShortcuts(
          commands: () => [
            PaletteCommand(
              label: 'Rankings',
              icon: Icons.circle,
              run: (_) => ran.add('Rankings'),
            ),
          ],
          onSection: (i) => section = i,
          child: const Scaffold(body: Text('page')),
        ),
      ),
    );
    Future<void> ctrl(LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    for (var i = 1; i <= 2; i++) {
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await ctrl(LogicalKeyboardKey.keyK);
      expect(find.byType(CommandPalette), findsOneWidget, reason: 'try $i');
      await tester.enterText(find.byType(TextField), 'rank');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(CommandPalette), findsNothing);
    }
    expect(ran, ['Rankings', 'Rankings']);

    await ctrl(LogicalKeyboardKey.digit2);
    expect(section, 1);

    // From inside the menu: it closes and goes.
    await ctrl(LogicalKeyboardKey.keyK);
    expect(find.byType(CommandPalette), findsOneWidget);
    await ctrl(LogicalKeyboardKey.digit4);
    expect(section, 3);
    expect(find.byType(CommandPalette), findsNothing);
    await ctrl(LogicalKeyboardKey.keyK);
    expect(find.byType(CommandPalette), findsOneWidget, reason: 'opens again');
  });
}
