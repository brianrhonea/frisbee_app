// C1: the one StatusPill, and the older pills that now wrap it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/core/ui/layout.dart';
import 'package:frisbee_app/ui/core/ui/scoreboard.dart';
import 'package:frisbee_app/ui/core/ui/status_pill.dart';
import 'package:frisbee_app/ui/core/ui/tone.dart';

import '../../ui_harness/harness.dart';

const _labels = {
  PillTone.neutral: 'Draft',
  PillTone.accent: 'Captain',
  PillTone.success: 'Going',
  PillTone.warning: 'Needs RSVP',
  PillTone.live: 'Live',
  PillTone.error: 'Cancelled',
};

/// Every tone, soft and solid, with and without an icon, plus counts.
Widget _gallery() => Padding(
  padding: const EdgeInsets.all(16),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final solid in [false, true]) ...[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in PillTone.values)
              StatusPill(_labels[t]!, tone: t, solid: solid),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            StatusPill(
              'Going',
              tone: PillTone.success,
              icon: Icons.check,
              solid: solid,
            ),
            StatusPill('Live', tone: PillTone.live, dot: true, solid: solid),
            StatusPill(
              'Needs you',
              tone: PillTone.warning,
              icon: Icons.priority_high,
              solid: solid,
            ),
          ],
        ),
        const SizedBox(height: 12),
      ],
      Wrap(
        spacing: 8,
        children: [
          StatusPill.count(3),
          StatusPill.count(120),
          StatusPill.count(4, tone: PillTone.neutral),
        ],
      ),
      const SizedBox(height: 12),
      const StatusPill(
        'A very long status that has to be shortened to fit',
        maxWidth: 200,
      ),
    ],
  ),
);

void main() {
  testWidgets('gallery goldens, light and dark', skip: goldenSkip != null, (
    t,
  ) async {
    await expectGoldens(t, _gallery(), 'status_pill_gallery', height: 420);
  });

  for (final theme in GoldenTheme.values) {
    testWidgets('every tone meets text contrast, ${theme.name}', (t) async {
      await pumpInApp(t, _gallery(), theme: theme, height: 420);
      final handle = t.ensureSemantics();
      await expectLater(t, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });
  }

  testWidgets('a label is always there: every tone shows its text', (t) async {
    await pumpInApp(
      t,
      Column(
        children: [
          for (final e in _labels.entries)
            StatusPill(e.value, tone: e.key, solid: e.key.index.isOdd),
        ],
      ),
    );
    for (final l in _labels.values) {
      expect(find.text(l), findsOneWidget);
    }
  });

  testWidgets('soft pills use the soft tokens, solid ones the solid fill', (
    t,
  ) async {
    await pumpInApp(
      t,
      const Column(
        children: [
          StatusPill('A', tone: PillTone.success),
          StatusPill('B', tone: PillTone.live, solid: true),
        ],
      ),
    );
    final c = AppColors.light;
    Color fill(String label) =>
        ((t.widget<Container>(
                  find.ancestor(
                    of: find.text(label),
                    matching: find.byType(Container),
                  ),
                )).decoration
                as BoxDecoration)
            .color!;
    expect(fill('A'), c.positiveSoft);
    expect(fill('B'), c.live);
  });

  testWidgets('count pill shows 99+ above 99 and the number otherwise', (
    t,
  ) async {
    await pumpInApp(
      t,
      Column(children: [StatusPill.count(7), StatusPill.count(100)]),
    );
    expect(find.text('7'), findsOneWidget);
    expect(find.text('99+'), findsOneWidget);
  });

  testWidgets('fits at text scale 2.0 and shortens when narrow', (t) async {
    await expectNoOverflowWithLargeText(t, _gallery(), height: 1400);
    await expectNoOverflowWithLargeText(
      t,
      const Row(children: [StatusPill('Needs RSVP now', maxWidth: 90)]),
      theme: GoldenTheme.dark,
    );
  });

  group('older names are StatusPills now', () {
    testWidgets('Tag, ToneTag, CountPill, LivePill, NeedsYouPill', (t) async {
      await pumpInApp(
        t,
        const Column(
          children: [
            Tag('Mixed'),
            Tag('On it', success: true),
            ToneTag(label: 'Open', tone: Tone.green, icon: Icons.check),
            CountPill(3),
            CountPill(3, dark: true),
            LivePill(),
            NeedsYouPill('Score due'),
            NeedsYouPill('Now', strong: true),
          ],
        ),
      );
      expect(find.byType(StatusPill), findsNWidgets(8));
      expect(find.text('Score due'), findsOneWidget);
    });

    test('Tone maps onto the pill tones', () {
      expect(Tone.grey.pill, PillTone.neutral);
      expect(Tone.amber.pill, PillTone.warning);
      expect(Tone.red.pill, PillTone.live);
      expect(Tone.green.pill, PillTone.success);
    });
  });
}
