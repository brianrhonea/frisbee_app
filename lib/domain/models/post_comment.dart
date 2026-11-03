import 'model_utils.dart';

/// A comment on a person's post, at `posts/{postId}/comments/{id}`.
/// Comments on a repost go on its original. Anyone signed in reads and
/// writes them; the comment's author or the post's author deletes them.
class PostComment {
  const PostComment({
    required this.id,
    required this.postId,
    required this.authorId,
    required this.authorName,
    this.authorPhotoUrl,
    required this.body,
    this.createdAt,
  });

  static const maxBody = 1000;

  final String id;
  final String postId;
  final String authorId;
  final String authorName;
  final String? authorPhotoUrl;
  final String body;

  /// Null until the server has stamped it.
  final DateTime? createdAt;

  factory PostComment.fromMap(
    String postId,
    String id,
    Map<String, dynamic> map,
  ) => PostComment(
    id: id,
    postId: postId,
    authorId: map['authorId'] as String? ?? '',
    authorName: map['authorName'] as String? ?? '',
    authorPhotoUrl: map['authorPhotoUrl'] as String?,
    body: map['body'] as String? ?? '',
    createdAt: parseDate(map['createdAt']),
  );

  static int oldestFirst(PostComment a, PostComment b) =>
      (a.createdAt ?? DateTime(9999)).compareTo(b.createdAt ?? DateTime(9999));
}
