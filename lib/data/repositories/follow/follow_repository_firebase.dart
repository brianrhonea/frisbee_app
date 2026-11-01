import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../domain/models/follow.dart';
import '../../../utils/result.dart';
import '../../services/firestore_utils.dart';
import '../../services/shared_streams.dart';
import 'follow_repository.dart';

/// firestore.rules lets only the owner read and write their follows; anyone
/// signed in may read `followCounts`, which only Cloud Functions write.
class FollowRepositoryFirebase implements FollowRepository {
  FollowRepositoryFirebase({
    FirebaseFirestore? firestore,
    SharedStreams? sharedStreams,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _shared = sharedStreams ?? SharedStreams.instance;

  final FirebaseFirestore _db;

  /// One listener per query, shared by every screen (see [SharedStreams]).
  final SharedStreams _shared;

  CollectionReference<Map<String, dynamic>> _follows(String uid) =>
      _db.collection('users').doc(uid).collection('follows');

  @override
  Stream<List<Follow>> watchFollows(String uid) => _shared.get(
    'follows/$uid',
    () => countedSnapshots(
      _follows(uid).orderBy('createdAt', descending: true),
      'follows',
    ).map((s) => [for (final d in s.docs) Follow.fromMap(plainData(d.data()))]),
  );

  /// From the shared list of [uid]'s follows, so every Follow button on
  /// screen costs no reads of its own.
  @override
  Stream<Follow?> watchFollow(String uid, String key) => watchFollows(
    uid,
  ).map((all) => all.where((f) => f.key == key).firstOrNull).distinct();

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
  Stream<FollowCounts> watchCounts(String key) => _shared.get(
    'followCounts/$key',
    () => countedDocSnapshots(
      _db.collection('followCounts').doc(key),
      'followCounts',
    ).map((d) => FollowCounts.fromMap(d.data())),
  );
}
