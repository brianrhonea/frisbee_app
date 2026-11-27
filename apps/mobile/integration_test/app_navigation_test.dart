// N7: sign in, visit the five tabs, open a team, its roster and chat, and
// step back, on the real router and shell over in-memory fakes. No network
// and no Firebase.
//
// Headless (no device), through the wrapper in test/integration:
//   flutter test test/integration/app_navigation_flow_test.dart
//
// It uses flutter_test's binding rather than the integration_test package,
// which isn't a dependency of this app, so the same file also runs through
// `flutter test` in CI. It is a whole-app flow over fakes, not a check of
// native behaviour: see the physical-device list for those.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/ui/auth/widgets/sign_in_screen.dart';
import 'package:frisbee_app/ui/explore/widgets/explore_screen.dart';
import 'package:frisbee_app/ui/home/widgets/home_screen.dart';
import 'package:frisbee_app/ui/messages/widgets/inbox_screen.dart';
import 'package:frisbee_app/ui/schedule/widgets/schedule_screen.dart';
import 'package:frisbee_app/ui/teams/widgets/team_home_screen.dart';
import 'package:frisbee_app/ui/teams/widgets/teams_screen.dart';
import 'package:go_router/go_router.dart';

import '../test/testing/app_harness.dart';
import '../test/testing/fakes.dart';

Future<void> _tab(WidgetTester t, String label) async {
  await t.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await t.pumpAndSettle();
}

void main() {
  testWidgets('sign in, visit every tab, open a team, its roster and chat, '
      'and step back', (t) async {
    // Signed out: the app opens on sign-in.
    final app = await pumpFullApp(t, signedIn: false);
    expect(find.byType(SignInScreen), findsOneWidget);

    // Signing in lands on Home.
    app.auth.setUser(testUser);
    await t.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);

    // All five tabs.
    final tabs = <String, Type>{
      'Discover': ExploreScreen,
      'Teams': TeamsScreen,
      'Schedule': ScheduleScreen,
      'Chats': InboxScreen,
      'Home': HomeScreen,
    };
    for (final e in tabs.entries) {
      await _tab(t, e.key);
      expect(find.byType(e.value), findsOneWidget, reason: e.key);
      expect(t.takeException(), isNull, reason: e.key);
    }

    // A team from the Teams tab.
    await _tab(t, 'Teams');
    await t.tap(find.text('Northside Flyers').first);
    await t.pumpAndSettle();
    expect(find.byType(TeamHomeScreen), findsOneWidget);

    // Its roster (the Roster tab opens the roster section, called members
    // on a team that keeps no separate roster), then its chat.
    final router = GoRouter.of(t.element(find.byType(NavigationBar)));
    await t.tap(find.text('Roster').first);
    await t.pumpAndSettle();
    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      anyOf(contains('roster'), contains('members')),
    );
    expect(t.takeException(), isNull);
    await t.tap(find.text('Chat').first);
    await t.pumpAndSettle();
    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      contains('chat'),
    );
    expect(t.takeException(), isNull);

    // Step back out to the list: the Teams tab, tapped again, returns to
    // its first page.
    await _tab(t, 'Teams');
    expect(find.byType(TeamsScreen), findsOneWidget);
    expect(find.byType(TeamHomeScreen), findsNothing);

    // The other tabs are intact, and we can get home.
    await _tab(t, 'Home');
    expect(find.byType(HomeScreen), findsOneWidget);
  });
}
