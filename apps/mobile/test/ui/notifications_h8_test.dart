// H8: the notifications list with All / Unread chips, Today and Earlier
// groups and unread dots. Parity: website notifications page.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/notification.dart';
import 'package:frisbee_app/ui/notifications/view_models/notifications_viewmodel.dart';
import 'package:frisbee_app/ui/notifications/widgets/notifications_screen.dart';
import 'package:go_router/go_router.dart';

import '../testing/fakes.dart';
import '../ui_harness/harness.dart';
import 'notifications_test.dart' show note;

void main() {
  final today = DateTime.now();

  AppNotification at(String id, DateTime when, {bool read = false}) =>
      AppNotification(
        id: id,
        category: NotificationCategory.eventChanges,
        title: 'Title $id',
        body: 'Body $id',
        route: '/target',
        createdAt: when,
        read: read,
      );

  Widget screen(List<AppNotification> feed) {
    final vm = NotificationsViewModel(
      notificationRepository: FakeNotificationRepository(feed: feed),
      authRepository: FakeAuthRepository(user: testUser),
    );
    addTearDown(vm.dispose);
    final router = GoRouter(
      initialLocation: '/notifications',
      routes: [
        GoRoute(
          path: '/notifications',
          builder: (_, _) => NotificationsScreen(viewModel: vm),
        ),
        GoRoute(
          path: '/target',
          builder: (_, _) => const Scaffold(body: Text('Target page')),
        ),
      ],
    );
    addTearDown(router.dispose);
    return Router(
      routerDelegate: router.routerDelegate,
      routeInformationParser: router.routeInformationParser,
      routeInformationProvider: router.routeInformationProvider,
      backButtonDispatcher: RootBackButtonDispatcher(),
    );
  }

  final feed = [
    at('a', today),
    at('b', today, read: true),
    at('c', today.subtract(const Duration(days: 3))),
  ];

  testWidgets('chips, Today and Earlier groups and unread dots', (
    tester,
  ) async {
    await pumpInApp(tester, screen(feed), width: 390, height: 800);
    await tester.pumpAndSettle();
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Unread 2'), findsOneWidget);
    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('EARLIER'), findsOneWidget);
    expect(find.byIcon(Icons.circle), findsNWidgets(2));
  });

  testWidgets('Unread keeps only unread entries; All brings them back', (
    tester,
  ) async {
    await pumpInApp(tester, screen(feed), width: 390, height: 800);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unread 2'));
    await tester.pumpAndSettle();
    expect(find.text('Title a'), findsOneWidget);
    expect(find.text('Title b'), findsNothing);
    expect(find.text('Title c'), findsOneWidget);
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(find.text('Title b'), findsOneWidget);
  });

  testWidgets('tapping an entry still opens its target', (tester) async {
    await pumpInApp(tester, screen(feed), width: 390, height: 800);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Title a'));
    await tester.pumpAndSettle();
    expect(find.text('Target page'), findsOneWidget);
  });

  for (final theme in GoldenTheme.values) {
    testWidgets('meets accessibility guidelines, ${theme.name}', (
      tester,
    ) async {
      await pumpInApp(
        tester,
        screen(feed),
        theme: theme,
        width: 390,
        height: 800,
      );
      await tester.pumpAndSettle();
      await expectAccessible(tester);
    });
  }

  testWidgets('fits at text scale 2.0', (tester) async {
    await expectNoOverflowWithLargeText(
      tester,
      screen([note('a'), note('b', read: true)]),
      width: 390,
      height: 800,
    );
  });

  testWidgets(
    'goldens at phone and tablet widths, light and dark',
    skip: goldenSkip != null,
    (tester) async {
      await expectGoldens(
        tester,
        screen([
          AppNotification(
            id: 'a',
            category: NotificationCategory.eventChanges,
            title: 'Practice moved to 7 pm',
            body: 'Thursday, Riverside field 2',
            createdAt: DateTime(today.year, today.month, today.day, 9),
          ),
          AppNotification(
            id: 'b',
            category: NotificationCategory.eventChanges,
            title: 'New in Northside Flyers',
            body: 'Cam: See everyone at 6.',
            createdAt: DateTime(today.year, today.month, today.day, 8, 15),
            read: true,
          ),
        ]),
        'notifications_h8',
        widths: const [GoldenWidth.phone, GoldenWidth.tablet],
        height: 800,
      );
    },
  );
}
