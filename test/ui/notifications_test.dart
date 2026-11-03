import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/follow.dart';
import 'package:frisbee_app/domain/models/notification.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/notifications/view_models/notification_settings_viewmodel.dart';
import 'package:frisbee_app/ui/notifications/view_models/notifications_viewmodel.dart';
import 'package:frisbee_app/ui/notifications/widgets/notification_settings_screen.dart';
import 'package:frisbee_app/ui/notifications/widgets/notifications_screen.dart';
import 'package:frisbee_app/ui/profile/view_models/profile_viewmodel.dart';
import 'package:go_router/go_router.dart';

import '../testing/fakes.dart';
import '../testing/social_fakes.dart';

AppNotification note(String id, {bool read = false, String? route}) =>
    AppNotification(
      id: id,
      category: NotificationCategory.eventChanges,
      title: 'Title $id',
      body: 'Body $id',
      route: route,
      createdAt: DateTime(2026, 10, 30, 9),
      read: read,
    );

void main() {
  group('NotificationPreferences', () {
    test('everything is on by default', () {
      const p = NotificationPreferences();
      for (final c in NotificationCategory.values) {
        expect(p.isOn(c), isTrue);
        expect(p.isOnFor(c, 't1'), isTrue);
      }
    });

    test('a team override wins over the default', () {
      final p = NotificationPreferences.fromMap({
        'categories': {'chat': false, 'eventChanges': true},
        'teams': {
          't1': {'chat': true, 'eventChanges': false},
          't2': {'bogus': true},
        },
        'mutedRooms': ['t1/general'],
      });
      expect(p.isOn(NotificationCategory.chat), isFalse);
      expect(p.isOnFor(NotificationCategory.chat, 't1'), isTrue);
      expect(p.isOnFor(NotificationCategory.chat, 't2'), isFalse);
      expect(p.isOnFor(NotificationCategory.eventChanges, 't1'), isFalse);
      expect(p.hasOverrides('t1'), isTrue);
      // Unknown categories are dropped, so t2 has no overrides at all.
      expect(p.hasOverrides('t2'), isFalse);
      expect(p.isRoomMuted('t1', 'general'), isTrue);
      expect(p.isRoomMuted('t1', 'caps'), isFalse);
    });
  });

  test('NotificationsViewModel counts unread and marks entries read', () async {
    final repo = FakeNotificationRepository(
      feed: [note('a'), note('b'), note('c', read: true)],
    );
    final vm = NotificationsViewModel(
      notificationRepository: repo,
      authRepository: FakeAuthRepository(user: testUser),
    );
    await pumpEventQueue();
    expect(vm.unreadCount, 2);
    await vm.open.execute(vm.items.first);
    await pumpEventQueue();
    expect(vm.unreadCount, 1);
    await vm.markAllRead.execute();
    await pumpEventQueue();
    expect(vm.unreadCount, 0);
    await vm.clearAll.execute();
    await pumpEventQueue();
    expect(vm.items, isEmpty);
    vm.dispose();
  });

  group('NotificationsScreen', () {
    Future<FakeNotificationRepository> pump(
      WidgetTester tester,
      List<AppNotification> feed, {
      FakeFollowRepository? follows,
    }) async {
      final repo = FakeNotificationRepository(feed: feed);
      final vm = NotificationsViewModel(
        notificationRepository: repo,
        authRepository: FakeAuthRepository(user: testUser),
        followRepository: follows,
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
      await tester.pumpWidget(
        MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      );
      await tester.pumpAndSettle();
      return repo;
    }

    testWidgets('a new follower can be followed back', (tester) async {
      final follows = FakeFollowRepository();
      final repo = await pump(tester, [
        AppNotification.fromMap('f1', {
          'category': 'social',
          'title': 'Riley started following you',
          'route': '/target',
          'read': false,
          'followBack': {'uid': 'u9', 'name': 'Riley', 'photoUrl': null},
        }),
      ], follows: follows);
      expect(find.text('Riley started following you'), findsOneWidget);
      await tester.tap(find.text('Follow back'));
      await tester.pumpAndSettle();
      // Followed, still on the list, and read.
      final mine = await follows.watchFollows(testUser.uid).first;
      expect(mine.map((f) => f.key), [FollowTarget.userKey('u9')]);
      expect(mine.single.target.name, 'Riley');
      await tester.pumpAndSettle();
      expect(find.text('Following'), findsOneWidget);
      expect(find.text('Follow back'), findsNothing);
      expect(find.text('Target page'), findsNothing);
      expect(repo.feed.single.read, isTrue);
    });

    testWidgets('no Follow back for someone already followed', (tester) async {
      final follows = FakeFollowRepository();
      await follows.follow(
        testUser.uid,
        const FollowTarget.user('u9', 'Riley'),
      );
      await pump(tester, [
        AppNotification.fromMap('f1', {
          'category': 'social',
          'title': 'Riley started following you',
          'followBack': {'uid': 'u9', 'name': 'Riley'},
        }),
      ], follows: follows);
      expect(find.text('Follow back'), findsNothing);
      expect(find.text('Following'), findsOneWidget);
    });

    testWidgets('shows an empty state', (tester) async {
      await pump(tester, const []);
      expect(find.text('No notifications'), findsOneWidget);
    });

    testWidgets('tapping an entry marks it read and opens it', (tester) async {
      final repo = await pump(tester, [note('a', route: '/target')]);
      expect(find.text('Title a'), findsOneWidget);
      expect(find.text('Mark all read'), findsOneWidget);
      await tester.tap(find.text('Title a'));
      await tester.pumpAndSettle();
      expect(find.text('Target page'), findsOneWidget);
      expect(repo.feed.single.read, isTrue);
    });
  });

  group('NotificationSettingsScreen', () {
    Future<FakeNotificationRepository> pump(
      WidgetTester tester, {
      PushStatus status = PushStatus.notDetermined,
    }) async {
      final repo = FakeNotificationRepository(status: status);
      final teams = FakeTeamRepository()
        ..teams['t1'] = teamWith({'u1': TeamRole.owner});
      final vm = NotificationSettingsViewModel(
        notificationRepository: repo,
        teamRepository: teams,
        authRepository: FakeAuthRepository(user: testUser),
      );
      addTearDown(vm.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: NotificationSettingsScreen(viewModel: vm),
        ),
      );
      await tester.pumpAndSettle();
      return repo;
    }

    testWidgets('turns on push for this device', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Turn on'));
      await tester.pumpAndSettle();
      expect(find.text('Push notifications are on'), findsOneWidget);
    });

    testWidgets('explains that Windows has no push', (tester) async {
      await pump(tester, status: PushStatus.unsupported);
      expect(
        find.text("Push notifications aren't available on Windows"),
        findsOneWidget,
      );
    });

    testWidgets('turns a category off for every team', (tester) async {
      final repo = await pump(tester);
      await tester.tap(find.text('Team chat'));
      await tester.pumpAndSettle();
      expect(repo.prefs.isOn(NotificationCategory.chat), isFalse);
    });

    testWidgets('overrides one team and resets it', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repo = await pump(tester);
      expect(find.text('Using your defaults'), findsOneWidget);
      await tester.tap(find.text('Team'));
      await tester.pumpAndSettle();
      final teamSwitch = find.descendant(
        of: find.byType(ExpansionTile),
        matching: find.text('Event reminders'),
      );
      await tester.tap(teamSwitch);
      await tester.pumpAndSettle();
      expect(
        repo.prefs.isOnFor(NotificationCategory.eventReminders, 't1'),
        isFalse,
      );
      expect(repo.prefs.isOn(NotificationCategory.eventReminders), isTrue);
      expect(find.text('Custom for this team'), findsOneWidget);
      await tester.tap(find.text('Use my defaults'));
      await tester.pumpAndSettle();
      expect(repo.prefs.hasOverrides('t1'), isFalse);
    });
  });

  test('signing out unregisters this device first', () async {
    final repo = FakeNotificationRepository();
    final vm = ProfileViewModel(
      authRepository: FakeAuthRepository(user: testUser),
      themeRepository: FakeThemeRepository(),
      notificationRepository: repo,
    );
    await vm.signOut.execute();
    expect(repo.unregistered, ['u1']);
    vm.dispose();
  });
}
