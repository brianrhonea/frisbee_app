// C6: SummaryTiles.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/ui/core/ui/summary_tiles.dart';

import '../../ui_harness/harness.dart';

const _tiles = [
  SummaryTile(value: '3', label: 'Games this week'),
  SummaryTile(value: '12', label: 'Unread'),
  SummaryTile(value: '2', label: 'Needs RSVP'),
  SummaryTile(value: '48', label: 'Teammates'),
];

/// Placeholders pulse for ever unless animations are off.
Widget _still(Widget child) => Builder(
  builder: (context) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: true),
    child: child,
  ),
);

Widget _gallery() => _still(
  Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SummaryTiles(tiles: _tiles),
        const SizedBox(height: 16),
        SummaryTiles(
          tiles: [
            SummaryTile(value: '3', label: 'Tap me', onTap: () {}),
            const SummaryTile(value: '1,204', label: 'A rather long caption'),
          ],
        ),
        const SizedBox(height: 16),
        const SummaryTiles(tiles: _tiles, loading: true),
      ],
    ),
  ),
);

void main() {
  testWidgets('gallery goldens, light and dark', skip: goldenSkip != null, (
    t,
  ) async {
    await expectGoldens(t, _gallery(), 'summary_tiles_gallery', height: 520);
  });

  testWidgets('shows every value and caption (upper-cased)', (t) async {
    await pumpInApp(t, const SummaryTiles(tiles: _tiles));
    for (final tile in _tiles) {
      expect(find.text(tile.value), findsOneWidget);
      expect(find.text(tile.label.toUpperCase()), findsOneWidget);
    }
  });

  testWidgets('a tile with onTap is a button and fires', (t) async {
    var taps = 0;
    final handle = t.ensureSemantics();
    await pumpInApp(
      t,
      SummaryTiles(
        tiles: [SummaryTile(value: '3', label: 'Games', onTap: () => taps++)],
      ),
    );
    expect(
      t.getSemantics(find.text('3')),
      matchesSemantics(label: '3, Games', isButton: true, hasTapAction: true),
    );
    await t.tap(find.text('3'));
    expect(taps, 1);
    handle.dispose();
  });

  testWidgets('loading shows placeholders, no numbers', (t) async {
    await pumpInApp(
      t,
      _still(const SummaryTiles(tiles: _tiles, loading: true)),
    );
    expect(find.text('3'), findsNothing);
    expect(find.byType(Card), findsNWidgets(4));
  });

  testWidgets('wraps to two lines on a narrow phone', (t) async {
    await pumpInApp(t, const SummaryTiles(tiles: _tiles), width: 320);
    final tops = {
      for (final c in t.widgetList<Card>(find.byType(Card)))
        t.getTopLeft(find.byWidget(c)).dy,
    };
    expect(tops.length, greaterThan(1));
    expect(t.takeException(), isNull);
  });

  for (final theme in GoldenTheme.values) {
    testWidgets('meets accessibility guidelines, ${theme.name}', (t) async {
      await pumpInApp(
        t,
        SummaryTiles(
          tiles: [
            SummaryTile(value: '3', label: 'Games', onTap: () {}),
            const SummaryTile(value: '2', label: 'Unread'),
          ],
        ),
        theme: theme,
      );
      await expectAccessible(t);
    });
  }

  testWidgets('fits at text scale 2.0', (t) async {
    await expectNoOverflowWithLargeText(t, _gallery(), height: 1400);
    await expectNoOverflowWithLargeText(
      t,
      const SummaryTiles(tiles: _tiles),
      theme: GoldenTheme.dark,
    );
  });
}
