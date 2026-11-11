import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:frisbee_app/data/repositories/auth/auth_repository.dart';
import 'package:frisbee_app/domain/models/team_event.dart';
import 'package:frisbee_app/domain/models/user_post.dart';
import 'package:frisbee_app/routing/routes.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/posts/view_models/post_actions.dart';
import 'package:frisbee_app/ui/posts/widgets/post_widgets.dart';
import 'package:frisbee_app/utils/result.dart';

import '../testing/fakes.dart';
import '../testing/social_fakes.dart';

void main() {
  final event = SharedEvent(
    eventId: 'e1',
    title: 'Fall showcase',
    type: EventType.game,
    startsAt: DateTime(2026, 11, 7, 18),
    endsAt: DateTime(2026, 11, 7, 20),
    location: 'City Park',
    teamId: 't1',
    teamName: 'Northside Flyers',
  );

  UserPost post(String author, SharedEvent e) => UserPost(
    id: 'p1',
    authorId: author,
    authorName: 'Pat',
    body: 'Come watch!',
    event: e,
    createdAt: DateTime(2026, 11, 2, 9),
  );

  group('SharedEvent', () {
    test('round-trips through a post', () {
      final map = post('u1', event).toEditableMap();
      expect(map['kind'], 'event');
      final back = UserPost.fromMap('p1', {...map, 'authorId': 'u1'});
      expect(back.kind, UserPostKind.event);
      expect(back.hasContent, isTrue);
      final e = back.event!;
      expect(e.eventId, 'e1');
      expect(e.title, 'Fall showcase');
      expect(e.type, EventType.game);
      expect(e.startsAt, DateTime(2026, 11, 7, 18));
      expect(e.endsAt, DateTime(2026, 11, 7, 20));
      expect(e.location, 'City Park');
      expect(e.teamId, 't1');
      expect(e.teamName, 'Northside Flyers');
    });

    test('a personal event leaves out the team, end and place', () {
      final map = SharedEvent.of(
        TeamEvent(id: 'm1', title: 'Run', startsAt: DateTime(2026, 11, 3)),
      ).toMap();
      expect(map.keys, ['eventId', 'title', 'type', 'startsAt']);
    });

    test('a repost round-trips, pointing at the original', () {
      final repost = UserPost.repost(post('sam', event), note: 'In!');
      final map = repost.toEditableMap();
      expect(map['kind'], 'repost');
      expect(map['repostOf'], {
        'postId': 'p1',
        'authorId': 'sam',
        'authorName': 'Pat',
      });
      expect(map['event'], isNull);
      final back = UserPost.fromMap('r1', map);
      expect(back.isRepost, isTrue);
      expect(back.originalId, 'p1');
      expect(back.body, 'In!');
      // Editing a repost keeps what it points at.
      expect(back.copyWith(body: 'Edited').repostOf!.postId, 'p1');
      // Reposting a repost points at the original.
      final again = UserPost.repost(back.copyWith(), note: '');
      expect(again.repostOf!.postId, 'p1');
      expect(UserPost.repostId('p1', 'u1'), 'r_p1_u1');
    });

    test('likes and reposts are read from the post', () {
      final p = UserPost.fromMap('p1', {
        'kind': 'text',
        'body': 'Hi',
        'likedBy': ['a', 'b'],
        'repostedBy': ['c'],
      });
      expect(p.likeCount, 2);
      expect(p.repostCount, 1);
      expect(p.toEditableMap().containsKey('likedBy'), isFalse);
    });

    test('an event on a text post is ignored', () {
      final map = post('u1', event).toEditableMap()..['kind'] = 'text';
      expect(UserPost.fromMap('p1', map).event, isNull);
    });
  });

  Future<void> pumpCard(
    WidgetTester tester,
    UserPost p, {
    PostActions? actions,
    VoidCallback? onRepost,
  }) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            body: SingleChildScrollView(
              child: UserPostCard(
                post: p,
                loadImage: (_) async => Result.ok(Uint8List(0)),
                actions: actions,
                onRepost: onRepost,
              ),
            ),
          ),
        ),
      ],
      errorBuilder: (_, state) => Text('Went to ${state.uri.path}'),
    );
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthRepository>.value(
        value: FakeAuthRepository(user: testUser),
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the post shows the event, and opens it for its author', (
    tester,
  ) async {
    await pumpCard(tester, post(testUser.uid, event));
    expect(find.textContaining('Shared an event'), findsOneWidget);
    expect(find.text('Come watch!'), findsOneWidget);
    expect(find.text('NOV'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('Game'), findsOneWidget);
    expect(find.text('Fall showcase'), findsOneWidget);
    expect(find.textContaining('Saturday'), findsOneWidget);
    expect(find.text('City Park'), findsOneWidget);
    expect(find.text('Northside Flyers'), findsOneWidget);

    await tester.tap(find.byType(SharedEventCard));
    await tester.pumpAndSettle();
    expect(find.text('Went to ${Routes.event('t1', 'e1')}'), findsOneWidget);
  });

  testWidgets("followers go to the team's page", (tester) async {
    await pumpCard(tester, post('someone-else', event));
    await tester.tap(find.byType(SharedEventCard));
    await tester.pumpAndSettle();
    expect(find.text('Went to ${Routes.team('t1')}'), findsOneWidget);
  });

  testWidgets('likes, reposts and shows a repost with its original', (
    tester,
  ) async {
    final posts = FakeUserPostRepository();
    final original = post('sam', event);
    posts.posts.add(original);
    final actions = PostActions(
      userPostRepository: posts,
      authRepository: FakeAuthRepository(user: testUser),
    );
    addTearDown(actions.dispose);
    var reposts = 0;
    await pumpCard(
      tester,
      original,
      actions: actions,
      onRepost: () => reposts++,
    );
    expect(find.text('Like'), findsOneWidget);
    await tester.tap(find.text('Repost'));
    expect(reposts, 1);

    // A repost by Zed shows Sam's post inside it.
    final repost = UserPost(
      id: 'r_p1_zed',
      authorId: 'zed',
      authorName: 'Zed',
      body: 'Go see this',
      repostOf: const RepostOf(
        postId: 'p1',
        authorId: 'sam',
        authorName: 'Pat',
      ),
    );
    actions.track([repost]);
    await pumpCard(tester, repost, actions: actions, onRepost: () {});
    await tester.pumpAndSettle();
    expect(find.textContaining("Reposted Pat's post"), findsOneWidget);
    expect(find.text('Go see this'), findsOneWidget);
    expect(find.text('Fall showcase'), findsOneWidget);

    // Liking the repost likes the original.
    await tester.tap(find.text('Like'));
    await tester.pumpAndSettle();
    expect(posts.posts.first.likedBy, [testUser.uid]);
    // Screens rebuild on the view model; here, draw it again.
    await pumpCard(tester, repost, actions: actions, onRepost: () {});
    expect(find.text('1'), findsOneWidget);
    expect(find.byIcon(Icons.favorite), findsOneWidget);
  });

  testWidgets('a repost of a deleted post says so', (tester) async {
    final posts = FakeUserPostRepository();
    final actions = PostActions(
      userPostRepository: posts,
      authRepository: FakeAuthRepository(user: testUser),
    );
    addTearDown(actions.dispose);
    final repost = UserPost(
      id: 'r_gone_zed',
      authorId: 'zed',
      authorName: 'Zed',
      repostOf: const RepostOf(postId: 'gone', authorId: 'sam'),
    );
    actions.track([repost]);
    await pumpCard(tester, repost, actions: actions);
    await tester.pumpAndSettle();
    expect(find.text('This post is no longer available.'), findsOneWidget);
    expect(find.text('Like'), findsNothing);
  });

  testWidgets('no Like or Repost without actions', (tester) async {
    await pumpCard(tester, post(testUser.uid, event));
    expect(find.text('Repost'), findsNothing);
    expect(find.text('Like'), findsNothing);
  });

  testWidgets("someone else's personal event doesn't open", (tester) async {
    final personal = SharedEvent(
      eventId: 'm1',
      title: 'Tempo run',
      type: EventType.workout,
      startsAt: DateTime(2026, 11, 7, 7),
    );
    await pumpCard(tester, post('someone-else', personal));
    expect(find.text('Tempo run'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
    await tester.tap(find.byType(SharedEventCard));
    await tester.pumpAndSettle();
    expect(find.textContaining('Went to'), findsNothing);
  });
}
