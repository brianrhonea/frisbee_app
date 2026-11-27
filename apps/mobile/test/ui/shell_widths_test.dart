// N5: the shell at the guide's widths: bottom bar under 600, rail 600-899,
// sidebar 900 and up, content capped at 1600.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/ui/core/ui/layout.dart';
import 'package:frisbee_app/ui/home/widgets/home_screen.dart';
import 'package:go_router/go_router.dart';

import '../testing/app_harness.dart';

void main() {
  test('breakpoints are 600, 900 and 1200 with a 1600 cap', () {
    expect(ScreenSize.forWidth(599), ScreenSize.mobile);
    expect(ScreenSize.forWidth(600), ScreenSize.tablet);
    expect(ScreenSize.forWidth(899), ScreenSize.tablet);
    expect(ScreenSize.forWidth(900), ScreenSize.desktop);
    expect(ScreenSize.forWidth(1200), ScreenSize.desktop);
    expect(ScreenSize.panelWidth, 1200);
    expect(ScreenSize.maxShellWidth, 1600);
  });

  // The sidebar has the "Better together." card, the rail does not.
  final sidebar = find.text('Better together.');
  final bar = find.byType(NavigationBar);

  testWidgets('360: bottom bar, no rail or sidebar', (t) async {
    await pumpFullApp(t, size: const Size(360, 780));
    expect(bar, findsOneWidget);
    expect(sidebar, findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('768: icon rail, no bottom bar, no sidebar', (t) async {
    await pumpFullApp(t, size: const Size(768, 1024));
    expect(bar, findsNothing);
    expect(sidebar, findsNothing);
    expect(find.byIcon(Icons.explore_outlined), findsWidgets);
    expect(t.takeException(), isNull);
  });

  testWidgets('1024: full sidebar with the tab labels', (t) async {
    await pumpFullApp(t, size: const Size(1024, 768));
    expect(bar, findsNothing);
    expect(sidebar, findsOneWidget);
    for (final label in ['Home', 'Discover', 'Teams', 'Schedule', 'Chats']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    expect(t.takeException(), isNull);
  });

  testWidgets('1440: sidebar and page, nothing overflows', (t) async {
    await pumpFullApp(t, size: const Size(1440, 900));
    expect(sidebar, findsOneWidget);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('wider than 1600 the page stops growing', (t) async {
    await pumpFullApp(t, size: const Size(2000, 900));
    final page = t.getSize(find.byType(HomeScreen));
    expect(page.width, lessThanOrEqualTo(ScreenSize.maxShellWidth));
    expect(t.takeException(), isNull);
  });

  testWidgets('every tab opens at every width', (t) async {
    for (final size in const [
      Size(360, 780),
      Size(768, 1024),
      Size(1024, 768),
      Size(1440, 900),
    ]) {
      await pumpFullApp(t, size: size);
      final router = GoRouter.of(t.element(find.byType(HomeScreen)));
      for (final path in ['/explore', '/teams', '/schedule', '/messages']) {
        router.go(path);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: '$path at $size');
      }
    }
  });
}
