// C10: ConfirmDialog.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/core/ui/confirm_dialog.dart';

import '../../ui_harness/harness.dart';

Widget _dialog({bool destructive = false}) => ConfirmDialog(
  title: destructive ? 'Delete post?' : 'Sign out?',
  message: 'Are you sure you want to do this? It cannot be undone.',
  confirmLabel: destructive ? 'Delete post' : 'Sign out',
  destructive: destructive,
);

/// A page with a button that asks, recording the answer.
class _Host extends StatefulWidget {
  const _Host({required this.destructive});
  final bool destructive;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  bool? answer;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      TextButton(
        onPressed: () async {
          final a = await confirmDialog(
            context,
            title: 'Delete post?',
            message: 'Gone for good.',
            confirmLabel: 'Delete post',
            destructive: widget.destructive,
          );
          setState(() => answer = a);
        },
        child: const Text('Ask'),
      ),
      Text('answer: $answer'),
    ],
  );
}

void main() {
  testWidgets('gallery goldens, light and dark', skip: goldenSkip != null, (
    t,
  ) async {
    await expectGoldens(
      t,
      Column(
        children: [
          _dialog(),
          const SizedBox(height: 16),
          _dialog(destructive: true),
        ],
      ),
      'confirm_dialog_gallery',
      height: 640,
    );
  });

  testWidgets('confirm answers true', (t) async {
    await pumpInApp(t, const _Host(destructive: false));
    await t.tap(find.text('Ask'));
    await t.pumpAndSettle();
    await t.tap(find.text('Delete post'));
    await t.pumpAndSettle();
    expect(find.text('answer: true'), findsOneWidget);
  });

  testWidgets('cancel answers false', (t) async {
    await pumpInApp(t, const _Host(destructive: true));
    await t.tap(find.text('Ask'));
    await t.pumpAndSettle();
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(find.text('answer: false'), findsOneWidget);
  });

  testWidgets('dismissing by tapping outside answers false', (t) async {
    await pumpInApp(t, const _Host(destructive: true));
    await t.tap(find.text('Ask'));
    await t.pumpAndSettle();
    await t.tapAt(const Offset(4, 4));
    await t.pumpAndSettle();
    expect(find.text('answer: false'), findsOneWidget);
  });

  testWidgets('destructive uses the destructive button colour', (t) async {
    await pumpInApp(t, _dialog(destructive: true));
    final button = t.widget<FilledButton>(find.byType(FilledButton));
    expect(button.style?.backgroundColor?.resolve({}), AppColors.light.error);
  });

  testWidgets('a plain confirm uses the primary colour', (t) async {
    await pumpInApp(t, _dialog());
    final button = t.widget<FilledButton>(find.byType(FilledButton));
    expect(button.style?.backgroundColor?.resolve({}), AppColors.light.accent);
  });

  testWidgets('destructive: Cancel has the focus first', (t) async {
    await pumpInApp(t, _dialog(destructive: true));
    await t.pump();
    final cancel = t.widget<OutlinedButton>(find.byType(OutlinedButton));
    expect(cancel.autofocus, isTrue);
    await pumpInApp(t, _dialog());
    expect(
      t.widget<OutlinedButton>(find.byType(OutlinedButton)).autofocus,
      isFalse,
    );
  });

  testWidgets('confirmDialog passes cancelLabel through', (t) async {
    await pumpInApp(
      t,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => confirmDialog(
            context,
            title: 'Leave?',
            message: 'Sure?',
            cancelLabel: 'Stay',
          ),
          child: const Text('Ask'),
        ),
      ),
    );
    await t.tap(find.text('Ask'));
    await t.pumpAndSettle();
    expect(find.text('Stay'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
  });

  testWidgets('the confirm button says what happens', (t) async {
    await pumpInApp(t, _dialog(destructive: true));
    expect(find.text('Delete post'), findsOneWidget);
    expect(find.text('OK'), findsNothing);
  });

  for (final theme in GoldenTheme.values) {
    testWidgets('meets accessibility guidelines, ${theme.name}', (t) async {
      // Two dialogs fit in 640 px with real fonts, not the test font.
      await loadAppFonts(t);
      await pumpInApp(
        t,
        Column(children: [_dialog(), _dialog(destructive: true)]),
        theme: theme,
        height: 640,
      );
      await expectAccessible(t);
    });
  }

  testWidgets('fits at text scale 2.0', (t) async {
    await expectNoOverflowWithLargeText(
      t,
      SingleChildScrollView(
        child: Column(children: [_dialog(), _dialog(destructive: true)]),
      ),
      height: 1800,
    );
  });
}
