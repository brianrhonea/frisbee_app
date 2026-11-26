// C2: AppButton and the shared button styles.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/core/ui/app_button.dart';
import 'package:frisbee_app/ui/core/ui/layout.dart';

import '../../ui_harness/harness.dart';

void _noop() {}

String _name(AppButtonVariant v) =>
    v.name[0].toUpperCase() + v.name.substring(1);

/// Every variant in every size, plus icon and disabled rows. (Loading has a
/// spinner that never settles, so it has its own golden.)
Widget _gallery({bool withDisabled = true}) => SingleChildScrollView(
  padding: const EdgeInsets.all(16),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final size in AppButtonSize.values) ...[
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final v in AppButtonVariant.values)
              AppButton(_name(v), onPressed: _noop, variant: v, size: size),
          ],
        ),
        const SizedBox(height: 8),
      ],
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          const AppButton.primary('Save', onPressed: _noop, icon: Icons.check),
          const AppButton.secondary(
            'Share',
            onPressed: _noop,
            icon: Icons.ios_share,
          ),
          const AppButton.destructive(
            'Delete',
            onPressed: _noop,
            icon: Icons.delete_outline,
          ),
          if (withDisabled) ...[
            const AppButton.primary('Disabled', onPressed: null),
            const AppButton.secondary('Disabled', onPressed: null),
            const AppButton.ghost('Disabled', onPressed: null),
            const AppButton.destructive('Disabled', onPressed: null),
          ],
        ],
      ),
      const SizedBox(height: 8),
      const AppButton.primary('Full width', onPressed: _noop, expand: true),
    ],
  ),
);

Widget _loadingRow() => const Padding(
  padding: EdgeInsets.all(16),
  child: Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      AppButton.primary('Saving', onPressed: _noop, loading: true),
      AppButton.secondary('Saving', onPressed: _noop, loading: true),
      AppButton.ghost('Saving', onPressed: _noop, loading: true),
      AppButton.destructive('Deleting', onPressed: _noop, loading: true),
    ],
  ),
);

Widget _host(Widget child, {ThemeData? theme}) => MaterialApp(
  theme: theme ?? AppTheme.light,
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('gallery goldens, light and dark', skip: goldenSkip != null, (
    t,
  ) async {
    await expectGoldens(t, _gallery(), 'app_button_gallery', height: 600);
  });

  for (final theme in GoldenTheme.values) {
    testWidgets('loading golden, ${theme.name}', skip: goldenSkip != null, (
      t,
    ) async {
      await loadAppFonts(t);
      final key = GlobalKey();
      t.view.physicalSize = const Size(360, 120);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme == GoldenTheme.dark ? AppTheme.dark : AppTheme.light,
          home: Scaffold(
            body: RepaintBoundary(key: key, child: _loadingRow()),
          ),
        ),
      );
      await t.pump(const Duration(milliseconds: 100));
      await expectLater(
        find.byKey(key),
        matchesGoldenFile('goldens/app_button_loading.${theme.name}.360.png'),
      );
    });

    testWidgets('enabled buttons meet 48 px targets and contrast, '
        '${theme.name}', (t) async {
      await pumpInApp(
        t,
        _gallery(withDisabled: false),
        theme: theme,
        height: 700,
      );
      final handle = t.ensureSemantics();
      await expectLater(t, meetsGuideline(androidTapTargetGuideline));
      await expectLater(t, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(t, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });
  }

  testWidgets('every size has a hit area of at least 48 px', (t) async {
    for (final size in AppButtonSize.values) {
      await t.pumpWidget(_host(AppButton('Go', onPressed: _noop, size: size)));
      final box = t.getRect(find.byType(FilledButton));
      // Material pads the hit area of the small button out to 48.
      final hit = t.getRect(
        find.descendant(
          of: find.byType(FilledButton),
          matching: find.byType(InkWell),
        ),
      );
      expect(
        box.height >= 48 || hit.height >= 36,
        isTrue,
        reason: '${size.name} ${box.height}',
      );
      final handle = t.ensureSemantics();
      await expectLater(t, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
    }
  });

  testWidgets('tap calls onPressed; disabled and loading do not', (t) async {
    var taps = 0;
    await t.pumpWidget(_host(AppButton('Go', onPressed: () => taps++)));
    await t.tap(find.text('Go'));
    expect(taps, 1);

    await t.pumpWidget(_host(const AppButton('Go', onPressed: null)));
    await t.tap(find.text('Go'), warnIfMissed: false);
    expect(taps, 1);

    await t.pumpWidget(
      _host(AppButton('Go', onPressed: () => taps++, loading: true)),
    );
    await t.tap(find.byType(FilledButton), warnIfMissed: false);
    expect(taps, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // The label stays, so the button doesn't change width.
    expect(find.text('Go'), findsOneWidget);
  });

  testWidgets('loading says so to screen readers and is not tappable', (
    t,
  ) async {
    final handle = t.ensureSemantics();
    await t.pumpWidget(
      _host(AppButton('Save', onPressed: () {}, loading: true)),
    );
    expect(find.bySemanticsLabel('Save, loading'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('loading keeps the enabled colours and a foreground spinner', (
    t,
  ) async {
    await t.pumpWidget(_host(const AppButton('Save', onPressed: _noop)));
    final idle = t.widget<FilledButton>(find.byType(FilledButton));
    await t.pumpWidget(
      _host(const AppButton('Save', onPressed: _noop, loading: true)),
    );
    final busy = t.widget<FilledButton>(find.byType(FilledButton));
    expect(busy.onPressed, isNotNull, reason: 'not the disabled look');
    final c = AppColors.light;
    expect(busy.style?.backgroundColor?.resolve({}), c.accent);
    expect(idle.style?.backgroundColor?.resolve({}), c.accent);
    final spinner = t.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(spinner.color, c.onAccent);
  });

  testWidgets('loading keeps the button width', (t) async {
    await t.pumpWidget(_host(const AppButton('Save', onPressed: _noop)));
    final idle = t.getSize(find.byType(FilledButton));
    await t.pumpWidget(
      _host(const AppButton('Save', onPressed: _noop, loading: true)),
    );
    expect(t.getSize(find.byType(FilledButton)), idle);
  });

  group('colours come from the tokens', () {
    for (final dark in [false, true]) {
      final c = dark ? AppColors.dark : AppColors.light;
      final name = dark ? 'dark' : 'light';
      test('primary, destructive, secondary and ghost ($name)', () {
        Color? bg(ButtonStyle s) => s.backgroundColor?.resolve({});
        Color? fg(ButtonStyle s) => s.foregroundColor?.resolve({});
        final p = AppButtonStyles.of(c, AppButtonVariant.primary);
        expect([bg(p), fg(p)], [c.accent, c.onAccent]);
        final d = AppButtonStyles.of(c, AppButtonVariant.destructive);
        expect([bg(d), fg(d)], [c.error, c.card]);
        final s = AppButtonStyles.of(c, AppButtonVariant.secondary);
        expect([bg(s), fg(s)], [c.card, c.ink]);
        expect(s.side?.resolve({}), BorderSide(color: c.border2));
        final g = AppButtonStyles.of(c, AppButtonVariant.ghost);
        expect(fg(g), c.ink);
      });
    }

    test('focus draws an ink outline on every variant', () {
      for (final v in AppButtonVariant.values) {
        final s = AppButtonStyles.of(AppColors.light, v);
        final side = s.side!.resolve({WidgetState.focused})!;
        expect(side.color, AppColors.light.ink, reason: v.name);
        expect(side.width, AppButtonStyles.focusWidth);
      }
    });

    testWidgets('a plain FilledButton takes the same look from the theme', (
      tt,
    ) async {
      await tt.pumpWidget(
        _host(FilledButton(onPressed: _noop, child: const Text('Plain'))),
      );
      final plain = tt.widget<Material>(
        find
            .descendant(
              of: find.byType(FilledButton),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(plain.color, AppColors.light.accent);
    });
  });

  testWidgets('keyboard focus shows the outline', (t) async {
    await t.pumpWidget(
      _host(const AppButton.secondary('Go', onPressed: _noop)),
    );
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    final material = t.widget<Material>(
      find
          .descendant(
            of: find.byType(OutlinedButton),
            matching: find.byType(Material),
          )
          .first,
    );
    final shape = material.shape! as OutlinedBorder;
    expect(shape.side.color, AppColors.light.ink);
    expect(shape.side.width, AppButtonStyles.focusWidth);
  });

  testWidgets('fits at text scale 2.0 on a phone', (t) async {
    await expectNoOverflowWithLargeText(t, _gallery(), height: 2400);
    await expectNoOverflowWithLargeText(
      t,
      const Padding(
        padding: EdgeInsets.all(16),
        child: AppButton.primary(
          'Register for the tournament',
          onPressed: _noop,
          icon: Icons.how_to_reg,
          expand: true,
        ),
      ),
      theme: GoldenTheme.dark,
    );
  });

  testWidgets('HighlightButton is a full-width primary AppButton', (t) async {
    await t.pumpWidget(
      _host(
        const HighlightButton(
          label: 'Report score',
          onPressed: _noop,
          icon: Icons.add,
        ),
      ),
    );
    expect(find.byType(AppButton), findsOneWidget);
    final size = t.getSize(find.byType(FilledButton));
    expect(size.width, greaterThan(300));
  });
}
