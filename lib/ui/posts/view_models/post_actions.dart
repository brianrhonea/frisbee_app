import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/user_post/user_post_repository.dart';
import '../../../domain/models/user_post.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// Likes and reposts for the posts on a page (the feed, a profile, a post's
/// own page), and the original posts behind any reposts there, kept up to
/// date so a repost shows the post as it is now (or that it was deleted).
///
/// Liking or reposting a repost acts on its original.
class PostActions extends ChangeNotifier {
  PostActions({
    required UserPostRepository userPostRepository,
    required AuthRepository authRepository,
  }) : _posts = userPostRepository,
       _auth = authRepository {
    toggleLike = Command1<void, UserPost>(_toggleLike);
    repost = Command1<void, ({UserPost post, String note})>(_repost);
    undoRepost = Command1<void, UserPost>(_undoRepost);
  }

  final UserPostRepository _posts;
  final AuthRepository _auth;
  final _subs = <String, StreamSubscription<UserPost?>>{};
  final _originals = <String, UserPost?>{};

  String get _uid => _auth.currentUser?.uid ?? '';

  /// Likes [post] (its original, for a repost), or takes the like back.
  late final Command1<void, UserPost> toggleLike;

  /// Reposts a post to the user's followers, with a note.
  late final Command1<void, ({UserPost post, String note})> repost;

  /// Takes back the user's repost of a post.
  late final Command1<void, UserPost> undoRepost;

  /// Watches the originals of the reposts among [posts], and stops watching
  /// the rest.
  void track(Iterable<UserPost> posts) {
    final ids = {
      for (final p in posts)
        if (p.repostOf case final r?) r.postId,
    };
    for (final id in _subs.keys.where((id) => !ids.contains(id)).toList()) {
      _subs.remove(id)?.cancel();
      _originals.remove(id);
    }
    for (final id in ids.where((id) => !_subs.containsKey(id))) {
      _subs[id] = _posts
          .watchPost(id)
          .listen(
            (p) {
              _originals[id] = p;
              notifyListeners();
            },
            onError: (Object _) {
              _originals[id] = null;
              notifyListeners();
            },
          );
    }
  }

  /// Whether [repost]'s original has loaded (it may be gone).
  bool originalLoaded(UserPost repost) =>
      _originals.containsKey(repost.repostOf?.postId);

  /// [repost]'s original; null while loading or once deleted.
  UserPost? originalOf(UserPost repost) => _originals[repost.repostOf?.postId];

  /// The post that likes and reposts of [post] count toward.
  UserPost? target(UserPost post) => post.isRepost ? originalOf(post) : post;

  bool isLiked(UserPost post) => target(post)?.likedBy.contains(_uid) ?? false;

  /// Someone else's post (or a repost of one) the user hasn't reposted.
  bool canRepost(UserPost post) {
    final t = target(post);
    return t != null && _uid.isNotEmpty && t.authorId != _uid;
  }

  bool isReposted(UserPost post) =>
      target(post)?.repostedBy.contains(_uid) ?? false;

  Future<Result<void>> _toggleLike(UserPost post) async {
    final t = target(post);
    if (t == null || _uid.isEmpty) {
      return Result.error(Exception("This post can't be liked"));
    }
    return _posts.setLiked(t.id, _uid, !t.likedBy.contains(_uid));
  }

  Future<Result<void>> _repost(({UserPost post, String note}) r) async {
    final me = _auth.currentUser;
    final t = target(r.post);
    if (me == null || t == null || !canRepost(r.post)) {
      return Result.error(Exception("This post can't be reposted"));
    }
    if (isReposted(r.post)) return const Result.ok(null);
    final saved = await _posts.repost(t, r.note, me);
    return switch (saved) {
      Ok() => const Result.ok(null),
      Error(:final error) => Result.error(error),
    };
  }

  Future<Result<void>> _undoRepost(UserPost post) async {
    final t = target(post);
    if (t == null || _uid.isEmpty) return const Result.ok(null);
    return _posts.undoRepost(t.id, _uid);
  }

  @override
  void dispose() {
    for (final s in _subs.values) {
      s.cancel();
    }
    toggleLike.dispose();
    repost.dispose();
    undoRepost.dispose();
    super.dispose();
  }
}
