import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../domain/models/follow.dart';
import '../../../utils/result.dart';
import '../../services/firestore_utils.dart';
import 'follow_repository.dart';

/// firestore.rules lets only the owner read and write their follows; anyone
/// signed in may read `followCounts`, which only Cloud Functions write.
class FollowRepositoryFirebase implements FollowRepository {
  FollowRepositoryFirebase({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _follows(String uid) =>
      _db.collection('users').doc(uid).collection('follows');

  @override
  Stream<List<Follow>> watchFollows(String uid) => _follows(uid)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map(
        (s) => [for (final d in s.docs) Follow.fromMap(plainData(d.data()))],
      );

  @override
  Stream<Follow?> watchFollow(String uid, String key) => _follows(uid)
      .doc(key)
      .snapshots()
      .map((d) => d.exists ? Follow.fromMap(plainData(d.data())) : null);

  @override
  Future<Result<void>> follow(
    String uid,
    FollowTarget target, {
    bool notify = false,
  }) => guard(
    () => _follows(uid).doc(target.key).set({
      ...Follow(target: target, notify: notify).toMap(),
      'createdAt': FieldValue.serverTimestamp(),
    }),
  );

  @override
  Future<Result<void>> unfollow(String uid, String key) =>
      guard(() => _follows(uid).doc(key).delete());

  @override
  Future<Result<void>> setNotify(String uid, String key, bool notify) =>
      guard(() => _follows(uid).doc(key).update({'notify': notify}));

  @override
  Stream<FollowCounts> watchCounts(String key) => _db
      .collection('followCounts')
      .doc(key)
      .snapshots()
      .map((d) => FollowCounts.fromMap(d.data()));
}
