import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../domain/models/app_user.dart';
import '../../../domain/models/outbox.dart';
import '../../../domain/models/post_comment.dart';
import '../../../utils/result.dart';
import '../../services/firestore_utils.dart';
import '../outbox/outbox_repository.dart';
import 'post_comment_repository.dart';
import '../../../domain/models/word_filter.dart';

/// Replies, edits and likes live on the comment documents themselves
/// (`parentId`, `editedAt`, `likedBy`); firestore.rules checks each.
class PostCommentRepositoryFirebase implements PostCommentRepository {
  PostCommentRepositoryFirebase({
    FirebaseFirestore? firestore,
    OutboxRepository? outbox,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _outbox = outbox {
    outbox?.register(
      OutboxKind.comment,
      OutboxHandler(
        send: (job, _, author) async {
          final r = await _add(
            job.target,
            job.id,
            job.payload['body'] as String? ?? '',
            author,
            parentId: job.payload['parentId'] as String?,
            replyToName: job.payload['replyToName'] as String?,
          );
          return switch (r) {
            Ok() => const Result.ok(null),
            Error(:final error) => Result.error(error),
          };
        },
        sent: (job) => existsOnServer(_comments(job.target).doc(job.id)),
      ),
    );
  }

  final FirebaseFirestore _db;

  /// Holds comments made offline until they can go out.
  final OutboxRepository? _outbox;

  CollectionReference<Map<String, dynamic>> _comments(String postId) =>
      _db.collection('posts').doc(postId).collection('comments');

  @override
  Stream<List<PostComment>> watchComments(String postId, {int limit = 100}) =>
      _comments(postId)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots()
          .map(
            (snap) => [
              for (final d in snap.docs.reversed)
                PostComment.fromMap(postId, d.id, plainData(d.data())),
            ],
          );

  @override
  Future<Result<String>> addComment(
    String postId,
    String body,
    AppUser author, {
    PostComment? replyTo,
  }) async {
    if (refuseBlockedWords<String>([body]) case final r?) return r;
    body = maskSwearing(body);
    final id = _comments(postId).doc().id;
    final parentId = replyTo == null ? null : replyTo.parentId ?? replyTo.id;
    // Replying to a reply says whose; a top-level comment is obvious.
    final replyToName = replyTo != null && replyTo.isReply
        ? replyTo.authorName
        : null;
    Future<Result<String>> now() => _add(
      postId,
      id,
      body,
      author,
      parentId: parentId,
      replyToName: replyToName,
    );
    final outbox = _outbox;
    if (outbox == null) return now();
    final r = await outbox.submit(
      kind: OutboxKind.comment,
      id: id,
      target: postId,
      label: 'Comment',
      payload: {'body': body, 'parentId': parentId, 'replyToName': replyToName},
      sendNow: () async => switch (await now()) {
        Ok() => const Result.ok(null),
        Error(:final error) => Result.error(error),
      },
    );
    return switch (r) {
      Ok() => Result.ok(id),
      Error(:final error) => Result.error(error),
    };
  }

  Future<Result<String>> _add(
    String postId,
    String id,
    String body,
    AppUser author, {
    String? parentId,
    String? replyToName,
  }) => guard(() async {
    final ref = _comments(postId).doc(id);
    await ref.set({
      'body': body.trim(),
      'authorId': author.uid,
      'authorName': author.label,
      'authorPhotoUrl': author.photoUrl,
      'createdAt': FieldValue.serverTimestamp(),
      'parentId': ?parentId,
      'replyToName': ?replyToName,
    });
    return ref.id;
  });

  @override
  Future<Result<void>> editComment(PostComment comment, String body) => guard(
    () => _comments(comment.postId).doc(comment.id).update({
      'body': cleanText(body).trim(),
      'editedAt': FieldValue.serverTimestamp(),
    }),
  );

  @override
  Future<Result<void>> setCommentLiked(
    PostComment comment,
    String uid, {
    required bool liked,
  }) => guard(
    () => _comments(comment.postId).doc(comment.id).update({
      'likedBy': liked
          ? FieldValue.arrayUnion([uid])
          : FieldValue.arrayRemove([uid]),
    }),
  );

  @override
  Future<Result<void>> deleteComment(PostComment comment) =>
      guard(() => _comments(comment.postId).doc(comment.id).delete());
}
