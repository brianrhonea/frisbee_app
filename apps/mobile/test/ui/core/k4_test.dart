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

    test('selected segment outline passes 3:1 on the page and a card '
        '(${e.key})', () {
      expect(_contrast(c.accent, c.background), greaterThanOrEqualTo(3));
      expect(_contrast(c.accent, c.card), greaterThanOrEqualTo(3));
      expect(AppSegmentedButton.outlineWidth, greaterThanOrEqualTo(1.5));
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
