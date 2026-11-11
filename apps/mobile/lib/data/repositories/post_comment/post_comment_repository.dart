import '../../../domain/models/app_user.dart';
import '../../../domain/models/post_comment.dart';
import '../../../utils/result.dart';

/// Comments on people's posts, at `posts/{postId}/comments/{id}`. The
/// post's `commentCount` is kept by a Cloud Function.
abstract class PostCommentRepository {
  /// The newest [limit] comments on post [postId], oldest first.
  Stream<List<PostComment>> watchComments(String postId, {int limit = 100});

  /// Adds [author]'s comment to post [postId]; returns its id. With
  /// [replyTo] it's a reply, threaded under [replyTo]'s top-level comment.
  Future<Result<String>> addComment(
    String postId,
    String body,
    AppUser author, {
    PostComment? replyTo,
  });

  /// Rewrites one of the author's own comments.
  Future<Result<void>> editComment(PostComment comment, String body);

  /// Likes or unlikes [comment] as [uid].
  Future<Result<void>> setCommentLiked(
    PostComment comment,
    String uid, {
    required bool liked,
  });

  /// Deletes a comment: its author's, or any on the post's author's post.
  Future<Result<void>> deleteComment(PostComment comment);
}
