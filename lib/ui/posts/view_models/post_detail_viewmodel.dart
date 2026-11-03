import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/post_comment/post_comment_repository.dart';
import '../../../data/repositories/user_post/user_post_repository.dart';
import '../../../domain/models/chat.dart';
import '../../../domain/models/post_comment.dart';
import '../../../domain/models/user_post.dart';
import '../../../utils/command.dart';
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
  }) : _posts = userPostRepository,
       _auth = authRepository,
       _commentRepo = commentRepository {
    delete = Command0<void>(() => _posts.deletePost(postId));
    addComment = Command1<void, String>(_addComment);
    deleteComment = Command1<void, PostComment>(_deleteComment);
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
  List<PostComment>? get comments => _comments;
  Object? get commentsError => _commentsError;

  /// The post comments go on: a repost's original.
  String? get commentPostId => _commentsOf;

  /// Adds the user's comment to [commentPostId].
  late final Command1<void, String> addComment;
  late final Command1<void, PostComment> deleteComment;

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
    if (text.isEmpty) return Result.error(Exception('Write a comment first'));
    if (text.length > PostComment.maxBody) {
      return Result.error(
        Exception('Comments are up to ${PostComment.maxBody} characters'),
      );
    }
    final r = await repo.addComment(id, text, me);
    return switch (r) {
      Ok() => const Result.ok(null),
      Error(:final error) => Result.error(error),
    };
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
    _sub.cancel();
    _commentSub?.cancel();
    delete.dispose();
    addComment.dispose();
    deleteComment.dispose();
    actions
      ..removeListener(notifyListeners)
      ..dispose();
    super.dispose();
  }
}
