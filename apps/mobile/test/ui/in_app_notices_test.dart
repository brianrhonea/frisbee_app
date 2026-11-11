import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/notification.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/notifications/view_models/in_app_notices_viewmodel.dart';
import 'package:frisbee_app/ui/notifications/widgets/in_app_notice_bubble.dart';

import '../testing/fakes.dart';

AppNotification _dm({int count = 1, bool read = false, String id = 'c1'}) =>
    AppNotification(
      id: id,
      category: NotificationCategory.directMessages,
      title: 'Pat Player',
      body: count == 1 ? 'Throwing tonight?' : '$count new messages',
      route: '/messages/$id',
      count: count,
      read: read,
    );

void main() {
  late FakeNotificationRepository repo;
  late InAppNoticesViewModel vm;
  late String here;
  final opened = <String>[];

  setUp(() {
    here = '/home';
    opened.clear();
    repo = FakeNotificationRepository(feed: [_dm(id: 'old')]);
  });

  Future<void> pump(WidgetTester tester) async {
    vm = InAppNoticesViewModel(
      authRepository: FakeAuthRepository(user: testUser),
      notificationRepository: repo,
      currentLocation: () => here,
    );
    addTearDown(vm.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: InAppNoticeBubble(
          viewModel: vm,
          onOpen: opened.add,
          child: const Scaffold(body: Text('page')),
        ),
      ),
    );
    await tester.pump();
  }

  void arrive(AppNotification n) {
    repo.feed
      ..removeWhere((e) => e.id == n.id)
      ..insert(0, n);
    repo.emit();
  }

  testWidgets('what was there already stays quiet; new ones show and go', (
    tester,
  ) async {
    await pump(tester);
    expect(vm.current, isNull);

    arrive(_dm());
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.text('Pat Player  Throwing tonight?', findRichText: true),
      findsOne,
    );

    await tester.pump(vm.showFor);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(vm.current, isNull);
    expect(find.textContaining('Pat Player', findRichText: true), findsNothing);
  });

  testWidgets('more in the same chat updates the bubble in place', (
    tester,
  ) async {
    await pump(tester);
    arrive(_dm());
    await tester.pump();
    arrive(_dm(count: 2));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('2 new messages', findRichText: true), findsOne);
    expect(find.textContaining('Pat Player', findRichText: true), findsOne);
    await tester.pump(vm.showFor);
  });

  testWidgets('nothing shows for the page you are on', (tester) async {
    here = '/messages/c1';
    await pump(tester);
    arrive(_dm());
    await tester.pump();
    expect(vm.current, isNull);
  });

  testWidgets('tapping opens it and puts the entry away', (tester) async {
    await pump(tester);
    arrive(_dm());
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.textContaining('Pat Player', findRichText: true));
    await tester.pump();
    expect(opened, ['/messages/c1']);
    expect(repo.feed.where((n) => n.id == 'c1'), isEmpty);
    expect(vm.current, isNull);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('read elsewhere takes it down', (tester) async {
    await pump(tester);
    arrive(_dm());
    await tester.pump();
    expect(vm.current, isNotNull);
    arrive(_dm(read: true));
    await tester.pump();
    expect(vm.current, isNull);
    await tester.pump(vm.showFor);
  });
}
