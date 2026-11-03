import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../domain/models/app_user.dart';
import '../../../domain/models/post_comment.dart';
import '../../../utils/result.dart';
import '../../services/firestore_utils.dart';
import 'post_comment_repository.dart';

class PostCommentRepositoryFirebase implements PostCommentRepository {
  PostCommentRepositoryFirebase({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

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
    AppUser author,
  ) => guard(() async {
    final ref = _comments(postId).doc();
    await ref.set({
      'body': body.trim(),
      'authorId': author.uid,
      'authorName': author.label,
      'authorPhotoUrl': author.photoUrl,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  });

  @override
  Future<Result<void>> deleteComment(PostComment comment) =>
      guard(() => _comments(comment.postId).doc(comment.id).delete());
}
