// K8: fills the gaps left by design_tokens_test.dart. Reads the shared fixture
// (packages/shared/fixtures/design_tokens/tokens.json).
//
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';

const _fixture = '../../packages/shared/fixtures/design_tokens/tokens.json';
void main() {
  final doc =
      jsonDecode(File(_fixture).readAsStringSync()) as Map<String, dynamic>;

  group('fixture shape the scalar tests rely on', () {
    test('text styles have size, line and weight', () {
      final text = doc['text'] as Map<String, dynamic>;
      expect(text, isNotEmpty);
      for (final e in text.entries) {
        final t = e.value as Map<String, dynamic>;
        expect(t['app'], 'AppText.${e.key}', reason: e.key);
        for (final k in ['size', 'line', 'weight']) {
          expect(t[k], isA<num>(), reason: '${e.key}.$k');
        }
      }
    });

    test('space, radius and motion list numeric values', () {
      for (final group in ['space', 'radius', 'motion']) {
        final m = doc[group] as Map<String, dynamic>;
        for (final e in m.entries) {
          if (e.key.startsWith(r'$')) continue;
          expect(
            e.value,
            anyOf(isA<num>(), isA<List>()),
            reason: '$group.${e.key}',
          );
        }
      }
    });
  });

  group('AppColors has no colour the fixture does not list', () {
    test('every AppColors field name is a fixture app name', () {
      final src = File('lib/ui/core/themes/theme.dart').readAsStringSync();
      final cls = src.substring(src.indexOf('class AppColors'));
      final end = cls.indexOf('static const light');
      final fields = RegExp(
        r'^\s*final Color (\w+);',
        multiLine: true,
      ).allMatches(cls.substring(0, end)).map((m) => m.group(1)!).toSet();
      final named = {
        for (final v in (doc['color'] as Map<String, dynamic>).values)
          if ((v as Map)['app'] != null) v['app'] as String,
      };
      expect(
        fields.difference(named),
        isEmpty,
        reason: 'colours in AppColors that the fixture does not list',
      );
      expect(
        named.difference(fields),
        isEmpty,
        reason: 'fixture app names with no AppColors field',
      );
    });

    test('light and dark differ where the fixture says they differ', () {
      // Guards a theme being copied into the other by mistake.
      expect(AppColors.light.background, isNot(AppColors.dark.background));
      expect(AppColors.light.ink, isNot(AppColors.dark.ink));
    });
  });

  group('AppText matches text.*', () {
    test('size, line height, weight and face per style', () {
      final styles = <String, TextStyle>{
        'caption': AppText.caption,
        'secondary': AppText.secondary,
        'label': AppText.label,
        'body': AppText.body,
        'bodyStrong': AppText.bodyStrong,
        'section': AppText.section,
        'heading3': AppText.heading3,
        'heading2': AppText.heading2,
        'heading1': AppText.heading1,
        'scoreSmall': AppText.scoreSmall,
        'score': AppText.score,
      };
      final text = doc['text'] as Map<String, dynamic>;
      expect(styles.keys.toSet(), text.keys.toSet());
      final fonts = doc['font'] as Map<String, dynamic>;
      for (final e in text.entries) {
        final t = e.value as Map<String, dynamic>;
        final s = styles[e.key]!;
        expect(s.fontSize, (t['size'] as num).toDouble(), reason: e.key);
        expect(
          s.height! * s.fontSize!,
          closeTo((t['line'] as num) * 1.0, 1e-9),
          reason: '${e.key} line height',
        );
        expect(s.fontWeight!.value, t['weight'], reason: '${e.key} weight');
        expect(
          s.fontFamily,
          fonts[t['font'] ?? 'body'],
          reason: '${e.key} font',
        );
      }
    });
  });
  group('AppSpace matches space.*', () {
    test('every spacing value', () {
      final space = doc['space'] as Map<String, dynamic>;
      final values = <String, double>{
        'xs': AppSpace.xs,
        'sm': AppSpace.sm,
        'md': AppSpace.md,
        'lg': AppSpace.lg,
        'xl': AppSpace.xl,
        'xxl': AppSpace.xxl,
        'xxxl': AppSpace.xxxl,
        'pageEdge': AppSpace.pageEdge,
        'card': AppSpace.card,
        'control': AppSpace.control,
      };
      final fixture = {
        for (final e in space.entries)
          if (!e.key.startsWith(r'$')) e.key: (e.value as num).toDouble(),
      };
      expect(values, fixture);
    });
  });
  group('AppRadius matches radius.*', () {
    test('card, control and pill', () {
      final r = doc['radius'] as Map<String, dynamic>;
      expect(AppRadius.card, (r['card'] as num).toDouble());
      expect(AppRadius.control, (r['control'] as num).toDouble());
      expect(AppRadius.pill, (r['pill'] as num).toDouble());
      expect(AppRadius.card, cardRadius);
      expect(AppRadius.control, controlRadius);
    });
  });
  group('AppMotion matches motion.*', () {
    final m = doc['motion'] as Map<String, dynamic>;

    test('fast, base and sheet durations and easing', () {
      expect(AppMotion.fast.inMilliseconds, m['fast']);
      expect(AppMotion.base.inMilliseconds, m['base']);
      expect(AppMotion.sheet.inMilliseconds, m['sheet']);
      final e = (m['easing'] as List)
          .map((v) => (v as num).toDouble())
          .toList();
      expect([
        AppMotion.easing.a,
        AppMotion.easing.b,
        AppMotion.easing.c,
        AppMotion.easing.d,
      ], e);
    });

    for (final reduce in [false, true]) {
      testWidgets('of() with disableAnimations=$reduce', (tester) async {
        late Duration d;
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(disableAnimations: reduce),
            child: Builder(
              builder: (c) {
                d = AppMotion.of(c, AppMotion.base);
                return const SizedBox();
              },
            ),
          ),
        );
        expect(d.inMilliseconds, reduce ? m['reducedMotion'] : m['base']);
      });
    }
  });
}
