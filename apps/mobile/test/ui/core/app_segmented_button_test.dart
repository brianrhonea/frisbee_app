// The shared segmented control: filled chipOn on the selected segment only,
// 48 px tall, direction-aware, survives large text, and says what is selected.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/core/ui/app_segmented_button.dart';

import 'package:frisbee_app/ui/group_tournaments/widgets/hat_parts.dart';

import '../../ui_harness/harness.dart';

// Goldens: the control as three typical uses.
Widget _gallery() => Padding(
  padding: const EdgeInsets.all(16),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Center(
        child: AppSegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 1, label: Text('Members')),
            ButtonSegment(value: 2, label: Text('Players')),
            ButtonSegment(value: 3, label: Text('Staff')),
          ],
          selected: const {2},
          onSelectionChanged: (_) {},
          showSelectedIcon: false,
        ),
      ),
      const SizedBox(height: 20),
      Center(
        child: AppSegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 1, label: Text('Hosted')),
            ButtonSegment(value: 2, label: Text('League')),
          ],
          selected: const {1},
          onSelectionChanged: (_) {},
        ),
      ),
      const SizedBox(height: 20),
      AppSegmentedButton<int>(
        segments: const [
          ButtonSegment(
            value: 1,
            label: Text('Week'),
            icon: Icon(Icons.view_week_outlined),
          ),
          ButtonSegment(
            value: 2,
            label: Text('Month'),
            icon: Icon(Icons.calendar_month_outlined),
          ),
        ],
        selected: const {2},
        showSelectedIcon: false,
        expandedInsets: EdgeInsets.zero,
        onSelectionChanged: (_) {},
      ),
    ],
  ),
);

Widget _app(
  Widget child, {
  ThemeData? theme,
  TextDirection dir = TextDirection.ltr,
  double scale = 1,
  double width = 360,
}) => MaterialApp(
  theme: theme ?? AppTheme.light,
  builder: (context, home) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: Directionality(textDirection: dir, child: home!),
  ),
  home: Scaffold(
    body: Center(
      child: SizedBox(width: width, child: child),
    ),
  ),
);

AppSegmentedButton<int> _control({
  Set<int> selected = const {1},
  ValueChanged<Set<int>>? onChanged,
  bool disabled = false,
}) => AppSegmentedButton<int>(
  segments: const [
    ButtonSegment(value: 1, label: Text('One')),
    ButtonSegment(value: 2, label: Text('Two')),
    ButtonSegment(value: 3, label: Text('Three')),
  ],
  selected: selected,
  onSelectionChanged: disabled ? null : (onChanged ?? (_) {}),
  showSelectedIcon: false,
);

/// The segment's Material: its shape carries the outline.
Material _material(WidgetTester t, String label) => t.widget<Material>(
  find.ancestor(of: find.text(label), matching: find.byType(Material)).first,
);

Color? _labelColor(WidgetTester t, String label) => t
    .widget<DefaultTextStyle>(
      find
          .ancestor(
            of: find.text(label),
            matching: find.byType(DefaultTextStyle),
          )
          .first,
    )
    .style
    .color;

void main() {
  testWidgets('goldens, light and dark', skip: goldenSkip != null, (t) async {
    await expectGoldens(t, _gallery(), 'segmented_control', height: 280);
  });

  testWidgets('SegmentedTabBar follows and drives the tab controller', (
    t,
  ) async {
    late TabController controller;
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: DefaultTabController(
          length: 3,
          child: Builder(
            builder: (context) {
              controller = DefaultTabController.of(context);
              return Scaffold(
                appBar: AppBar(
                  bottom: const SegmentedTabBar(
                    labels: ['Schedule', 'Standings', 'Teams'],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    expect(
      (_material(t, 'Schedule').shape! as OutlinedBorder).side.color,
      AppColors.light.chipOn,
    );
    await t.tap(find.text('Teams'));
    await t.pumpAndSettle();
    expect(controller.index, 2);
    expect(
      (_material(t, 'Teams').shape! as OutlinedBorder).side.color,
      AppColors.light.chipOn,
    );
    expect(
      (_material(t, 'Schedule').shape! as OutlinedBorder).side,
      BorderSide.none,
    );
  });

  testWidgets('gallery meets tap-target, label and contrast guidelines', (
    t,
  ) async {
    await pumpInApp(t, _gallery());
    await expectAccessible(t);
  });

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    final c = dark ? AppColors.dark : AppColors.light;
    final theme = dark ? AppTheme.dark : AppTheme.light;

    testWidgets('selected segment is filled chipOn with onChipOn text, others '
        'none ($name)', (t) async {
      await t.pumpWidget(_app(_control(), theme: theme));
      final on = _material(t, 'One');
      final side = (on.shape! as OutlinedBorder).side;
      expect(side.color, c.chipOn);
      expect(side.width, AppSegmentedButton.outlineWidth);
      expect(on.color, c.chipOn);
      final off = _material(t, 'Two');
      expect((off.shape! as OutlinedBorder).side, BorderSide.none);
      expect(off.color, Colors.transparent);
      expect(_labelColor(t, 'One'), c.onChipOn);
    });
  }

  testWidgets('segments are at least 48 px tall', (t) async {
    await t.pumpWidget(_app(_control()));
    for (final l in ['One', 'Two', 'Three']) {
      final box = find.ancestor(
        of: find.text(l),
        matching: find.byType(InkWell),
      );
      expect(t.getSize(box.first).height, greaterThanOrEqualTo(48));
    }
  });

  testWidgets('segments run in reading order, mirrored in RTL', (t) async {
    await t.pumpWidget(_app(_control()));
    expect(
      t.getCenter(find.text('One')).dx,
      lessThan(t.getCenter(find.text('Three')).dx),
    );
    await t.pumpWidget(_app(_control(), dir: TextDirection.rtl));
    expect(
      t.getCenter(find.text('One')).dx,
      greaterThan(t.getCenter(find.text('Three')).dx),
    );
  });

  testWidgets('text scale 2.0 does not overflow on a narrow screen', (t) async {
    await t.pumpWidget(
      _app(
        AppSegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 1, label: Text('Members')),
            ButtonSegment(value: 2, label: Text('Players and guests')),
            ButtonSegment(value: 3, label: Text('Everyone else')),
          ],
          selected: const {2},
          onSelectionChanged: (_) {},
          expandedInsets: EdgeInsets.zero,
        ),
        scale: 2,
        width: 320,
      ),
    );
    expect(t.takeException(), isNull);
    expect(t.getSize(find.byType(AppSegmentedButton<int>)).width, 320);
  });

  testWidgets('sizes to its labels without expandedInsets, no overflow', (
    t,
  ) async {
    await t.pumpWidget(_app(_control(), scale: 2, width: 300));
    expect(t.takeException(), isNull);
  });

  testWidgets('semantics: button, selected on the chosen one only', (t) async {
    final handle = t.ensureSemantics();
    await t.pumpWidget(_app(_control()));
    expect(
      t.getSemantics(find.text('One')),
      matchesSemantics(
        label: 'One',
        isButton: true,
        isSelected: true,
        hasSelectedState: true,
        isEnabled: true,
        hasEnabledState: true,
        isInMutuallyExclusiveGroup: true,
        hasTapAction: true,
        hasFocusAction: true,
        isFocusable: true,
      ),
    );
    expect(
      t.getSemantics(find.text('Two')),
      matchesSemantics(
        label: 'Two',
        isButton: true,
        isSelected: false,
        hasSelectedState: true,
        isEnabled: true,
        hasEnabledState: true,
        isInMutuallyExclusiveGroup: true,
        hasTapAction: true,
        hasFocusAction: true,
        isFocusable: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('tapping reports the new selection', (t) async {
    Set<int>? got;
    await t.pumpWidget(_app(_control(onChanged: (s) => got = s)));
    await t.tap(find.text('Two'));
    expect(got, {2});
    got = null;
    await t.tap(find.text('One')); // already selected, no empty selection
    expect(got, isNull);
  });

  testWidgets('empty selection allowed: tapping the chosen one clears it', (
    t,
  ) async {
    Set<int>? got;
    await t.pumpWidget(
      _app(
        AppSegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 1, label: Text('One')),
            ButtonSegment(value: 2, label: Text('Two')),
          ],
          selected: const {1},
          emptySelectionAllowed: true,
          onSelectionChanged: (s) => got = s,
        ),
      ),
    );
    await t.tap(find.text('One'));
    expect(got, <int>{});
  });

  testWidgets('multi-select toggles', (t) async {
    Set<int>? got;
    await t.pumpWidget(
      _app(
        AppSegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 1, label: Text('One')),
            ButtonSegment(value: 2, label: Text('Two')),
          ],
          selected: const {1},
          multiSelectionEnabled: true,
          onSelectionChanged: (s) => got = s,
        ),
      ),
    );
    await t.tap(find.text('Two'));
    expect(got, {1, 2});
  });

  testWidgets('disabled control is muted and ignores taps', (t) async {
    await t.pumpWidget(_app(_control(disabled: true)));
    expect(_labelColor(t, 'Two'), AppColors.light.muted);
    await t.tap(find.text('Two'));
    expect(t.takeException(), isNull);
  });
}
