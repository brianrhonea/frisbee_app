import 'dart:async';
import 'dart:typed_data';

import 'package:frisbee_app/data/repositories/follow/follow_repository.dart';
import 'package:frisbee_app/data/repositories/post_comment/post_comment_repository.dart';
import 'package:frisbee_app/data/repositories/user_post/user_post_repository.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/chat.dart';
import 'package:frisbee_app/domain/models/follow.dart';
import 'package:frisbee_app/domain/models/post_comment.dart';
import 'package:frisbee_app/domain/models/user_post.dart';
import 'package:frisbee_app/utils/result.dart';

class FakeFollowRepository implements FollowRepository {
  /// uid → key → follow.
  final follows = <String, Map<String, Follow>>{};

  /// key → counts, as Cloud Functions would keep them.
  final counts = <String, FollowCounts>{};
  final _changes = StreamController<void>.broadcast();

  void _changed() => _changes.add(null);

  List<Follow> _of(String uid) => [...?follows[uid]?.values.toList().reversed];

  @override
  Stream<List<Follow>> watchFollows(String uid) async* {
    yield _of(uid);
    yield* _changes.stream.map((_) => _of(uid));
  }

  @override
  Stream<Follow?> watchFollow(String uid, String key) async* {
    yield follows[uid]?[key];
    yield* _changes.stream.map((_) => follows[uid]?[key]);
  }

  @override
  Future<Result<void>> follow(
    String uid,
    FollowTarget target, {
    bool notify = false,
  }) async {
    if (target.type == FollowType.user && privateOwners.contains(target.id)) {
      return Result.error(Exception("You don't have permission to do that."));
    }
    final mine = follows.putIfAbsent(uid, () => {});
    if (!mine.containsKey(target.key)) {
      _bump(target.key, followers: 1);
      _bump(FollowTarget.userKey(uid), following: 1);
    }
    mine[target.key] = Follow(
      target: target,
      notify: notify,
      createdAt: DateTime.now(),
    );
    _changed();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> unfollow(String uid, String key) async {
    if (follows[uid]?.remove(key) != null) {
      _bump(key, followers: -1);
      _bump(FollowTarget.userKey(uid), following: -1);
    }
    _changed();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> setNotify(String uid, String key, bool notify) async {
    final f = follows[uid]?[key];
    if (f == null) return Result.error(Exception('Not following'));
    follows[uid]![key] = f.copyWith(notify: notify);
    _changed();
    return const Result.ok(null);
  }

  void _bump(String key, {int followers = 0, int following = 0}) {
    final c = counts[key] ?? const FollowCounts();
    counts[key] = FollowCounts(
      followers: c.followers + followers,
      following: c.following + following,
    );
  }

  @override
  Stream<FollowCounts> watchCounts(String key) async* {
    yield counts[key] ?? const FollowCounts();
    yield* _changes.stream.map((_) => counts[key] ?? const FollowCounts());
  }

  /// owner → requester uid → request.
  final requests = <String, Map<String, FollowRequest>>{};

  /// Owners whose profile is private, so [follow] is refused, as the rules
  /// refuse it.
  final privateOwners = <String>{};

  List<FollowRequest> _requestsOf(String owner) => [
    ...?requests[owner]?.values,
  ];

  @override
  Stream<bool> watchFollowRequested(String uid, String owner) async* {
    yield requests[owner]?.containsKey(uid) ?? false;
    yield* _changes.stream.map(
      (_) => requests[owner]?.containsKey(uid) ?? false,
    );
  }

  @override
  Future<Result<void>> requestFollow(AppUser me, String owner) async {
    requests.putIfAbsent(owner, () => {})[me.uid] = FollowRequest(
      uid: me.uid,
      name: me.label,
      username: me.username,
      photoUrl: me.photoUrl,
      createdAt: DateTime.now(),
    );
    _changed();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> cancelFollowRequest(String uid, String owner) async {
    requests[owner]?.remove(uid);
    _changed();
    return const Result.ok(null);
  }

  @override
  Stream<List<FollowRequest>> watchFollowRequests(String owner) async* {
    yield _requestsOf(owner);
    yield* _changes.stream.map((_) => _requestsOf(owner));
  }

  @override
  Future<Result<void>> acceptFollowRequest(
    AppUser owner,
    FollowRequest request,
  ) async {
    if (requests[owner.uid]?.remove(request.uid) == null) {
      return Result.error(Exception('No such request'));
    }
    final wasPrivate = privateOwners.remove(owner.uid);
    await follow(request.uid, FollowTarget.user(owner.uid, owner.label));
    if (wasPrivate) privateOwners.add(owner.uid);
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> declineFollowRequest(
    String owner,
    String requester,
  ) async {
    requests[owner]?.remove(requester);
    _changed();
    return const Result.ok(null);
  }
}

class FakeUserPostRepository implements UserPostRepository {
  final posts = <UserPost>[];
  final _changes = StreamController<void>.broadcast();
  var _next = 0;

  /// Photos uploaded by [savePost], by name.
  final uploaded = <String>[];

  /// Tells watchers that [posts] changed (after editing it directly).
  void changed() => _changes.add(null);

  List<UserPost> _where(bool Function(UserPost) test, int limit) =>
      (posts.where(test).toList()..sort(UserPost.newestFirst))
          .take(limit)
          .toList();

  Stream<List<UserPost>> _watch(
    bool Function(UserPost) test,
    int limit,
  ) async* {
    yield _where(test, limit);
    yield* _changes.stream.map((_) => _where(test, limit));
  }

  @override
  Stream<List<UserPost>> watchPostsBy(String authorId, {int limit = 50}) =>
      _watch((p) => p.authorId == authorId, limit);

  @override
  Stream<List<UserPost>> watchPostsByAuthors(
    List<String> authorIds, {
    int limit = 50,
  }) => authorIds.isEmpty
      ? Stream.value(const [])
      : _watch((p) => authorIds.contains(p.authorId), limit);

  @override
  Stream<List<UserPost>> watchPostsForTournaments(
    List<String> tournamentKeys, {
    int limit = 50,
  }) => tournamentKeys.isEmpty
      ? Stream.value(const [])
      : _watch((p) => tournamentKeys.contains(p.tournamentKey), limit);

  @override
  Stream<List<UserPost>> watchPostsForTeamEvents(
    List<String> teamIds, {
    int limit = 50,
  }) => teamIds.isEmpty
      ? Stream.value(const [])
      : _watch((p) => teamIds.contains(p.event?.teamId), limit);

  /// Calls to [fetchPostsBefore], for checking reads stay paged.
  int fetches = 0;

  @override
  Future<Result<List<UserPost>>> fetchPostsBefore(
    UserPostFilter filter,
    List<String> values, {
    required DateTime before,
    int limit = 20,
  }) async {
    fetches++;
    bool matches(UserPost p) => switch (filter) {
      UserPostFilter.authors => values.contains(p.authorId),
      UserPostFilter.tournaments => values.contains(p.tournamentKey),
      UserPostFilter.teamEvents => values.contains(p.event?.teamId),
    };
    return Result.ok(
      _where(
        (p) =>
            matches(p) && p.createdAt != null && p.createdAt!.isBefore(before),
        limit,
      ),
    );
  }

  UserPost? _find(String id) => posts.where((p) => p.id == id).firstOrNull;

  @override
  Stream<UserPost?> watchPost(String id) async* {
    yield _find(id);
    yield* _changes.stream.map((_) => _find(id));
  }

  @override
  Future<Result<String>> savePost(UserPostDraft draft, AppUser author) async {
    final post = draft.post;
    final images = [
      ...post.images,
      for (final a in draft.newImages)
        ChatAttachment(
          path: 'users/${author.uid}/posts/${a.name}',
          name: a.name,
          contentType: a.contentType,
          size: a.size,
        ),
    ];
    uploaded.addAll(draft.newImages.map((a) => a.name));
    if (post.isNew) {
      final id = 'up${++_next}';
      posts.add(
        UserPost(
          id: id,
          authorId: author.uid,
          authorName: author.label,
          body: post.body,
          links: post.links,
          images: images,
          workout: post.workout,
          event: post.event,
          repostOf: post.repostOf,
          tournamentKey: post.tournamentKey,
          tournamentName: post.tournamentName,
          createdAt: DateTime.now(),
        ),
      );
      _changes.add(null);
      return Result.ok(id);
    }
    final i = posts.indexWhere((p) => p.id == post.id);
    if (i < 0) return Result.error(Exception('No post'));
    posts[i] = post.copyWith(images: images);
    _changes.add(null);
    return Result.ok(post.id);
  }

  void _setList(
    String postId,
    String uid,
    bool on,
    UserPost Function(UserPost p, List<String> uids) apply,
    List<String> Function(UserPost p) of,
  ) {
    final i = posts.indexWhere((p) => p.id == postId);
    if (i < 0) return;
    final uids = [...of(posts[i])]..remove(uid);
    if (on) uids.add(uid);
    posts[i] = apply(posts[i], uids);
  }

  static UserPost _with(
    UserPost p, {
    List<String>? likedBy,
    List<String>? repostedBy,
    int? commentCount,
  }) => UserPost(
    id: p.id,
    authorId: p.authorId,
    authorName: p.authorName,
    authorPhotoUrl: p.authorPhotoUrl,
    body: p.body,
    links: p.links,
    images: p.images,
    workout: p.workout,
    event: p.event,
    repostOf: p.repostOf,
    likedBy: likedBy ?? p.likedBy,
    repostedBy: repostedBy ?? p.repostedBy,
    commentCount: commentCount ?? p.commentCount,
    tournamentKey: p.tournamentKey,
    tournamentName: p.tournamentName,
    createdAt: p.createdAt,
    updatedAt: p.updatedAt,
  );

  @override
  Future<Result<void>> setLiked(String postId, String uid, bool liked) async {
    if (_find(postId) == null) return Result.error(Exception('No post'));
    _setList(
      postId,
      uid,
      liked,
      (p, u) => _with(p, likedBy: u),
      (p) => p.likedBy,
    );
    _changes.add(null);
    return const Result.ok(null);
  }

  @override
  Future<Result<String>> repost(
    UserPost original,
    String note,
    AppUser me,
  ) async {
    final post = UserPost.repost(original, note: note);
    final id = UserPost.repostId(post.originalId, me.uid);
    if (_find(post.originalId) == null) {
      return Result.error(Exception('No post'));
    }
    if (_find(id) != null) return Result.error(Exception('Already reposted'));
    posts.add(
      UserPost(
        id: id,
        authorId: me.uid,
        authorName: me.label,
        body: post.body,
        repostOf: post.repostOf,
        createdAt: DateTime.now(),
      ),
    );
    _setList(
      post.originalId,
      me.uid,
      true,
      (p, u) => _with(p, repostedBy: u),
      (p) => p.repostedBy,
    );
    _changes.add(null);
    return Result.ok(id);
  }

  @override
  Future<Result<void>> undoRepost(String originalId, String uid) async {
    posts.removeWhere((p) => p.id == UserPost.repostId(originalId, uid));
    _setList(
      originalId,
      uid,
      false,
      (p, u) => _with(p, repostedBy: u),
      (p) => p.repostedBy,
    );
    _changes.add(null);
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> deletePost(String id) async {
    posts.removeWhere((p) => p.id == id);
    _changes.add(null);
    return const Result.ok(null);
  }

  @override
  Future<Result<Uint8List>> downloadImage(ChatAttachment image) async =>
      Result.ok(Uint8List(0));
}

/// Comments in memory. With [posts], keeps each post's commentCount the
/// way the Cloud Function does.
class FakePostCommentRepository implements PostCommentRepository {
  FakePostCommentRepository({this.posts});

  final FakeUserPostRepository? posts;
  final comments = <PostComment>[];
  final _changes = StreamController<void>.broadcast();
  var _next = 0;

  void changed() => _changes.add(null);

  List<PostComment> _on(String postId, int limit) {
    final list = comments.where((c) => c.postId == postId).toList()
      ..sort(PostComment.oldestFirst);
    return list.length > limit ? list.sublist(list.length - limit) : list;
  }

  void _count(String postId, int by) {
    final repo = posts;
    if (repo == null) return;
    final i = repo.posts.indexWhere((p) => p.id == postId);
    if (i < 0) return;
    final p = repo.posts[i];
    repo.posts[i] = FakeUserPostRepository._with(
      p,
      commentCount: p.commentCount + by,
    );
    repo.changed();
  }

  @override
  Stream<List<PostComment>> watchComments(
    String postId, {
    int limit = 100,
  }) async* {
    yield _on(postId, limit);
    yield* _changes.stream.map((_) => _on(postId, limit));
  }

  @override
  Future<Result<String>> addComment(
    String postId,
    String body,
    AppUser author,
  ) async {
    final id = 'c${++_next}';
    comments.add(
      PostComment(
        id: id,
        postId: postId,
        authorId: author.uid,
        authorName: author.label,
        authorPhotoUrl: author.photoUrl,
        body: body.trim(),
        createdAt: DateTime(2026, 11, 3, 12, _next),
      ),
    );
    _count(postId, 1);
    changed();
    return Result.ok(id);
  }

  @override
  Future<Result<void>> deleteComment(PostComment comment) async {
    final before = comments.length;
    comments.removeWhere(
      (c) => c.postId == comment.postId && c.id == comment.id,
    );
    if (comments.length < before) _count(comment.postId, -1);
    changed();
    return const Result.ok(null);
  }
}
