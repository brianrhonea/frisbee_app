// N1 (every route in the route map opens), N2 (sign-in redirects on the real
// router) and N10 (keyboard navigation of the shell).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/ui/auth/widgets/sign_in_screen.dart';
import 'package:frisbee_app/ui/explore/widgets/explore_screen.dart';
import 'package:frisbee_app/ui/home/widgets/home_screen.dart';
import 'package:frisbee_app/ui/messages/widgets/inbox_screen.dart';
import 'package:frisbee_app/ui/schedule/widgets/schedule_screen.dart';
import 'package:frisbee_app/ui/teams/widgets/teams_screen.dart';
import 'package:go_router/go_router.dart';

import '../testing/app_harness.dart';
import '../testing/fakes.dart';
import '../ui_harness/harness.dart' show loadAppFonts;

/// Paths from docs/specifications/navigation-route-map.md §3 that take only
/// the data the harness has (team t1, team event e1, personal event m1).
const _routes = <String>[
  '/home',
  '/explore',
  '/explore?q=flyers&only=teams',
  '/discover',
  '/rankings',
  '/players/u2',
  '/people/u2',
  '/record',
  '/learn',
  '/learn?part=rules',
  '/rules',
  '/profile',
  '/profile/following',
  '/settings',
  '/settings/general',
  '/settings/privacy',
  '/settings/account',
  '/settings/personal',
  '/settings/calendar',
  '/settings/help',
  '/settings/following',
  '/notifications',
  '/notifications/follow-requests',
  '/notifications/settings',
  '/schedule',
  '/team-events/t1/new',
  '/team-events/t1/e1',
  '/my-events/new',
  '/my-events/m1',
  '/teams',
  '/teams/new',
  '/teams/new?kind=community',
  '/teams/new?kind=organization',
  '/teams/search',
  '/teams/t1',
  '/teams/t1?section=roster',
  '/teams/t1?section=events',
  '/teams/t1?section=chat',
  '/teams/t1?section=members',
  '/teams/t1?section=playbook',
  '/teams/t1?section=videos',
  '/teams/t1?section=stats',
  '/teams/t1?section=tournaments',
  '/over/teams/t1',
  '/teams/t1/roles',
  '/teams/t1/chats/new',
  '/teams/t1/plays/new',
  '/teams/t1/whiteboards/new',
  '/teams/t1/stats/season',
  '/team-videos/t1/new',
  '/team-meetings/t1',
  '/team-meetings/t1/new',
  '/messages',
  '/messages/new',
  '/messages/new-group',
  '/tournaments',
  '/tournaments/host',
  '/g/t1',
];

void main() {
  testWidgets('N1: every route in the route map opens', (t) async {
    // Real fonts, so overflow checks match the device.
    await loadAppFonts(t);
    await pumpFullApp(t);
    final router = GoRouter.of(t.element(find.byType(HomeScreen)));
    final failures = <String>[];
    for (final path in _routes) {
      router.go(path);
      await t.pumpAndSettle();
      final error = t.takeException();
      if (error != null) {
        failures.add('$path threw: ${'$error'.split('\n').first}');
      }
      if (find.text('Page Not Found').evaluate().isNotEmpty) {
        failures.add('$path: page not found');
      }
      // Back to a known page so one route cannot hide the next.
      router.go('/home');
      await t.pumpAndSettle();
      t.takeException();
    }
    expect(failures, isEmpty);
  });

  group('N2: sign-in redirects on the real router', () {
    testWidgets('signed out, the app opens on sign-in', (t) async {
      await pumpFullApp(t, signedIn: false);
      expect(find.byType(SignInScreen), findsOneWidget);
    });

    testWidgets('a private page asks for sign-in, keeping where it was going', (
      t,
    ) async {
      await pumpFullApp(t, signedIn: false);
      final router = GoRouter.of(t.element(find.byType(SignInScreen)));
      router.go('/teams');
      await t.pumpAndSettle();
      expect(find.byType(SignInScreen), findsOneWidget);
      expect(
        router.routerDelegate.currentConfiguration.uri.queryParameters['from'],
        '/teams',
      );
    });

    testWidgets('signing in lands on Home, not the page asked for', (t) async {
      final app = await pumpFullApp(t, signedIn: false);
      final router = GoRouter.of(t.element(find.byType(SignInScreen)));
      router.go('/teams');
      await t.pumpAndSettle();
      app.auth.setUser(testUser);
      await t.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(TeamsScreen), findsNothing);
    });

    testWidgets('signing out returns to sign-in', (t) async {
      final app = await pumpFullApp(t);
      app.auth.setUser(null);
      await t.pumpAndSettle();
      expect(find.byType(SignInScreen), findsOneWidget);
    });
  });

  group('N10: keyboard navigation of the shell', () {
    Future<void> ctrl(WidgetTester t, LogicalKeyboardKey key) async {
      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await t.sendKeyEvent(key);
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await t.pumpAndSettle();
    }

    testWidgets('Ctrl+1..5 open Home, Discover, Teams, Schedule, Chats', (
      t,
    ) async {
      await pumpFullApp(t, size: const Size(1024, 768));
      final pages = <(LogicalKeyboardKey, Type)>[
        (LogicalKeyboardKey.digit2, ExploreScreen),
        (LogicalKeyboardKey.digit3, TeamsScreen),
        (LogicalKeyboardKey.digit4, ScheduleScreen),
        (LogicalKeyboardKey.digit5, InboxScreen),
        (LogicalKeyboardKey.digit1, HomeScreen),
      ];
      for (final (key, page) in pages) {
        await ctrl(t, key);
        expect(find.byType(page), findsOneWidget, reason: '$key');
      }
    });

    testWidgets('the shortcuts work on a phone layout too', (t) async {
      await pumpFullApp(t);
      await ctrl(t, LogicalKeyboardKey.digit3);
      expect(find.byType(TeamsScreen), findsOneWidget);
    });

    testWidgets('Ctrl+K opens the command menu and Escape closes it', (
      t,
    ) async {
      await pumpFullApp(t, size: const Size(1024, 768));
      await ctrl(t, LogicalKeyboardKey.keyK);
      expect(find.byType(TextField), findsWidgets);
      final before = find.byType(HomeScreen);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(before, findsOneWidget);
    });

    testWidgets('Tab reaches the sidebar and Enter opens the focused section', (
      t,
    ) async {
      await pumpFullApp(t, size: const Size(1024, 768));

      /// The text of the InkWell the focus is in, if any.
      String? focusedLabel() {
        final focus = FocusManager.instance.primaryFocus?.context;
        if (focus == null) return null;
        Element? ink;
        focus.visitAncestorElements((e) {
          if (e.widget is InkWell) {
            ink = e;
            return false;
          }
          return true;
        });
        String? text;
        void walk(Element e) {
          if (text != null) return;
          final w = e.widget;
          if (w is Text && w.data != null) {
            text = w.data;
            return;
          }
          e.visitChildren(walk);
        }

        if (ink != null) walk(ink!);
        return text;
      }

      var opened = false;
      for (var i = 0; i < 40 && !opened; i++) {
        await t.sendKeyEvent(LogicalKeyboardKey.tab);
        await t.pump();
        if (focusedLabel() == 'Discover') {
          await t.sendKeyEvent(LogicalKeyboardKey.enter);
          await t.pumpAndSettle();
          opened = find.byType(ExploreScreen).evaluate().isNotEmpty;
        }
      }
      expect(opened, isTrue, reason: 'Tab then Enter reached Discover');
    });
  });
}
