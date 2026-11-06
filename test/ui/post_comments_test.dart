import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/direct_message.dart';
import 'package:frisbee_app/domain/models/post_comment.dart';
import 'package:frisbee_app/domain/models/user_post.dart';
import 'package:frisbee_app/ui/posts/view_models/post_detail_viewmodel.dart';
import 'package:frisbee_app/ui/posts/view_models/send_post_viewmodel.dart';

import '../testing/fakes.dart';
import '../testing/social_fakes.dart';

void main() {
  late FakeUserPostRepository posts;
  late FakePostCommentRepository comments;

  const zed = AppUser(uid: 'zed', email: 'z@z.com', displayName: 'Zed');

  setUp(() {
    posts = FakeUserPostRepository();
    comments = FakePostCommentRepository(posts: posts);
  });

  PostDetailViewModel open(String id, {AppUser user = testUser}) =>
      PostDetailViewModel(
        postId: id,
        userPostRepository: posts,
        authRepository: FakeAuthRepository(user: user),
        commentRepository: comments,
      );

  test("a repost's comments are its original's", () async {
    posts.posts.addAll([
      UserPost(id: 'p1', authorId: 'sam', authorName: 'Sam', body: 'Hi'),
      UserPost(
        id: 'r_p1_zed',
        authorId: 'zed',
        repostOf: const RepostOf(postId: 'p1', authorId: 'sam'),
      ),
    ]);
    final vm = open('r_p1_zed');
    addTearDown(vm.dispose);
    await pumpEventQueue();
    expect(vm.commentPostId, 'p1');
    expect(vm.comments, isEmpty);

    await vm.addComment.execute(' Nice ');
    await pumpEventQueue();
    expect(vm.comments!.single.body, 'Nice');
    expect(vm.comments!.single.postId, 'p1');
    expect(posts.posts.firstWhere((p) => p.id == 'p1').commentCount, 1);
  });

  test("empty or too long comments aren't sent", () async {
    posts.posts.add(UserPost(id: 'p1', authorId: 'sam', body: 'Hi'));
    final vm = open('p1');
    addTearDown(vm.dispose);
    await pumpEventQueue();
    await vm.addComment.execute('   ');
    expect(vm.addComment.error, isTrue);
    await vm.addComment.execute('x' * 1001);
    expect(vm.addComment.error, isTrue);
    expect(comments.comments, isEmpty);
  });

  test(
    "the post's author deletes anyone's comment; others only theirs",
    () async {
      posts.posts.add(UserPost(id: 'p1', authorId: testUser.uid, body: 'Hi'));
      await comments.addComment('p1', 'From Zed', zed);
      final mine = open('p1');
      addTearDown(mine.dispose);
      final theirs = open(
        'p1',
        user: const AppUser(uid: 'jo', email: 'j@j.com'),
      );
      addTearDown(theirs.dispose);
      await pumpEventQueue();
      final c = mine.comments!.single;
      expect(theirs.canDeleteComment(c), isFalse);
      await theirs.deleteComment.execute(c);
      expect(theirs.deleteComment.error, isTrue);
      expect(mine.canDeleteComment(c), isTrue);
      await mine.deleteComment.execute(c);
      await pumpEventQueue();
      expect(mine.comments, isEmpty);
      expect(posts.posts.single.commentCount, 0);
    },
  );

  test('replies thread one level deep under the top-level comment', () async {
    posts.posts.add(UserPost(id: 'p1', authorId: 'sam', body: 'Hi'));
    await comments.addComment('p1', 'Who is in?', zed);
    final vm = open('p1');
    addTearDown(vm.dispose);
    await pumpEventQueue();
    final top = vm.comments!.single;

    vm.replyTo(top);
    expect(vm.replyingTo, top);
    await vm.addComment.execute('Me');
    await pumpEventQueue();
    expect(vm.replyingTo, isNull, reason: 'the next comment is top-level');
    final reply = vm.comments!.last;
    expect(reply.parentId, top.id);
    expect(reply.replyToName, isNull);

    // Replying to a reply stays under the same top-level comment.
    vm.replyTo(reply);
    await vm.addComment.execute('Me too');
    await vm.addComment.execute('A new thread');
    await pumpEventQueue();
    final threads = vm.threads!;
    expect(threads.map((t) => t.comment.body), ['Who is in?', 'A new thread']);
    expect(threads.first.replies.map((r) => r.body), ['Me', 'Me too']);
    expect(threads.first.replies.last.parentId, top.id);
    expect(threads.first.replies.last.replyToName, testUser.label);
  });

  test("replies whose comment is gone aren't shown", () {
    const orphan = PostComment(
      id: 'r1',
      postId: 'p1',
      authorId: 'zed',
      authorName: 'Zed',
      body: 'Me',
      parentId: 'gone',
    );
    expect(threadComments([orphan]), isEmpty);
  });

  test('only the author edits a comment, and it shows as edited', () async {
    posts.posts.add(UserPost(id: 'p1', authorId: 'sam', body: 'Hi'));
    await comments.addComment('p1', 'From Zed', zed);
    final vm = open('p1');
    addTearDown(vm.dispose);
    await pumpEventQueue();
    final theirs = vm.comments!.single;
    expect(vm.canEditComment(theirs), isFalse);
    vm.startEditing(theirs);
    expect(vm.editing, isNull);

    await vm.addComment.execute('Mine');
    await pumpEventQueue();
    final mine = vm.comments!.last;
    expect(mine.edited, isFalse);
    vm.startEditing(mine);
    expect(vm.editing, mine);
    await vm.editComment.execute('   ');
    expect(vm.editComment.error, isTrue);
    await vm.editComment.execute(' Mine, fixed ');
    await pumpEventQueue();
    expect(vm.editing, isNull);
    expect(vm.comments!.last.body, 'Mine, fixed');
    expect(vm.comments!.last.edited, isTrue);
  });

  test('liking a comment toggles the like', () async {
    posts.posts.add(UserPost(id: 'p1', authorId: 'sam', body: 'Hi'));
    await comments.addComment('p1', 'Huck it', zed);
    final vm = open('p1');
    addTearDown(vm.dispose);
    await pumpEventQueue();
    await vm.toggleCommentLike.execute(vm.comments!.single);
    await pumpEventQueue();
    expect(vm.comments!.single.likedByUser(testUser.uid), isTrue);
    expect(vm.comments!.single.likeCount, 1);
    await vm.toggleCommentLike.execute(vm.comments!.single);
    await pumpEventQueue();
    expect(vm.comments!.single.likeCount, 0);
  });

  test('sends a post to recent people and anyone found, once each', () async {
    final dms = FakeDirectMessageRepository()
      ..profiles.add(const UserProfile(uid: 'jo', name: 'Jo Park'));
    // Talked to Zed before.
    final convo = (await dms.openConversation(
      testUser,
      const UserProfile(uid: 'zed', name: 'Zed'),
    ));
    await dms.sendMessage(
      Conversation.idFor(testUser.uid, 'zed'),
      author: testUser,
      text: 'Hey',
    );
    expect(convo, isNotNull);
    final vm = SendPostViewModel(
      post: UserPost(id: 'p1', authorId: testUser.uid, body: 'My first 5k'),
      directMessageRepository: dms,
      authRepository: FakeAuthRepository(user: testUser),
      debounce: Duration.zero,
    );
    addTearDown(vm.dispose);
    await pumpEventQueue();
    expect(vm.recent!.map((p) => p.uid), ['zed']);
    expect(
      vm.messageText,
      startsWith('Check out my post on Stall 10: “My first 5k”'),
    );
    expect(vm.messageText, endsWith('/p/p1'));

    vm.search('jo');
    await pumpEventQueue();
    await Future<void>.delayed(Duration.zero);
    expect(vm.results.map((p) => p.uid), ['jo']);
    await vm.send.execute(vm.results.single);
    await vm.send.execute(vm.results.single);
    expect(vm.wasSent('jo'), isTrue);
    expect(dms.messages[Conversation.idFor(testUser.uid, 'jo')], hasLength(1));
  });
}
