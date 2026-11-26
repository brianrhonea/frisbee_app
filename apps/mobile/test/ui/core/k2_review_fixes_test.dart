// K2 review fixes: FeatureCard draws the standard card edge, organization
// badges stay visible, and a selected tone chip's label is readable.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/core/ui/layout.dart';
import 'package:frisbee_app/ui/core/ui/tone.dart';
import 'package:frisbee_app/ui/teams/widgets/team_initials.dart';

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

    testWidgets('FeatureCard draws the card border (${e.key})', (t) async {
      await t.pumpWidget(_app(e.value, const FeatureCard(child: Text('x'))));
      final material = t.widget<Material>(
        find
            .descendant(
              of: find.byType(FeatureCard),
              matching: find.byType(Material),
            )
            .first,
      );
      final shape = material.shape! as RoundedSuperellipseBorder;
      expect(shape.side.color, c.border);
      expect(shape.side.width, 1);
      expect(material.color, c.feature);
    });

    testWidgets('organization badge is a soft accent square (${e.key})', (
      t,
    ) async {
      await t.pumpWidget(
        _app(
          e.value,
          const TeamInitials(name: 'Hylite Org', kind: TeamKind.organization),
        ),
      );
      final box = t.widget<Container>(
        find
            .descendant(
              of: find.byType(TeamInitials),
              matching: find.byType(Container),
            )
            .first,
      );
      expect((box.decoration! as BoxDecoration).color, c.accentSoft);
      final text = t.widget<Text>(find.byType(Text));
      expect(text.style!.color, c.accentInk);
      expect(c.accentSoft, isNot(c.card));
    });

    for (final tone in Tone.values) {
      testWidgets('selected ${tone.name} chip label passes 4.5:1 (${e.key})', (
        t,
      ) async {
        await t.pumpWidget(
          _app(
            e.value,
            ToneFilterBar<int>(
              filters: [(value: 1, label: 'Mine', count: 2, tone: tone)],
              selected: 1,
              onSelected: (_) {},
            ),
          ),
        );
        final label = t.widget<RichText>(
          find
              .descendant(
                of: find.byType(ChoiceChip),
                matching: find.byType(RichText),
              )
              .first,
        );
        // Selected is the theme's indigo for every tone, label on it >= 4.5:1.
        final color = label.text.style!.color!;
        expect(color, c.onChipOn);
        expect(_contrast(color, c.chipOn), greaterThanOrEqualTo(4.5));
        expect(
          t.widget<ChoiceChip>(find.byType(ChoiceChip)).selectedColor,
          isNull,
          reason: 'falls through to the theme chipOn',
        );
      });
    }
  }
}
