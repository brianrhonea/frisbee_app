// REL2: pulling Home down to refresh keeps the posts on screen, ends the
// spinner only when the new first page is in, and feels native on iOS.
import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoSliverRefreshControl;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/user_post.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/core/ui/layout.dart';
import 'package:frisbee_app/ui/home/view_models/home_viewmodel.dart';
import 'package:frisbee_app/ui/home/widgets/home_screen.dart';
import 'package:frisbee_app/ui/posts/view_models/community_feed.dart';
import 'package:frisbee_app/ui/posts/view_models/home_feed.dart';

import '../testing/fakes.dart';
import '../testing/social_fakes.dart';

/// Holds the author query's first answer until [gate] completes, as a
/// slow connection would.
class _GatedUserPosts extends FakeUserPostRepository {
  Completer<void>? gate;

  @override
  Stream<List<UserPost>> watchPostsByAuthors(
    List<String> authorIds, {
    int limit = 50,
    Set<String> includePrivate = const {},
  }) async* {
    await gate?.future;
    yield* super.watchPostsByAuthors(
      authorIds,
      limit: limit,
      includePrivate: includePrivate,
    );
  }
}

UserPost _post(String id, DateTime at, {String author = 'sam'}) => UserPost(
  id: id,
  authorId: author,
  authorName: author == testUser.uid ? 'Alex' : 'Sam',
  body: 'Post $id',
  createdAt: at,
);

void main() {
  final now = DateTime(2026, 10, 28, 9);

  group('HomeFeed.refresh', () {
    late _GatedUserPosts userPosts;
    late FakeFollowRepository follows;
    late List<HomeFeed> feeds;

    HomeFeed make({Duration timeout = const Duration(seconds: 10)}) {
      final f = HomeFeed(
        uid: testUser.uid,
        followRepository: follows,
        teamRepository: FakeTeamRepository(),
        teamPostRepository: FakeTeamPostRepository(),
        userPostRepository: userPosts,
        refreshTimeout: timeout,
      );
      feeds.add(f);
      return f;
    }

    setUp(() {
      userPosts = _GatedUserPosts();
      follows = FakeFollowRepository();
      feeds = [];
      userPosts.posts.add(_post('mine', now, author: testUser.uid));
    });

    tearDown(() {
      for (final f in feeds) {
        f.dispose();
      }
    });

    test('the posts stay while it loads, then swap in', () async {
      final f = make();
      await pumpEventQueue();
      expect(f.items.map((i) => i.id), ['user/mine']);

      final lengths = <int>[];
      f.addListener(() => lengths.add(f.items.length));
      userPosts.posts.add(
        _post('fresh', now.add(const Duration(minutes: 1)), author: 'sam'),
      );
      userPosts.posts.add(
        _post(
          'mine2',
          now.add(const Duration(minutes: 2)),
          author: testUser.uid,
        ),
      );
      userPosts.gate = Completer<void>();
      var done = false;
      final refreshing = f.refresh().then((_) => done = true);
      await pumpEventQueue();

      expect(done, isFalse, reason: 'not before the first page is in');
      expect(f.items.map((i) => i.id), ['user/mine'], reason: 'old posts stay');
      expect(f.loaded, isTrue, reason: 'no loading skeleton');

      userPosts.gate!.complete();
      await refreshing;
      expect(done, isTrue);
      expect(f.items.map((i) => i.id), ['user/mine2', 'user/mine']);
      expect(
        lengths.every((n) => n >= 1),
        isTrue,
        reason: 'never blank in between: $lengths',
      );
    });

    test('it gives up waiting after the timeout, and swaps later', () async {
      final f = make(timeout: const Duration(milliseconds: 50));
      await pumpEventQueue();
      userPosts.gate = Completer<void>();
      userPosts.posts.add(
        _post(
          'late',
          now.add(const Duration(minutes: 1)),
          author: testUser.uid,
        ),
      );
      await f.refresh();
      // The spinner ended; the old posts are still there.
      expect(f.items.map((i) => i.id), ['user/mine']);
      userPosts.gate!.complete();
      await pumpEventQueue();
      expect(f.items.map((i) => i.id), ['user/late', 'user/mine']);
    });

    test('a second refresh while one waits finishes both', () async {
      final f = make();
      await pumpEventQueue();
      userPosts.gate = Completer<void>();
      final first = f.refresh();
      await pumpEventQueue();
      final second = f.refresh();
      await pumpEventQueue();
      userPosts.gate!.complete();
      await Future.wait([first, second]);
      expect(f.items.map((i) => i.id), ['user/mine']);
    });

    test('older pages are dropped by a refresh', () async {
      final f = make();
      await pumpEventQueue();
      await f.refresh();
      expect(f.hasMore, isFalse);
      expect(f.items, hasLength(1));
    });

    test('refreshing after dispose does nothing', () async {
      final f = make();
      await pumpEventQueue();
      f.dispose();
      await f.refresh();
      feeds.remove(f);
    });
  });

  group('CommunityFeed.refresh', () {
    late FakeUserPostRepository posts;
    late CommunityFeed feed;

    CommunityFeed make({Duration timeout = const Duration(seconds: 10)}) =>
        feed = CommunityFeed(
          userPostRepository: posts,
          refreshTimeout: timeout,
        );

    setUp(() {
      posts = FakeUserPostRepository();
      posts.posts.addAll([
        _post('a', now),
        _post('b', now.subtract(const Duration(hours: 1))),
        _post('c', now.add(const Duration(hours: 1))),
      ]);
      posts.communityPages[null] = (ids: ['a', 'b'], next: 5);
    });

    tearDown(() => feed.dispose());

    test('the posts stay until the new page and its posts are in', () async {
      make().start();
      await pumpEventQueue();
      expect(feed.posts.map((p) => p.id), ['a', 'b']);

      posts.communityPages[null] = (ids: ['c', 'a'], next: null);
      posts.idsGate = Completer<void>();
      final seen = <List<String>>[];
      feed.addListener(() => seen.add([for (final p in feed.posts) p.id]));
      var done = false;
      final refreshing = feed.refresh().then((_) => done = true);
      await pumpEventQueue();

      expect(done, isFalse);
      expect(feed.posts.map((p) => p.id), ['a', 'b']);
      expect(feed.loaded, isTrue);
      expect(feed.hasMore, isTrue, reason: 'cursor kept until the swap');

      posts.idsGate!.complete();
      await refreshing;
      expect(feed.posts.map((p) => p.id), ['c', 'a']);
      expect(feed.hasMore, isFalse);
      expect(feed.loaded, isTrue);
      expect(seen.every((ids) => ids.isNotEmpty), isTrue, reason: '$seen');
    });

    test('a failed refresh keeps the posts and says so', () async {
      make().start();
      await pumpEventQueue();
      posts.communityError = Exception('offline');
      await feed.refresh();
      expect(feed.posts.map((p) => p.id), ['a', 'b']);
      expect(feed.error, isTrue);

      posts.communityError = null;
      await feed.refresh();
      expect(feed.error, isFalse);
      expect(feed.posts.map((p) => p.id), ['a', 'b']);
    });

    test('it stops waiting after the timeout, and swaps when it can', () async {
      make(timeout: const Duration(milliseconds: 50)).start();
      await pumpEventQueue();
      posts.communityPages[null] = (ids: ['c'], next: null);
      posts.idsGate = Completer<void>();
      await feed.refresh();
      expect(feed.posts.map((p) => p.id), ['a', 'b']);
      posts.idsGate!.complete();
      await pumpEventQueue();
      expect(feed.posts.map((p) => p.id), ['c']);
    });

    test('before the tab is opened it does nothing', () async {
      make();
      await feed.refresh();
      expect(posts.communityRequests, isEmpty);
    });
  });

  group('PageScroll', () {
    Widget host({required Future<void> Function() onRefresh}) => MaterialApp(
      theme: AppTheme.light.copyWith(platform: defaultTargetPlatform),
      home: Scaffold(
        body: PageScroll(
          onRefresh: onRefresh,
          children: [
            for (var i = 0; i < 30; i++)
              SizedBox(height: 80, child: Text('$i')),
          ],
        ),
      ),
    );

    /// Runs [body] as [platform], put back before the test's checks.
    void onPlatform(
      String name,
      TargetPlatform platform,
      Future<void> Function(WidgetTester) body,
    ) => testWidgets(name, (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await body(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    onPlatform(
      'Android pulls with the Material indicator',
      TargetPlatform.android,
      (tester) async {
        var calls = 0;
        await tester.pumpWidget(host(onRefresh: () async => calls++));
        expect(find.byType(RefreshIndicator), findsOneWidget);
        expect(
          find.byType(CupertinoSliverRefreshControl, skipOffstage: false),
          findsNothing,
        );
        await tester.fling(find.byType(PageScroll), const Offset(0, 400), 1000);
        await tester.pumpAndSettle();
        expect(calls, 1);
      },
    );

    onPlatform(
      'iOS pulls with the native sliver control and bounces',
      TargetPlatform.iOS,
      (tester) async {
        var calls = 0;
        await tester.pumpWidget(host(onRefresh: () async => calls++));
        expect(
          find.byType(CupertinoSliverRefreshControl, skipOffstage: false),
          findsOneWidget,
        );
        expect(find.byType(RefreshIndicator), findsNothing);
        final scroll = tester.widget<CustomScrollView>(
          find.byType(CustomScrollView),
        );
        expect(scroll.physics, isA<AlwaysScrollableScrollPhysics>());

        await tester.drag(find.byType(PageScroll), const Offset(0, 300));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();
        expect(calls, 1);
        // Back at the top where the pull began.
        final position = tester
            .state<ScrollableState>(find.byType(Scrollable))
            .position;
        expect(position.pixels, 0);
      },
    );

    onPlatform(
      'a page without onRefresh has neither control',
      TargetPlatform.iOS,
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light.copyWith(platform: defaultTargetPlatform),
            home: const Scaffold(body: PageScroll(children: [Text('x')])),
          ),
        );
        expect(find.byType(RefreshIndicator), findsNothing);
        expect(
          find.byType(CupertinoSliverRefreshControl, skipOffstage: false),
          findsNothing,
        );
        expect(find.text('x'), findsOneWidget);
      },
    );

    testWidgets('the scroll controller still drives either layout', (
      tester,
    ) async {
      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        debugDefaultTargetPlatformOverride = platform;
        final controller = ScrollController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light.copyWith(platform: defaultTargetPlatform),
            home: Scaffold(
              body: PageScroll(
                controller: controller,
                onRefresh: () async {},
                children: [
                  for (var i = 0; i < 30; i++)
                    SizedBox(height: 80, child: Text('$i')),
                ],
              ),
            ),
          ),
        );
        controller.jumpTo(200);
        await tester.pump();
        expect(controller.offset, 200, reason: '$platform');
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('Home screen refresh', () {
    testWidgets('posts stay and the scroll position holds during a refresh', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final userPosts = _GatedUserPosts();
      for (var i = 0; i < 8; i++) {
        userPosts.posts.add(
          _post(
            'p$i',
            now.subtract(Duration(minutes: i)),
            author: testUser.uid,
          ),
        );
      }
      final vm = await tester.runAsync(() async {
        final vm = HomeViewModel(
          authRepository: FakeAuthRepository(user: testUser),
          teamRepository: FakeTeamRepository(),
          eventRepository: FakeEventRepository(),
          teamPostRepository: FakeTeamPostRepository(),
          followRepository: FakeFollowRepository(),
          userPostRepository: userPosts,
          filePicker: FakeFilePickerService(),
          clock: () => now,
        );
        await pumpEventQueue();
        return vm;
      });
      addTearDown(vm!.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light.copyWith(platform: defaultTargetPlatform),
          home: HomeScreen(viewModel: vm),
        ),
      );
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: find.byType(UnderlineTabs),
          matching: find.text('Following'),
        ),
      );
      await tester.pump();
      expect(find.text('Post p0'), findsOneWidget);

      final scrollable = find.byType(Scrollable).first;
      await tester.drag(scrollable, const Offset(0, -150));
      await tester.pump();
      final before = tester.state<ScrollableState>(scrollable).position.pixels;
      expect(before, greaterThan(0));

      userPosts.gate = Completer<void>();
      Future<void>? refreshing;
      await tester.runAsync(() async {
        refreshing = vm.refreshFeed();
        await pumpEventQueue();
      });
      await tester.pump();
      // Mid-refresh: no empty state, no skeleton, nothing moved.
      expect(vm.posts, hasLength(8));
      expect(find.textContaining('No posts yet'), findsNothing);
      expect(tester.state<ScrollableState>(scrollable).position.pixels, before);

      await tester.runAsync(() async {
        userPosts.gate!.complete();
        await refreshing;
        await pumpEventQueue();
      });
      await tester.pump();
      expect(vm.posts, hasLength(8));
      expect(tester.state<ScrollableState>(scrollable).position.pixels, before);
      expect(tester.takeException(), isNull);
    });
  });
}
