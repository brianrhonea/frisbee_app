// Checks AppColors against the shared design-token fixture
// (packages/shared/fixtures/design_tokens/tokens.json): every colour with an
// app name must match in light and dark, and every contrast pair must meet
// its WCAG ratio using the app's own values.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';

const _fixture = '../../packages/shared/fixtures/design_tokens/tokens.json';

final Map<String, Color Function(AppColors)> _getters = {
  'background': (c) => c.background,
  'card': (c) => c.card,
  'field': (c) => c.field,
  'border': (c) => c.border,
  'border2': (c) => c.border2,
  'ink': (c) => c.ink,
  'ink2': (c) => c.ink2,
  'muted': (c) => c.muted,
  'accent': (c) => c.accent,
  'onAccent': (c) => c.onAccent,
  'accentSoft': (c) => c.accentSoft,
  'accentInk': (c) => c.accentInk,
  'highlight': (c) => c.highlight,
  'onHighlight': (c) => c.onHighlight,
  'highlightSoft': (c) => c.highlightSoft,
  'highlightInk': (c) => c.highlightInk,
  'live': (c) => c.live,
  'liveSoft': (c) => c.liveSoft,
  'liveInk': (c) => c.liveInk,
  'error': (c) => c.error,
  'errorSoft': (c) => c.errorSoft,
  'positive': (c) => c.positive,
  'positiveSoft': (c) => c.positiveSoft,
  'sidebar': (c) => c.sidebar,
  'onSidebar': (c) => c.onSidebar,
  'onSidebarMuted': (c) => c.onSidebarMuted,
  'feature': (c) => c.feature,
  'onFeature': (c) => c.onFeature,
  'onFeatureMuted': (c) => c.onFeatureMuted,
  'featureHighlight': (c) => c.featureHighlight,
  'chipOn': (c) => c.chipOn,
  'onChipOn': (c) => c.onChipOn,
  'team': (c) => c.team,
  'personal': (c) => c.personal,
  'badge': (c) => c.badge,
  'media': (c) => c.media,
  'media2': (c) => c.media2,
  'onMedia': (c) => c.onMedia,
  'onMediaMuted': (c) => c.onMediaMuted,
};

/// Media colours: the orchestrator adds these to tokens.json after this
/// test was written; until then they are asserted here (same in both themes).
const _mediaLiterals = {
  'media': '#18181B',
  'media2': '#27272A',
  'onMedia': '#FAFAFA',
  'onMediaMuted': '#A1A1AA',
};

Color _hex(String h) =>
    Color(0xFF000000 | int.parse(h.substring(1), radix: 16));

String _str(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

double _lum(Color c) {
  double ch(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _ratio(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  final doc =
      jsonDecode(File(_fixture).readAsStringSync()) as Map<String, dynamic>;
  final colors = doc['color'] as Map<String, dynamic>;
  final themes = {'light': AppColors.light, 'dark': AppColors.dark};

  group('AppColors matches the shared fixture', () {
    for (final theme in themes.entries) {
      test('${theme.key} values', () {
        final problems = <String>[];
        for (final e in colors.entries) {
          final v = e.value as Map<String, dynamic>;
          final app = v['app'] as String?;
          if (app == null) continue;
          final get = _getters[app];
          if (get == null) {
            problems.add('${e.key}: no getter registered for AppColors.$app');
            continue;
          }
          final want = (v[theme.key] as String).toUpperCase();
          final got = _str(get(theme.value));
          if (got != want) {
            problems.add(
              'AppColors.${theme.key}.$app is $got, fixture ${e.key} says $want',
            );
          }
        }
        expect(problems, isEmpty, reason: problems.join('\n'));
      });

      test('${theme.key} media colours', () {
        for (final m in _mediaLiterals.entries) {
          expect(
            _str(_getters[m.key]!(theme.value)),
            m.value,
            reason: 'AppColors.${theme.key}.${m.key}',
          );
        }
      });
    }

    test('every fixture app name has a getter', () {
      final names = {
        for (final v in colors.values)
          if ((v as Map)['app'] != null) v['app'] as String,
      };
      expect(names.difference(_getters.keys.toSet()), isEmpty);
    });
  });

  group('contrast pairs from the fixture', () {
    for (final theme in themes.entries) {
      test('${theme.key} meets every ratio', () {
        final problems = <String>[];
        for (final p in doc['contrast'] as List) {
          final fg = colors[p[0]] as Map<String, dynamic>;
          final bg = colors[p[1]] as Map<String, dynamic>;
          final need = (p[2] as num).toDouble();
          final fgApp = fg['app'] as String?, bgApp = bg['app'] as String?;
          if (fgApp == null || bgApp == null) continue;
          final r = _ratio(
            _getters[fgApp]!(theme.value),
            _getters[bgApp]!(theme.value),
          );
          if (r < need) {
            problems.add(
              '${p[0]} ($fgApp) on ${p[1]} ($bgApp): '
              '${r.toStringAsFixed(2)} < $need',
            );
          }
        }
        expect(problems, isEmpty, reason: problems.join('\n'));
      });
    }

    test('onError on error (ColorScheme) is at least 4.5', () {
      for (final c in themes.values) {
        expect(_ratio(c.card, c.error), greaterThanOrEqualTo(4.5));
      }
    });

    test('snackbar ink on background is at least 4.5', () {
      for (final c in themes.values) {
        expect(_ratio(c.background, c.ink), greaterThanOrEqualTo(4.5));
      }
    });

    test('media text on media surfaces is at least 4.5', () {
      for (final c in themes.values) {
        expect(_ratio(c.onMedia, c.media), greaterThanOrEqualTo(4.5));
        expect(_ratio(c.onMedia, c.media2), greaterThanOrEqualTo(4.5));
        expect(_ratio(c.onMediaMuted, c.media), greaterThanOrEqualTo(4.5));
      }
    });
  });

  test('hex helper', () => expect(_str(_hex('#4338CA')), '#4338CA'));
}
