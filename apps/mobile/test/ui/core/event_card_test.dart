// C8: EventCard and DateBadge.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/core/ui/date_badge.dart';
import 'package:frisbee_app/ui/core/ui/event_card.dart';
import 'package:frisbee_app/ui/core/ui/status_pill.dart';

import '../../ui_harness/harness.dart';

final _day = DateTime(2026, 11, 28, 18, 30);

Widget _gallery() => Padding(
  padding: const EdgeInsets.all(16),
  child: SingleChildScrollView(
    child: Column(
      children: [
        for (final card in [
          EventCard(
            date: _day,
            title: 'Team practice',
            meta: '6:30 PM · Pier 62 field',
            rsvp: EventRsvp.going,
            onTap: () {},
          ),
          EventCard(
            date: _day,
            title: 'Pickup at the park',
            meta: '6:30 PM',
            rsvp: EventRsvp.needsReply,
            recurring: true,
            onTap: () {},
          ),
          EventCard(
            date: _day,
            title: 'Scrimmage',
            meta: '6:30 PM · Cancelled by the captain',
            rsvp: EventRsvp.going,
            cancelled: true,
            onTap: () {},
          ),
          EventCard(
            date: _day,
            title: 'A tournament with a very long name that wraps',
            meta: 'Saturday, all day · A long venue name that wraps too',
            rsvp: EventRsvp.maybe,
            recurring: true,
          ),
        ]) ...[card, const SizedBox(height: 8)],
        Row(
          children: [
            DateBadge(date: _day),
            const SizedBox(width: 8),
            DateBadge(date: _day, cancelled: true),
            const SizedBox(width: 8),
            DateBadge(date: _day, size: 56),
          ],
        ),
      ],
    ),
  ),
);

void main() {
  testWidgets('gallery goldens, light and dark', skip: goldenSkip != null, (
    t,
  ) async {
    await expectGoldens(t, _gallery(), 'event_card_gallery', height: 720);
  });

  testWidgets('DateBadge shows month over day', (t) async {
    await pumpInApp(t, DateBadge(date: _day));
    expect(find.text('NOV'), findsOneWidget);
    expect(find.text('28'), findsOneWidget);
  });

  testWidgets('a cancelled DateBadge is grey and struck through', (t) async {
    await pumpInApp(t, DateBadge(date: _day, cancelled: true));
    final fill =
        (t.widget<Container>(find.byType(Container).first).decoration
                as BoxDecoration)
            .color;
    expect(fill, AppColors.light.field);
    expect(
      t.widget<Text>(find.text('28')).style?.decoration,
      TextDecoration.lineThrough,
    );
  });

  testWidgets('shows title, meta and the RSVP chip; taps', (t) async {
    var taps = 0;
    await pumpInApp(
      t,
      EventCard(
        date: _day,
        title: 'Practice',
        meta: '6:30 PM',
        rsvp: EventRsvp.going,
        onTap: () => taps++,
      ),
    );
    expect(find.text('Practice'), findsOneWidget);
    expect(find.text('6:30 PM'), findsOneWidget);
    expect(find.text('Going'), findsOneWidget);
    expect(find.text('Repeats'), findsNothing);
    await t.tap(find.text('Practice'));
    expect(taps, 1);
  });

  testWidgets('every RSVP state has a text chip', (t) async {
    for (final r in EventRsvp.values) {
      await pumpInApp(t, EventCard(date: _day, title: 'E', rsvp: r));
      expect(find.text(r.label), findsOneWidget, reason: r.name);
      expect(find.byType(StatusPill), findsOneWidget);
    }
  });

  testWidgets('cancelled replaces the RSVP chip and strikes the title', (
    t,
  ) async {
    await pumpInApp(
      t,
      EventCard(
        date: _day,
        title: 'Scrimmage',
        rsvp: EventRsvp.going,
        cancelled: true,
      ),
    );
    expect(find.text('Cancelled'), findsOneWidget);
    expect(find.text('Going'), findsNothing);
    expect(
      t.widget<Text>(find.text('Scrimmage')).style?.decoration,
      TextDecoration.lineThrough,
    );
  });

  testWidgets('recurring adds a Repeats chip', (t) async {
    await pumpInApp(t, EventCard(date: _day, title: 'Pickup', recurring: true));
    expect(find.text('Repeats'), findsOneWidget);
  });

  testWidgets('is read as one item with everything in it', (t) async {
    final handle = t.ensureSemantics();
    await pumpInApp(
      t,
      EventCard(
        date: _day,
        title: 'Pickup',
        meta: '6:30 PM',
        rsvp: EventRsvp.needsReply,
        recurring: true,
        onTap: () {},
      ),
    );
    expect(
      find.bySemanticsLabel(
        'November 28, Pickup, 6:30 PM, Needs RSVP, Repeats',
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('is at least 72 px tall', (t) async {
    await pumpInApp(t, EventCard(date: _day, title: 'Short'));
    expect(
      t.getSize(find.byType(EventCard)).height,
      greaterThanOrEqualTo(EventCard.minHeight),
    );
  });

  for (final theme in GoldenTheme.values) {
    testWidgets('meets accessibility guidelines, ${theme.name}', (t) async {
      await pumpInApp(t, _gallery(), theme: theme, height: 720);
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
