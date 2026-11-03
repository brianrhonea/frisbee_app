import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/user_post.dart';
import 'package:frisbee_app/ui/posts/view_models/post_actions.dart';

import '../testing/fakes.dart';
import '../testing/social_fakes.dart';

void main() {
  late FakeUserPostRepository posts;
  late PostActions actions;

  UserPost by(String id, String author) => UserPost(
    id: id,
    authorId: author,
    authorName: author == 'sam' ? 'Sam' : 'Someone',
    body: 'Post $id',
    createdAt: DateTime(2026, 11, 2),
  );

  UserPost current(String id) => posts.posts.firstWhere((p) => p.id == id);

  setUp(() {
    posts = FakeUserPostRepository();
    actions = PostActions(
      userPostRepository: posts,
      authRepository: FakeAuthRepository(user: testUser),
    );
  });

  tearDown(() => actions.dispose());

  test('likes and unlikes a post', () async {
    posts.posts.add(by('p1', 'sam'));
    await actions.toggleLike.execute(current('p1'));
    expect(current('p1').likedBy, [testUser.uid]);
    expect(actions.isLiked(current('p1')), isTrue);
    await actions.toggleLike.execute(current('p1'));
    expect(current('p1').likedBy, isEmpty);
  });

  test("reposts someone's post once, and takes it back", () async {
    posts.posts.add(by('p1', 'sam'));
    expect(actions.canRepost(current('p1')), isTrue);
    await actions.repost.execute((post: current('p1'), note: ' Look! '));
    final repost = current(UserPost.repostId('p1', testUser.uid));
    expect(repost.authorId, testUser.uid);
    expect(repost.body, 'Look!');
    expect(repost.repostOf!.postId, 'p1');
    expect(repost.repostOf!.authorName, 'Sam');
    expect(current('p1').repostedBy, [testUser.uid]);
    expect(actions.isReposted(current('p1')), isTrue);

    // Again: nothing new.
    await actions.repost.execute((post: current('p1'), note: ''));
    expect(posts.posts.where((p) => p.isRepost), hasLength(1));

    await actions.undoRepost.execute(current('p1'));
    expect(posts.posts.where((p) => p.isRepost), isEmpty);
    expect(current('p1').repostedBy, isEmpty);
  });

  test("my own posts can't be reposted", () async {
    posts.posts.add(by('mine', testUser.uid));
    expect(actions.canRepost(current('mine')), isFalse);
    await actions.repost.execute((post: current('mine'), note: ''));
    expect(actions.repost.error, isTrue);
    expect(posts.posts, hasLength(1));
  });

  test("a repost's likes and reposts go to its original", () async {
    posts.posts.addAll([
      by('p1', 'sam'),
      UserPost(
        id: 'r_p1_zed',
        authorId: 'zed',
        repostOf: const RepostOf(postId: 'p1', authorId: 'sam'),
      ),
    ]);
    final echo = current('r_p1_zed');
    // Until the original loads there's nothing to act on.
    expect(actions.canRepost(echo), isFalse);
    actions.track([echo]);
    await pumpEventQueue();
    expect(actions.originalLoaded(echo), isTrue);
    expect(actions.originalOf(echo)!.id, 'p1');

    await actions.toggleLike.execute(echo);
    expect(current('p1').likedBy, [testUser.uid]);
    expect(current('r_p1_zed').likedBy, isEmpty);

    await actions.repost.execute((post: echo, note: ''));
    expect(posts.posts.map((p) => p.id), contains('r_p1_${testUser.uid}'));
    expect(current('p1').repostedBy, [testUser.uid]);
  });

  test('stops watching originals no longer shown', () async {
    final echo = UserPost(
      id: 'r_p1_zed',
      authorId: 'zed',
      repostOf: const RepostOf(postId: 'p1', authorId: 'sam'),
    );
    actions.track([echo]);
    await pumpEventQueue();
    expect(actions.originalLoaded(echo), isTrue);
    expect(actions.originalOf(echo), isNull); // Deleted, or never there.
    actions.track(const []);
    expect(actions.originalLoaded(echo), isFalse);
  });
}
