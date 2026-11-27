import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../domain/models/app_user.dart';
import '../../../domain/models/outbox.dart';
import '../../../domain/models/post_comment.dart';
import '../../../utils/result.dart';
import '../../services/api_client.dart';
import '../../services/firestore_utils.dart';
import '../outbox/outbox_payloads.dart';
import '../outbox/outbox_repository.dart';
import 'post_comment_repository.dart';
import '../../../domain/models/word_filter.dart';

/// Replies, edits and likes live on the comment documents themselves
/// (`parentId`, `editedAt`, `likedBy`); firestore.rules checks each.
class PostCommentRepositoryFirebase implements PostCommentRepository {
  PostCommentRepositoryFirebase({
    FirebaseFirestore? firestore,
    ApiClient? api,
    OutboxRepository? outbox,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _api = api,
       _outbox = outbox {
    outbox?.register(
      OutboxKind.comment,
      OutboxHandler(
        send: (job, _, author) async {
          final body = OutboxPayloads.comment(job);
          if (body == null) {
            return Result.error(
              const ApiException(
                'failed_precondition',
                OutboxPayloads.unmappable,
              ),
            );
          }
          final r = await _add(job.target, job.id, body);
          return switch (r) {
            Ok() => const Result.ok(null),
            Error(:final error) => Result.error(error),
          };
        },
        sent: (job) => existsOnServer(_comments(job.target).doc(job.id)),
      ),
    );
  }

  /// The Stall 10 API: every comment write goes through it
  /// (`/v1/posts/:id/comments`); there's no direct fallback.
  final ApiClient? _api;

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
    // The comment replied to (a reply too: the server threads it under its
    // top-level comment and says whose reply it was).
    final replyToId = replyTo?.id;
    Future<Result<String>> now() =>
        _add(postId, id, {'body': body.trim(), 'replyTo': ?replyToId});
    final outbox = _outbox;
    if (outbox == null) return now();
    final r = await outbox.submit(
      kind: OutboxKind.comment,
      id: id,
      target: postId,
      label: 'Comment',
      payload: {'body': body, 'replyTo': replyToId},
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

  /// `POST /v1/posts/:postId/comments` with the comment's [id], so a resend
  /// can't post it twice (a 409 is `already_exists`, which the queue counts
  /// as sent).
  Future<Result<String>> _add(
    String postId,
    String id,
    Map<String, Object?> body,
  ) => guard(() async {
    await _api.required.post(
      '/v1/posts/${Uri.encodeComponent(postId)}/comments',
      {...body, 'id': id},
    );
    return id;
  });

  String _path(PostComment c) =>
      '/v1/posts/${Uri.encodeComponent(c.postId)}/comments/'
      '${Uri.encodeComponent(c.id)}';

  @override
  Future<Result<void>> editComment(PostComment comment, String body) => guard(
    () => _api.required.patch(_path(comment), {'body': cleanText(body).trim()}),
  );

  @override
  Future<Result<void>> setCommentLiked(
    PostComment comment,
    String uid, {
    required bool liked,
  }) => guard(
    () =>
        _api.required.send(liked ? 'PUT' : 'DELETE', '${_path(comment)}/like'),
  );

  @override
  Future<Result<void>> deleteComment(PostComment comment) =>
      guard(() => _api.required.delete(_path(comment)));
}
