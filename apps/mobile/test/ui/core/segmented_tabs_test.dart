// C3: SegmentedTabs.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/core/ui/segmented_tabs.dart';

import '../../ui_harness/harness.dart';

class _Tabs extends StatefulWidget {
  const _Tabs({
    required this.labels,
    this.initial = 0,
    this.onChanged,
    this.icons,
  });

  final List<String> labels;
  final int initial;
  final ValueChanged<int>? onChanged;
  final List<Widget?>? icons;

  @override
  State<_Tabs> createState() => _TabsState();
}

class _TabsState extends State<_Tabs> {
  late int _i = widget.initial;

  @override
  Widget build(BuildContext context) => SegmentedTabs(
    labels: widget.labels,
    selected: _i,
    icons: widget.icons,
    onSelect: (i) {
      setState(() => _i = i);
      widget.onChanged?.call(i);
    },
  );
}

const _few = ['Overview', 'Roster', 'Schedule'];
const _many = [
  'Overview',
  'Roster',
  'Schedule',
  'Standings',
  'Film room',
  'Playbook',
  'Settings',
];

Widget _gallery() => const Padding(
  padding: EdgeInsets.all(16),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _Tabs(labels: _few, initial: 1),
      SizedBox(height: 16),
      _Tabs(
        labels: ['Week', 'Month'],
        icons: [
          Icon(Icons.view_week_outlined),
          Icon(Icons.calendar_month_outlined),
        ],
      ),
      SizedBox(height: 16),
      _Tabs(labels: _many, initial: 0),
      SizedBox(height: 16),
      _Tabs(labels: _many, initial: 5),
    ],
  ),
);

Material _seg(WidgetTester t, String label) => t.widget<Material>(
  find.ancestor(of: find.text(label), matching: find.byType(Material)).first,
);

void main() {
  testWidgets('gallery goldens, light and dark', skip: goldenSkip != null, (
    t,
  ) async {
    await expectGoldens(t, _gallery(), 'segmented_tabs_gallery', height: 320);
  });

  for (final theme in GoldenTheme.values) {
    testWidgets('meets tap target, label and contrast guidelines, '
        '${theme.name}', (t) async {
      await pumpInApp(t, _gallery(), theme: theme, height: 320);
      await expectAccessible(t);
    });
  }

  testWidgets('the selected tab is filled chipOn with onChipOn text', (
    t,
  ) async {
    await pumpInApp(t, const _Tabs(labels: _few, initial: 1));
    final c = AppColors.light;
    expect(_seg(t, 'Roster').color, c.chipOn);
    expect(_seg(t, 'Overview').color, Colors.transparent);
    final style = t
        .widget<DefaultTextStyle>(
          find
              .ancestor(
                of: find.text('Roster'),
                matching: find.byType(DefaultTextStyle),
              )
              .first,
        )
        .style;
    expect(style.color, c.onChipOn);
    expect(style.fontWeight, FontWeight.w700, reason: 'not colour alone');
  });

  testWidgets('tapping selects and reports the index', (t) async {
    final got = <int>[];
    await pumpInApp(t, _Tabs(labels: _few, onChanged: got.add));
    await t.tap(find.text('Schedule'));
    await t.pump();
    expect(got, [2]);
    expect(_seg(t, 'Schedule').color, AppColors.light.chipOn);
  });

  testWidgets('semantics: selected on the chosen tab only', (t) async {
    await pumpInApp(t, const _Tabs(labels: _few, initial: 0));
    final h = t.ensureSemantics();
    expect(
      t.getSemantics(find.text('Overview')),
      matchesSemantics(
        label: 'Overview',
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
    h.dispose();
  });

  testWidgets('a few tabs share the width; many tabs scroll', (t) async {
    await pumpInApp(t, const _Tabs(labels: _few));
    expect(
      t.getSize(find.byType(SegmentedTabs)).width,
      360,
      reason: 'fills the row',
    );
    // Nothing scrolls when everything fits.
    var scroll = t.state<ScrollableState>(find.byType(Scrollable));
    expect(scroll.position.maxScrollExtent, 0);

    await pumpInApp(t, const _Tabs(labels: _many));
    scroll = t.state<ScrollableState>(find.byType(Scrollable));
    expect(scroll.position.maxScrollExtent, greaterThan(0));
    expect(t.takeException(), isNull);
  });

  testWidgets('selecting a tab off screen scrolls it into view', (t) async {
    await pumpInApp(t, const _Tabs(labels: _many, initial: 6));
    await t.pumpAndSettle();
    final scroll = t.state<ScrollableState>(find.byType(Scrollable));
    expect(scroll.position.pixels, greaterThan(0));
    final box = t.getRect(find.text('Settings'));
    expect(box.right, lessThanOrEqualTo(360));
  });

  testWidgets('fits at text scale 2.0: scrolls, no overflow', (t) async {
    await expectNoOverflowWithLargeText(t, _gallery(), height: 600);
    final scroll = t.state<ScrollableState>(find.byType(Scrollable).first);
    expect(scroll.position.maxScrollExtent, greaterThan(0));
    await expectNoOverflowWithLargeText(
      t,
      const _Tabs(labels: _few),
      theme: GoldenTheme.dark,
    );
  });

  testWidgets('arrow keys move focus between tabs, Enter selects', (t) async {
    final got = <int>[];
    await pumpInApp(t, _Tabs(labels: _few, onChanged: got.add));
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    expect(got, isNotEmpty);
    expect(got.last, isNot(0));
  });

  testWidgets('mirrors in RTL', (t) async {
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: _Tabs(labels: _few)),
        ),
      ),
    );
    expect(
      t.getCenter(find.text('Overview')).dx,
      greaterThan(t.getCenter(find.text('Schedule')).dx),
    );
  });
}
