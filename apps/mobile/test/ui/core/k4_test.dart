// K4 and follow-ups: green only for success, a visible outline on selected
// segments, and readable tone tags.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/core/ui/app_segmented_button.dart';
import 'package:frisbee_app/ui/core/ui/layout.dart';
import 'package:frisbee_app/domain/models/hosted_tournament.dart';
import 'package:frisbee_app/ui/core/ui/tone.dart';
import 'package:frisbee_app/ui/tournaments/widgets/hosted_status_badge.dart';

Widget _app(ThemeData theme, Widget child) => MaterialApp(
  theme: theme,
  home: Scaffold(body: Center(child: child)),
);

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  test('tone palette has no blue, teal or purple (zinc + indigo rule)', () {
    expect(
      Tone.values.map((t) => t.name),
      unorderedEquals(['grey', 'amber', 'red', 'green']),
    );
  });

  test('hosted statuses: live red, registration green, the rest grey', () {
    expect(HostedStatus.live.tone, Tone.red);
    expect(HostedStatus.registration.tone, Tone.green);
    for (final s in [
      HostedStatus.draft,
      HostedStatus.seeding,
      HostedStatus.scheduled,
      HostedStatus.finished,
    ]) {
      expect(s.tone, Tone.grey, reason: s.name);
    }
  });

  final themes = {'light': AppTheme.light, 'dark': AppTheme.dark};

  for (final e in themes.entries) {
    final c = e.key == 'light' ? AppColors.light : AppColors.dark;

    for (final tone in Tone.values) {
      testWidgets('${tone.name} tag text passes 4.5:1 over page and card '
          '(${e.key})', (t) async {
        await t.pumpWidget(
          _app(e.value, ToneTag(label: 'Open', tone: tone, icon: Icons.check)),
        );
        // ToneTag is a StatusPill now: its soft fill is opaque, so the text
        // is checked against that fill.
        final ink = t.widget<Text>(find.text('Open')).style!.color!;
        final box = t.widget<Container>(
          find.descendant(
            of: find.byType(ToneTag),
            matching: find.byType(Container),
          ),
        );
        final fill = (box.decoration! as BoxDecoration).color!;
        expect(
          _contrast(ink, fill),
          greaterThanOrEqualTo(4.5),
          reason: '${tone.name} ${e.key}',
        );
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
