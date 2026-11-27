// N1 (unknown routes) and N6 (every link a notification or share can open
// lands on the right screen, warm and from a cold start), on the real router
// over fakes.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/routing/open_link.dart';
import 'package:frisbee_app/ui/home/widgets/home_screen.dart';
import 'package:frisbee_app/utils/invite_links.dart';
import 'package:go_router/go_router.dart';

import '../testing/app_harness.dart';
import '../testing/fakes.dart';
import 'link_helpers.dart';

/// Every `route` the notification code can send (firebase/functions/src/
/// notifications/*.ts and apps/api/src/moderation/service.ts), with the
/// page it must open. Ids are the harness's team t1, event e1, personal
/// event m1; the others have no data, so they show the page's own empty or
/// error state, which still counts as opening the right page.
const _notificationRoutes = <(String, String)>[
  ('/teams/t1/chats/r1', 'chatRoom'),
  ('/messages/c1', 'directChat'),
  ('/messages', 'inbox'),
  ('/teams/t1/whiteboards/p1', 'whiteboard'),
  ('/teams/t1/plays/p1', 'play'),
  ('/team-videos/t1/v1', 'video'),
  ('/teams/t1/members', 'team'),
  ('/teams/t1', 'team'),
  ('/teams', 'teams'),
  ('/settings/calendar', 'calendars'),
  ('/team-meetings/t1/m1', 'meeting'),
  ('/teams/t1/events', 'team'),
  ('/posts/p1', 'post'),
  ('/players/u2', 'player'),
  ('/settings/follow-requests', 'followRequests'),
  ('/tournaments/x1', 'tournament'),
  ('/tournaments/x1?tab=teams', 'tournament'),
  ('/tournaments/x1?tab=schedule', 'tournament'),
  ('/tournaments/x1?tab=results', 'tournament'),
  ('/tournaments/x1/respond?team=t1', 'respond'),
  ('/tournaments/x1/live-draft/d1', 'liveDraft'),
  ('/my-events/m1', 'myEvent'),
  ('/schedule', 'schedule'),
  ('/team-events/t1/e1', 'teamEvent'),
  // A moderation warning's link; the guidelines live on the website, so
  // the app lands on Settings, which links to them.
  ('/guidelines', 'settings'),
];

Type _page(String name) => notificationPages[name]!;

void main() {
  group('N1: unknown routes show the not-found page', () {
    for (final path in [
      '/nope',
      '/teams/t1/nope/deeper',
      '/tournaments/x1/nope',
      '/settings/nope',
      '/messages/c1/nope',
    ]) {
      testWidgets(path, (t) async {
        await pumpFullApp(t);
        final router = GoRouter.of(t.element(find.byType(HomeScreen)));
        router.go(path);
        await t.pumpAndSettle();
        expect(find.text('Page Not Found'), findsOneWidget);
        // Not a crash, and the app is still usable.
        expect(t.takeException(), isNull);
        router.go('/home');
        await t.pumpAndSettle();
        expect(find.byType(HomeScreen), findsOneWidget);
      });
    }

    testWidgets('signed out, an unknown route still asks for sign-in', (
      t,
    ) async {
      await pumpFullApp(t, signedIn: false);
      final router = GoRouter.of(t.element(find.byType(Scaffold).first));
      router.go('/nope');
      await t.pumpAndSettle();
      expect(find.text('Page Not Found'), findsNothing);
    });
  });

  group('N6: notification links (a tap while the app runs)', () {
    for (final (route, page) in _notificationRoutes) {
      testWidgets('$route opens $page', (t) async {
        await pumpFullApp(t);
        final router = GoRouter.of(t.element(find.byType(HomeScreen)));
        router.openFromOutside(route);
        await t.pumpAndSettle();
        expectFound(t, route);
        expect(find.byType(_page(page)), findsOneWidget, reason: route);
      });
    }
  });

  group('N6: back from a notification link', () {
    // The app opens on Home; once sign-in settles, main.dart hands the
    // tapped notification's route to openFromOutside.
    for (final (route, page) in _notificationRoutes) {
      testWidgets('$route opens $page, with a way back', (t) async {
        await pumpFullApp(t);
        final router = GoRouter.of(t.element(find.byType(HomeScreen)));
        router.openFromOutside(route);
        await t.pumpAndSettle();
        expect(find.byType(_page(page)), findsOneWidget, reason: route);
        // Back never leaves the app on a blank page: either a page below
        // (the parent) or the tabs.
        var steps = 0;
        while (router.canPop() && steps++ < 4) {
          router.pop();
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
        }
        expect(find.text('Page Not Found'), findsNothing);
        expect(find.byType(Scaffold), findsWidgets);
      });
    }

    testWidgets('a post opened from a notification goes back to Home', (
      t,
    ) async {
      await pumpFullApp(t);
      final router = GoRouter.of(t.element(find.byType(HomeScreen)));
      router.openFromOutside('/posts/p1');
      await t.pumpAndSettle();
      router.pop();
      await t.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
    });
  });

  group('N6: cold start from a link (the initial route)', () {
    final links = <(String, String)>[
      (InviteLinks.join('ABC234').path, 'invite'),
      (InviteLinks.group('t1').path, 'team'),
      (InviteLinks.post('p1').path, 'post'),
      (InviteLinks.tournament('x1').path, 'tournament'),
      ('/teams/t1?section=roster', 'team'),
    ];
    for (final (link, page) in links) {
      testWidgets('$link opens $page', (t) async {
        t.platformDispatcher.defaultRouteNameTestValue = link;
        addTearDown(t.platformDispatcher.clearDefaultRouteNameTestValue);
        await pumpFullApp(t, expectHome: false);
        expectFound(t, link);
        expect(find.byType(_page(page)), findsOneWidget, reason: link);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('the app scheme opens the same page', (t) async {
      t.platformDispatcher.defaultRouteNameTestValue =
          'stall10://open/teams/t1';
      addTearDown(t.platformDispatcher.clearDefaultRouteNameTestValue);
      await pumpFullApp(t, expectHome: false);
      expectFound(t, 'stall10://open/teams/t1');
      expect(find.byType(_page('team')), findsOneWidget);
    });

    testWidgets('an invite link carries on after sign-in', (t) async {
      final link = InviteLinks.join('ABC234').path;
      t.platformDispatcher.defaultRouteNameTestValue = link;
      addTearDown(t.platformDispatcher.clearDefaultRouteNameTestValue);
      final app = await pumpFullApp(t, signedIn: false);
      app.auth.setUser(testUser);
      await t.pumpAndSettle();
      expect(find.byType(_page('invite')), findsOneWidget);
    });
  });

  testWidgets('a notification that launched a signed-out app opens after '
      'sign-in (main.dart holds it until then)', (t) async {
    final app = await pumpFullApp(t, signedIn: false);
    final router = GoRouter.of(t.element(find.byType(Scaffold).first));
    app.auth.setUser(testUser);
    await t.pumpAndSettle();
    router.openFromOutside('/teams/t1/chats/r1');
    await t.pumpAndSettle();
    expect(find.byType(_page('chatRoom')), findsOneWidget);
  });
}
