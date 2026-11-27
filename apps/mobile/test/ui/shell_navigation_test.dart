// N3 (tab order, each tab opens its branch, state kept) and N4 (the picture
// opens the profile), on the real router over fakes.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/ui/explore/widgets/explore_screen.dart';
import 'package:frisbee_app/ui/home/widgets/home_screen.dart';
import 'package:frisbee_app/ui/messages/widgets/inbox_screen.dart';
import 'package:frisbee_app/ui/profile/widgets/profile_screen.dart';
import 'package:frisbee_app/ui/schedule/widgets/schedule_screen.dart';
import 'package:frisbee_app/ui/teams/widgets/teams_screen.dart';

import '../testing/app_harness.dart';

Future<void> _open(WidgetTester t, String label) async {
  await t.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await t.pumpAndSettle();
}

void main() {
  testWidgets('N3: the bar reads Home, Discover, Teams, Schedule, Chats', (
    t,
  ) async {
    await pumpFullApp(t);
    final labels = [
      for (final d in t.widgetList<NavigationDestination>(
        find.byType(NavigationDestination),
      ))
        d.label,
    ];
    expect(labels, ['Home', 'Discover', 'Teams', 'Schedule', 'Chats']);
    expect(find.text('Profile'), findsNothing);
  });

  testWidgets('N3: each tab opens its own page', (t) async {
    await pumpFullApp(t);
    final pages = <String, Type>{
      'Discover': ExploreScreen,
      'Teams': TeamsScreen,
      'Schedule': ScheduleScreen,
      'Chats': InboxScreen,
      'Home': HomeScreen,
    };
    for (final e in pages.entries) {
      await _open(t, e.key);
      expect(find.byType(e.value), findsOneWidget, reason: e.key);
    }
  });

  testWidgets('N3: leaving a tab keeps its state', (t) async {
    await pumpFullApp(t);
    await _open(t, 'Schedule');
    await t.tap(find.byTooltip('Next week'));
    await t.pumpAndSettle();
    expect(find.byTooltip('Today'), findsOneWidget);
    await _open(t, 'Teams');
    await _open(t, 'Schedule');
    expect(find.byTooltip('Today'), findsOneWidget, reason: 'still next week');
  });

  testWidgets('N4: the picture sits at the top right on every tab', (t) async {
    await pumpFullApp(t);
    for (final label in ['Home', 'Discover', 'Teams', 'Schedule', 'Chats']) {
      await _open(t, label);
      final avatar = find.byTooltip('My profile');
      expect(avatar, findsOneWidget, reason: label);
      expect(t.getCenter(avatar).dx, greaterThan(390 / 2), reason: label);
    }
  });

  testWidgets('N4: the picture opens the profile', (t) async {
    await pumpFullApp(t);
    await t.tap(find.byTooltip('My profile'));
    await t.pumpAndSettle();
    expect(find.byType(PlayerProfileScreen), findsOneWidget);
  });
}
