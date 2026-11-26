// K8: fills the gaps left by design_tokens_test.dart. Reads the shared fixture
// (packages/shared/fixtures/design_tokens/tokens.json).
//
// Text, space, radius and motion tokens (AppText, AppSpace, AppRadius,
// AppMotion) are not defined in theme.dart yet (K6/K7 not built), so those
// groups are skipped with a reason. When the classes exist, replace each
// skipped body with the real comparison and remove the skip.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';

const _fixture = '../../packages/shared/fixtures/design_tokens/tokens.json';
const _notBuilt =
    'K6/K7 not built: theme.dart has no AppText/AppSpace/AppRadius/AppMotion yet';

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
          expect(e.value, anyOf(isA<num>(), isA<List>()), reason: '$group.${e.key}');
        }
      }
    });
  });

  group('AppColors has no colour the fixture does not list', () {
    test('every AppColors field name is a fixture app name', () {
      final src = File('lib/ui/core/themes/theme.dart').readAsStringSync();
      final cls = src.substring(src.indexOf('class AppColors'));
      final end = cls.indexOf('static const light');
      final fields = RegExp(r'^\s*final Color (\w+);', multiLine: true)
          .allMatches(cls.substring(0, end))
          .map((m) => m.group(1)!)
          .toSet();
      final named = {
        for (final v in (doc['color'] as Map<String, dynamic>).values)
          if ((v as Map)['app'] != null) v['app'] as String,
      };
      expect(fields.difference(named), isEmpty,
          reason: 'colours in AppColors that the fixture does not list');
      expect(named.difference(fields), isEmpty,
          reason: 'fixture app names with no AppColors field');
    });

    test('light and dark differ where the fixture says they differ', () {
      // Guards a theme being copied into the other by mistake.
      expect(AppColors.light.background, isNot(AppColors.dark.background));
      expect(AppColors.light.ink, isNot(AppColors.dark.ink));
    });
  });

  group('AppText matches text.*', () {
    test('size, line height and weight per style', () {}, skip: _notBuilt);
  });
  group('AppSpace matches space.*', () {
    test('every spacing value', () {}, skip: _notBuilt);
  });
  group('AppRadius matches radius.*', () {
    test('card, control and pill', () {}, skip: _notBuilt);
  });
  group('AppMotion matches motion.*', () {
    test('fast, base and sheet durations, easing and reduced motion', () {},
        skip: _notBuilt);
  });
}
