// C3: AppFilterChips.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/core/ui/filter_chips.dart';

import '../../ui_harness/harness.dart';

const _opts = <FilterOption<String>>[
  (value: null, label: 'All', count: 12, leading: null),
  (value: 'open', label: 'Open', count: 5, leading: null),
  (value: 'live', label: 'Live', count: 2, leading: null),
  (value: 'done', label: 'Finished', count: 5, leading: null),
  (value: 'draft', label: 'Draft', count: null, leading: null),
];

class _Host extends StatefulWidget {
  const _Host({this.options = _opts, this.initial, this.onChanged});

  final List<FilterOption<String>> options;
  final String? initial;
  final ValueChanged<String?>? onChanged;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late String? _sel = widget.initial;

  @override
  Widget build(BuildContext context) => AppFilterChips<String>(
    options: widget.options,
    selected: _sel,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    onSelected: (v) {
      setState(() => _sel = v);
      widget.onChanged?.call(v);
    },
  );
}

Widget _gallery() => const Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    SizedBox(height: 8),
    _Host(),
    SizedBox(height: 8),
    _Host(initial: 'live'),
    SizedBox(height: 8),
    _Host(
      options: [
        (value: null, label: 'All', count: null, leading: null),
        (
          value: 'a',
          label: 'Hosted',
          count: 3,
          leading: CircleAvatar(radius: 5, backgroundColor: Colors.grey),
        ),
      ],
      initial: 'a',
    ),
  ],
);

void main() {
  testWidgets('gallery goldens, light and dark', skip: goldenSkip != null, (
    t,
  ) async {
    await expectGoldens(t, _gallery(), 'filter_chips_gallery', height: 220);
  });

  for (final theme in GoldenTheme.values) {
    testWidgets('meets tap target, label and contrast guidelines, '
        '${theme.name}', (t) async {
      await pumpInApp(t, _gallery(), theme: theme, height: 220);
      await expectAccessible(t);
    });
  }

  testWidgets(
    'selected chip is filled chipOn, with onChipOn text and a check',
    (t) async {
      await pumpInApp(t, const _Host(initial: 'open'));
      final c = AppColors.light;
      final chip = t.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'Open 5'),
      );
      expect(chip.selected, isTrue);
      expect(chip.showCheckmark, isTrue, reason: 'not colour alone');
      final theme = Theme.of(t.element(find.byType(AppFilterChips<String>)));
      expect(theme.chipTheme.selectedColor, c.chipOn);
      final label = t.widget<RichText>(
        find
            .descendant(
              of: find.widgetWithText(ChoiceChip, 'Open 5'),
              matching: find.byType(RichText),
            )
            .first,
      );
      expect(label.text.style!.color, c.onChipOn);
      final other = t.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'Live 2'),
      );
      expect(other.selected, isFalse);
    },
  );

  testWidgets('tapping reports the value; All reports null', (t) async {
    final got = <String?>[];
    await pumpInApp(t, _Host(initial: 'live', onChanged: got.add));
    await t.tap(find.text('Finished 5'));
    await t.pump();
    await t.tap(find.text('All 12'));
    await t.pump();
    expect(got, ['done', null]);
    expect(
      t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'All 12')).selected,
      isTrue,
    );
  });

  testWidgets('scrolls sideways when the chips do not fit', (t) async {
    await pumpInApp(t, const _Host());
    final scroll = t.state<ScrollableState>(find.byType(Scrollable));
    expect(scroll.position.maxScrollExtent, greaterThan(0));
    expect(t.takeException(), isNull);
  });

  testWidgets('works at text scale 2.0', (t) async {
    await expectNoOverflowWithLargeText(t, _gallery(), height: 400);
    await t.tap(find.text('Open 5').first);
    await t.pump();
    expect(t.takeException(), isNull);
  });

  testWidgets('chips are at least 48 px tall to tap', (t) async {
    await pumpInApp(t, const _Host(initial: 'live'));
    final h = t.ensureSemantics();
    await expectLater(t, meetsGuideline(androidTapTargetGuideline));
    h.dispose();
  });
}
