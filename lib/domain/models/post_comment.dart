import 'model_utils.dart';

/// A comment on a person's post, at `posts/{postId}/comments/{id}`.
/// Comments on a repost go on its original. Anyone signed in reads and
/// writes them; the comment's author edits it, and the comment's author or
/// the post's author deletes it.
///
/// Replies are one level deep, like Instagram's: a reply's [parentId] is
/// always a top-level comment, and replying to a reply threads under the
/// same top-level comment with [replyToName] saying who it answers.
class PostComment {
  const PostComment({
    required this.id,
    required this.postId,
    required this.authorId,
    required this.authorName,
    this.authorPhotoUrl,
    required this.body,
    this.createdAt,
    this.editedAt,
    this.parentId,
    this.replyToName,
    this.likedBy = const [],
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

  /// When its author last changed it; null if never.
  final DateTime? editedAt;

  /// The top-level comment this replies to; null for a top-level comment.
  final String? parentId;

  /// Who a reply answers, when that's another reply's author.
  final String? replyToName;

  /// Everyone who liked it.
  final List<String> likedBy;

  bool get isReply => parentId != null;
  bool get edited => editedAt != null;
  int get likeCount => likedBy.length;
  bool likedByUser(String uid) => likedBy.contains(uid);

  PostComment copyWith({
    String? body,
    DateTime? editedAt,
    List<String>? likedBy,
  }) => PostComment(
    id: id,
    postId: postId,
    authorId: authorId,
    authorName: authorName,
    authorPhotoUrl: authorPhotoUrl,
    body: body ?? this.body,
    createdAt: createdAt,
    editedAt: editedAt ?? this.editedAt,
    parentId: parentId,
    replyToName: replyToName,
    likedBy: likedBy ?? this.likedBy,
  );

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
    editedAt: parseDate(map['editedAt']),
    parentId: map['parentId'] as String?,
    replyToName: map['replyToName'] as String?,
    likedBy: [for (final u in (map['likedBy'] as List?) ?? const []) '$u'],
  );

  static int oldestFirst(PostComment a, PostComment b) =>
      (a.createdAt ?? DateTime(9999)).compareTo(b.createdAt ?? DateTime(9999));
}

/// A top-level comment and its replies, oldest first.
typedef CommentThread = ({PostComment comment, List<PostComment> replies});

/// Groups [comments] into threads, oldest first. Replies whose parent
/// isn't loaded (deleted, or older than the page) are left out.
List<CommentThread> threadComments(Iterable<PostComment> comments) {
  final sorted = comments.toList()..sort(PostComment.oldestFirst);
  final replies = <String, List<PostComment>>{};
  for (final c in sorted) {
    if (c.parentId case final p?) (replies[p] ??= []).add(c);
  }
  return [
    for (final c in sorted)
      if (!c.isReply) (comment: c, replies: replies[c.id] ?? const []),
  ];
}
