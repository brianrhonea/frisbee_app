// C5: CoverHeader.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/ui/core/ui/avatar.dart';
import 'package:frisbee_app/ui/core/ui/cover_header.dart';

import '../../ui_harness/harness.dart';

Widget _header({
  String? coverUrl,
  String? subtitle = 'Seattle · Mixed club',
  List<Widget> actions = const [],
  String title = 'Northside Flyers',
}) => SingleChildScrollView(
  child: CoverHeader(
    title: title,
    subtitle: subtitle,
    coverUrl: coverUrl,
    actions: actions,
    avatar: const Avatar(name: 'Northside Flyers', size: 72),
  ),
);

Widget _gallery() => Padding(
  padding: const EdgeInsets.all(16),
  child: SingleChildScrollView(
    child: Column(
      children: [
        CoverHeader(
          title: 'Ana Rivera',
          subtitle: '@ana · Seattle',
          avatar: const Avatar(name: 'Ana Rivera', size: 72),
          actions: [
            OutlinedButton(onPressed: () {}, child: const Text('Follow')),
          ],
        ),
        const SizedBox(height: 24),
        CoverHeader(
          title: 'A very long team name that has to wrap onto two lines',
          avatar: const Avatar(name: 'Long Name', size: 72),
          // A photo that fails to load falls back to the band.
          coverUrl: 'https://invalid.test/cover.png',
        ),
      ],
    ),
  ),
);

void main() {
  testWidgets('gallery goldens, light and dark', skip: goldenSkip != null, (
    t,
  ) async {
    await expectGoldens(t, _gallery(), 'cover_header_gallery', height: 640);
  });

  testWidgets('shows the title, subtitle, avatar and actions', (t) async {
    await pumpInApp(
      t,
      _header(
        actions: [TextButton(onPressed: () {}, child: const Text('Join'))],
      ),
    );
    expect(find.text('Northside Flyers'), findsOneWidget);
    expect(find.text('Seattle · Mixed club'), findsOneWidget);
    expect(find.byType(Avatar), findsOneWidget);
    expect(find.text('Join'), findsOneWidget);
  });

  testWidgets('without a photo, or with a broken one, there is a band', (
    t,
  ) async {
    await pumpInApp(t, _header());
    expect(find.byType(Image), findsNothing);
    await pumpInApp(t, _header(coverUrl: 'https://invalid.test/c.png'));
    expect(t.takeException(), isNull);
    expect(find.text('Northside Flyers'), findsOneWidget);
  });

  testWidgets('the title is a header; the cover is not read', (t) async {
    final handle = t.ensureSemantics();
    await pumpInApp(t, _header());
    expect(
      t.getSemantics(find.text('Northside Flyers')),
      matchesSemantics(
        isHeader: true,
        label: 'Northside Flyers\nSeattle · Mixed club',
      ),
    );
    handle.dispose();
  });

  for (final theme in GoldenTheme.values) {
    testWidgets('meets accessibility guidelines, ${theme.name}', (t) async {
      await pumpInApp(
        t,
        _header(
          actions: [TextButton(onPressed: () {}, child: const Text('Join'))],
        ),
        theme: theme,
      );
      await expectAccessible(t);
    });
  }

  testWidgets('fits at text scale 2.0', (t) async {
    await expectNoOverflowWithLargeText(
      t,
      _header(
        title: 'A very long team name that has to wrap onto two lines',
        actions: [TextButton(onPressed: () {}, child: const Text('Join'))],
      ),
    );
    await expectNoOverflowWithLargeText(t, _header(), theme: GoldenTheme.dark);
  });
}
