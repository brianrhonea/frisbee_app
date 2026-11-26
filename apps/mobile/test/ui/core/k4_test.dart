// K4 and follow-ups: green only for success, a visible outline on selected
// segments, and readable tone tags.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/core/ui/app_segmented_button.dart';
import 'package:frisbee_app/ui/core/ui/layout.dart';
import 'package:frisbee_app/ui/core/ui/tone.dart';

Widget _app(ThemeData theme, Widget child) => MaterialApp(
  theme: theme,
  home: Scaffold(body: Center(child: child)),
);

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  final themes = {'light': AppTheme.light, 'dark': AppTheme.dark};

  for (final e in themes.entries) {
    final c = e.key == 'light' ? AppColors.light : AppColors.dark;

    for (final tone in Tone.values) {
      testWidgets('${tone.name} tag text passes 4.5:1 over page and card '
          '(${e.key})', (t) async {
        await t.pumpWidget(
          _app(e.value, ToneTag(label: 'Open', tone: tone, icon: Icons.check)),
        );
        final ink = t.widget<Text>(find.text('Open')).style!.color!;
        final base = tone.of(t.element(find.byType(ToneTag)));
        final tint = base.withValues(alpha: 0.14);
        for (final ground in [c.background, c.card]) {
          final on = Color.alphaBlend(tint, ground);
          expect(
            _contrast(ink, on),
            greaterThanOrEqualTo(4.5),
            reason: '${tone.name} ${e.key} on $ground',
          );
        }
      });
    }

    testWidgets('green tone is the success colour (${e.key})', (t) async {
      await t.pumpWidget(
        _app(e.value, const ToneTag(label: 'Open', tone: Tone.green)),
      );
      expect(Tone.green.of(t.element(find.byType(ToneTag))), c.positive);
    });

    testWidgets('selected segment is outlined in the accent (${e.key})', (
      t,
    ) async {
      await t.pumpWidget(
        _app(
          e.value,
          AppSegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 1, label: Text('One')),
              ButtonSegment(value: 2, label: Text('Two')),
            ],
            selected: const {1},
            onSelectionChanged: (_) {},
          ),
        ),
      );
      // The outline passes 3:1 against the page and a card.
      expect(_contrast(c.accent, c.background), greaterThanOrEqualTo(3));
      expect(_contrast(c.accent, c.card), greaterThanOrEqualTo(3));
      // And is painted on the selected segment only: 1.5 px, in the accent.
      expect(AppSegmentedButton.outlineWidth, greaterThanOrEqualTo(1.5));
      final accentStrokes = <double>[];
      expect(
        t.renderObject(find.byType(AppSegmentedButton<int>)),
        paints..everything((Symbol method, List<dynamic> args) {
          if (method == #drawRRect) {
            final paint = args[1] as Paint;
            if (paint.color.toARGB32() == c.accent.toARGB32()) {
              accentStrokes.add(paint.strokeWidth);
            }
          }
          return true;
        }),
      );
      // Exactly one segment of the two is selected, so one accent outline.
      expect(accentStrokes, [AppSegmentedButton.outlineWidth]);
      // The outer outline and dividers stay the neutral border.
      final style = SegmentedButtonTheme.of(
        t.element(find.byType(SegmentedButton<int>)),
      ).style!;
      expect(style.side!.resolve({})!.color, c.border2);
    });

    testWidgets('Tag success uses the success colours (${e.key})', (t) async {
      await t.pumpWidget(
        _app(e.value, const Tag("You're on it", success: true)),
      );
      final box = t.widget<Container>(find.byType(Container).first);
      expect((box.decoration! as BoxDecoration).color, c.positiveSoft);
      expect(t.widget<Text>(find.byType(Text)).style!.color, c.positive);
      expect(_contrast(c.positive, c.positiveSoft), greaterThanOrEqualTo(4.5));
    });
  }
}
