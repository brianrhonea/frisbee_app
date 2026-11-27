// C7: ListRow.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/core/ui/avatar.dart';
import 'package:frisbee_app/ui/core/ui/list_row.dart';
import 'package:frisbee_app/ui/core/ui/status_pill.dart';

import '../../ui_harness/harness.dart';

Widget _gallery() => Column(
  children: [
    ListRow(
      leading: const Avatar(name: 'Ana Rivera'),
      title: 'Ana Rivera',
      subtitle: 'See you at practice',
      trailing: const Text('2m'),
      onTap: () {},
    ),
    ListRow(
      leading: const Avatar(name: 'Northside Flyers'),
      title: 'Northside Flyers',
      subtitle: '3 new messages',
      trailing: const Text('9:41'),
      unread: true,
      onTap: () {},
    ),
    ListRow(
      leading: const Avatar(name: 'Cam Diaz'),
      title: 'Cam Diaz',
      subtitle: 'Muted chat',
      muted: true,
      onTap: () {},
    ),
    ListRow(
      leading: const Avatar(name: 'Dee Evans'),
      title: 'Dee Evans',
      subtitle: 'Selected on a wide screen',
      selected: true,
      onTap: () {},
    ),
    const ListRow(
      leading: Avatar(name: 'Eli Fox'),
      title: 'Eli Fox',
      trailing: StatusPill('Captain', tone: PillTone.accent),
    ),
    ListRow(
      leading: const Avatar(name: 'Fay Gray'),
      title: 'A very long conversation title that wraps onto a second line',
      subtitle: 'And a very long preview that also wraps onto a second line',
      unread: true,
      onTap: () {},
    ),
  ],
);

void main() {
  testWidgets('gallery goldens, light and dark', skip: goldenSkip != null, (
    t,
  ) async {
    await expectGoldens(t, _gallery(), 'list_row_gallery', height: 520);
  });

  testWidgets('shows title, subtitle and trailing, and taps', (t) async {
    var taps = 0;
    await pumpInApp(
      t,
      ListRow(
        title: 'Ana',
        subtitle: 'Hi',
        trailing: const Text('2m'),
        onTap: () => taps++,
      ),
    );
    expect(find.text('Ana'), findsOneWidget);
    expect(find.text('Hi'), findsOneWidget);
    expect(find.text('2m'), findsOneWidget);
    await t.tap(find.text('Ana'));
    expect(taps, 1);
  });

  testWidgets('the row has a minimum height, not a fixed one', (t) async {
    await pumpInApp(
      t,
      const Align(
        alignment: Alignment.topLeft,
        child: ListRow(title: 'A'),
      ),
    );
    expect(t.getSize(find.byType(ListRow)).height, ListRow.minHeight);
    // Two lines of title and subtitle make it taller.
    await pumpInApp(
      t,
      const Align(
        alignment: Alignment.topLeft,
        child: ListRow(
          title: 'A very long title that cannot fit on one line of a phone',
          subtitle: 'A very long subtitle that cannot fit on one line either',
        ),
      ),
    );
    expect(
      t.getSize(find.byType(ListRow)).height,
      greaterThan(ListRow.minHeight),
    );
  });

  testWidgets('unread: bold title and an Unread dot', (t) async {
    final handle = t.ensureSemantics();
    await pumpInApp(t, const ListRow(title: 'Ana', unread: true));
    expect(t.widget<Text>(find.text('Ana')).style?.fontWeight, FontWeight.w700);
    expect(find.bySemanticsLabel('Unread'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('muted: quiet colour, Muted icon, no unread dot', (t) async {
    final handle = t.ensureSemantics();
    await pumpInApp(t, const ListRow(title: 'Ana', muted: true, unread: true));
    expect(find.bySemanticsLabel('Muted'), findsOneWidget);
    expect(find.bySemanticsLabel('Unread'), findsNothing);
    expect(
      t.widget<Text>(find.text('Ana')).style?.color,
      AppColors.light.muted,
    );
    handle.dispose();
  });

  testWidgets('selected tints the row', (t) async {
    await pumpInApp(t, const ListRow(title: 'Ana', selected: true));
    final material = t.widget<Material>(
      find.descendant(
        of: find.byType(ListRow),
        matching: find.byType(Material),
      ),
    );
    expect(material.color, AppColors.light.accentSoft);
  });

  for (final theme in GoldenTheme.values) {
    testWidgets('meets accessibility guidelines, ${theme.name}', (t) async {
      await pumpInApp(t, _gallery(), theme: theme, height: 520);
      await expectAccessible(t);
    });
  }

  testWidgets('fits at text scale 2.0', (t) async {
    await expectNoOverflowWithLargeText(t, _gallery(), height: 1800);
    await expectNoOverflowWithLargeText(
      t,
      _gallery(),
      height: 1800,
      theme: GoldenTheme.dark,
    );
  });
}
