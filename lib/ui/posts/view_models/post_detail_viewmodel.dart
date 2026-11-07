import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/notification/notification_repository.dart';
import '../../../data/repositories/post_comment/post_comment_repository.dart';
import '../../../data/repositories/user_post/user_post_repository.dart';
import '../../../domain/models/chat.dart';
import '../../../domain/models/post_comment.dart';
import '../../../domain/models/user_post.dart';
import '../../../utils/command.dart';
import '../../../utils/pending_removals.dart';
import '../../../utils/result.dart';
import 'post_actions.dart';

/// One person's post on its own page, where post notifications lead, with
/// its comments. A repost's comments are its original's.
class PostDetailViewModel extends ChangeNotifier {
  PostDetailViewModel({
    required this.postId,
    required UserPostRepository userPostRepository,
    required AuthRepository authRepository,
    PostCommentRepository? commentRepository,
    NotificationRepository? notificationRepository,
  }) : _posts = userPostRepository,
       _auth = authRepository,
       _commentRepo = commentRepository {
    // Likes, comments and replies on it have been seen now.
    if (authRepository.currentUser?.uid case final uid?) {
      unawaited(notificationRepository?.clearRoute(uid, '/posts/$postId'));
    }
    delete = Command0<void>(() => _posts.deletePost(postId));
    addComment = Command1<void, String>(_addComment);
    deleteComment = Command1<void, PostComment>(_deleteComment);
    editComment = Command1<void, String>(_editComment);
    toggleCommentLike = Command1<void, PostComment>(_toggleCommentLike);
    actions = PostActions(
      userPostRepository: userPostRepository,
      authRepository: authRepository,
    )..addListener(notifyListeners);
    _sub = _posts
        .watchPost(postId)
        .listen(
          (p) {
            _post = p;
            _loaded = true;
            actions.track([?p]);
            _watchComments(p?.originalId);
            notifyListeners();
          },
          onError: (Object e) {
            _error = e;
            _loaded = true;
            notifyListeners();
          },
        );
  }

  final String postId;
  final UserPostRepository _posts;
  final AuthRepository _auth;
  final PostCommentRepository? _commentRepo;
  late final StreamSubscription<UserPost?> _sub;
  StreamSubscription<List<PostComment>>? _commentSub;
  String? _commentsOf;
  List<PostComment>? _comments;
  Object? _commentsError;
  final _downloads = <String, Future<Result<Uint8List>>>{};

  UserPost? _post;
  bool _loaded = false;
  Object? _error;

  UserPost? get post => _post;
  bool get loaded => _loaded;
  Object? get error => _error;
  bool get isMine => _post != null && _post!.authorId == _auth.currentUser?.uid;

  late final Command0<void> delete;

  /// Comments are available here (not in every test).
  bool get canComment => _commentRepo != null;

  /// Oldest first; null while loading.
  List<PostComment>? get comments => switch (_comments) {
    final list? => removals.visible(list),
    null => null,
  };

  /// Comments deleted, hidden while "Undo" is offered.
  late final removals = PendingRemovals<PostComment>(
    keyOf: (c) => c.id,
    commit: deleteComment.execute,
    onChange: notifyListeners,
  );
  Object? get commentsError => _commentsError;

  /// The post comments go on: a repost's original.
  String? get commentPostId => _commentsOf;

  /// Adds the user's comment to [commentPostId].
  late final Command1<void, String> addComment;
  late final Command1<void, PostComment> deleteComment;

  /// Saves new text for [editing].
  late final Command1<void, String> editComment;

  /// Likes a comment, or takes the like back.
  late final Command1<void, PostComment> toggleCommentLike;

  /// Top-level comments with their replies, oldest first; null while
  /// loading.
  List<CommentThread>? get threads => switch (comments) {
    final list? => threadComments(list),
    null => null,
  };

  PostComment? _replyingTo;
  PostComment? _editing;

  /// The comment the next one answers; null for a top-level comment.
  PostComment? get replyingTo => _replyingTo;

  /// The comment being rewritten in the box; null when writing a new one.
  PostComment? get editing => _editing;

  /// Replies to [c] with the next comment (or stops, with null).
  void replyTo(PostComment? c) {
    _replyingTo = c;
    _editing = null;
    notifyListeners();
  }

  /// Starts rewriting [c], one of the user's own (or stops, with null).
  void startEditing(PostComment? c) {
    if (c != null && !canEditComment(c)) return;
    _editing = c;
    _replyingTo = null;
    notifyListeners();
  }

  /// Only a comment's author edits it.
  bool canEditComment(PostComment c) => uid.isNotEmpty && c.authorId == uid;

  String get uid => _auth.currentUser?.uid ?? '';

  /// The comment's author, or the author of the post it's on.
  bool canDeleteComment(PostComment c) {
    if (uid.isEmpty) return false;
    if (c.authorId == uid) return true;
    final post = _post;
    if (post == null) return false;
    final on = post.isRepost ? actions.originalOf(post) : post;
    return on?.authorId == uid;
  }

  void _watchComments(String? id) {
    final repo = _commentRepo;
    if (repo == null || id == _commentsOf) return;
    _commentSub?.cancel();
    _commentSub = null;
    _commentsOf = id;
    _comments = null;
    _commentsError = null;
    if (id == null) return;
    _commentSub = repo
        .watchComments(id)
        .listen(
          (c) {
            _comments = c;
            _commentsError = null;
            notifyListeners();
          },
          onError: (Object e) {
            _comments ??= const [];
            _commentsError = e;
            notifyListeners();
          },
        );
  }

  Future<Result<void>> _addComment(String body) async {
    final me = _auth.currentUser;
    final id = _commentsOf;
    final repo = _commentRepo;
    final text = body.trim();
    if (me == null || id == null || repo == null) {
      return Result.error(Exception("Comments aren't available"));
    }
    if (_invalidBody(text) case final error?) return error;
    final r = await repo.addComment(id, text, me, replyTo: _replyingTo);
    switch (r) {
      case Ok():
        _replyingTo = null;
        notifyListeners();
        return const Result.ok(null);
      case Error(:final error):
        return Result.error(error);
    }
  }

  Result<void>? _invalidBody(String text) {
    if (text.isEmpty) return Result.error(Exception('Write a comment first'));
    if (text.length > PostComment.maxBody) {
      return Result.error(
        Exception('Comments are up to ${PostComment.maxBody} characters'),
      );
    }
    return null;
  }

  Future<Result<void>> _editComment(String body) async {
    final repo = _commentRepo;
    final c = _editing;
    final text = body.trim();
    if (repo == null || c == null || !canEditComment(c)) {
      return Result.error(Exception("You can't edit this comment"));
    }
    if (_invalidBody(text) case final error?) return error;
    if (text == c.body) {
      startEditing(null);
      return const Result.ok(null);
    }
    final r = await repo.editComment(c, text);
    if (r is Ok) startEditing(null);
    return r;
  }

  Future<Result<void>> _toggleCommentLike(PostComment c) async {
    final repo = _commentRepo;
    if (repo == null || uid.isEmpty) {
      return Result.error(Exception('Sign in to like comments'));
    }
    return repo.setCommentLiked(c, uid, liked: !c.likedByUser(uid));
  }

  Future<Result<void>> _deleteComment(PostComment c) async {
    final repo = _commentRepo;
    if (repo == null || !canDeleteComment(c)) {
      return Result.error(Exception("You can't delete this comment"));
    }
    return repo.deleteComment(c);
  }

  /// Likes and reposts, and the post a repost shows.
  late final PostActions actions;

  Future<Result<Uint8List>> imageData(ChatAttachment image) =>
      _downloads[image.path] ??= _posts.downloadImage(image).then((r) {
        if (r is Error) _downloads.remove(image.path);
        return r;
      });

  @override
  void dispose() {
    removals.flush((c) => _commentRepo?.deleteComment(c));
    _sub.cancel();
    _commentSub?.cancel();
    delete.dispose();
    addComment.dispose();
    deleteComment.dispose();
    editComment.dispose();
    toggleCommentLike.dispose();
    actions
      ..removeListener(notifyListeners)
      ..dispose();
    super.dispose();
  }
}
