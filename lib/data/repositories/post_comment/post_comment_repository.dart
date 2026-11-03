import '../../../domain/models/app_user.dart';
import '../../../domain/models/post_comment.dart';
import '../../../utils/result.dart';

/// Comments on people's posts, at `posts/{postId}/comments/{id}`. The
/// post's `commentCount` is kept by a Cloud Function.
abstract class PostCommentRepository {
  /// The newest [limit] comments on post [postId], oldest first.
  Stream<List<PostComment>> watchComments(String postId, {int limit = 100});

  /// Adds [author]'s comment to post [postId]; returns its id.
  Future<Result<String>> addComment(String postId, String body, AppUser author);

  /// Deletes a comment: its author's, or any on the post's author's post.
  Future<Result<void>> deleteComment(PostComment comment);
}
