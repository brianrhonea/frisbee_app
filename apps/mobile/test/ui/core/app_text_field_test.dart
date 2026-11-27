// C10: AppTextField (and the SearchField it sits beside).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/core/ui/app_search_field.dart';
import 'package:frisbee_app/ui/core/ui/app_text_field.dart';

import '../../ui_harness/harness.dart';

Widget _gallery() => Padding(
  padding: const EdgeInsets.all(16),
  child: SingleChildScrollView(
    child: Column(
      children: [
        const AppTextField(label: 'Team name', hint: 'e.g. Northside Flyers'),
        const SizedBox(height: 16),
        AppTextField(
          label: 'Email',
          controller: TextEditingController(text: 'ana@example.com'),
          helper: 'We never share it.',
          prefixIcon: Icons.mail_outline,
        ),
        const SizedBox(height: 16),
        const AppTextField(
          label: 'Password',
          obscureText: true,
          errorText: 'Use at least 8 characters.',
        ),
        const SizedBox(height: 16),
        const AppTextField(label: 'Locked', enabled: false),
        const SizedBox(height: 16),
        const AppTextField(label: 'Notes', maxLines: 4, maxLength: 200),
        const SizedBox(height: 16),
        const AppSearchField(hint: 'Search Stall 10'),
      ],
    ),
  ),
);

void main() {
  testWidgets('gallery goldens, light and dark', skip: goldenSkip != null, (
    t,
  ) async {
    await expectGoldens(t, _gallery(), 'text_field_gallery', height: 760);
  });

  testWidgets('has a visible label, and typing reaches onChanged', (t) async {
    final seen = <String>[];
    await pumpInApp(t, AppTextField(label: 'Team name', onChanged: seen.add));
    expect(find.text('Team name'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'Flyers');
    expect(seen, ['Flyers']);
  });

  testWidgets('submitting calls onSubmitted', (t) async {
    String? sent;
    await pumpInApp(
      t,
      AppTextField(label: 'Name', onSubmitted: (v) => sent = v),
    );
    await t.enterText(find.byType(TextField), 'Ana');
    await t.testTextInput.receiveAction(TextInputAction.done);
    expect(sent, 'Ana');
  });

  testWidgets('an error is shown in words, with an icon', (t) async {
    await pumpInApp(
      t,
      const AppTextField(label: 'Password', errorText: 'Too short.'),
    );
    expect(find.text('Too short.'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  testWidgets('no error, no icon', (t) async {
    await pumpInApp(t, const AppTextField(label: 'Password'));
    expect(find.byIcon(Icons.error_outline), findsNothing);
  });

  testWidgets('the outline is the 3:1 input border; focus uses the accent', (
    t,
  ) async {
    await pumpInApp(t, const AppTextField(label: 'Name'));
    InputDecoration decoration() =>
        t.widget<TextField>(find.byType(TextField)).decoration!;
    final enabled = decoration().enabledBorder! as OutlineInputBorder;
    expect(enabled.borderSide.color, AppColors.light.border2);
    final focused = decoration().focusedBorder! as OutlineInputBorder;
    expect(focused.borderSide.color, AppColors.light.accent);
  });

  testWidgets('is at least 48 px tall', (t) async {
    await pumpInApp(
      t,
      const Align(
        alignment: Alignment.topCenter,
        child: AppTextField(label: 'Name'),
      ),
    );
    expect(t.getSize(find.byType(TextField)).height, greaterThanOrEqualTo(48));
  });

  testWidgets('a disabled field takes no input', (t) async {
    await pumpInApp(t, const AppTextField(label: 'Locked', enabled: false));
    expect(t.widget<TextField>(find.byType(TextField)).enabled, isFalse);
  });

  testWidgets('the search field keeps its hint and clear button', (t) async {
    await pumpInApp(t, const AppSearchField(hint: 'Search Stall 10'));
    expect(find.text('Search Stall 10'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'flyers');
    await t.pump();
    expect(find.byTooltip('Clear'), findsOneWidget);
  });

  for (final theme in GoldenTheme.values) {
    testWidgets('meets accessibility guidelines, ${theme.name}', (t) async {
      await pumpInApp(t, _gallery(), theme: theme, height: 760);
      await expectAccessible(t);
    });
  }

  testWidgets('fits at text scale 2.0', (t) async {
    await expectNoOverflowWithLargeText(t, _gallery(), height: 1800);
    await expectNoOverflowWithLargeText(
      t,
      _gallery(),
      height: 1800,
      theme: GoldenTheme.dark,
    );
  });
}
