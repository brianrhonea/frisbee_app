import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../domain/models/app_user.dart';
import '../../../domain/models/follow.dart';
import '../../../utils/result.dart';
import '../../services/api_client.dart';
import '../../services/firestore_utils.dart';
import '../../services/shared_streams.dart';
import 'follow_repository.dart';

/// firestore.rules lets only the owner read and write their follows; anyone
/// signed in may read `followCounts`, which only Cloud Functions write.
class FollowRepositoryFirebase implements FollowRepository {
  FollowRepositoryFirebase({
    FirebaseFirestore? firestore,
    SharedStreams? sharedStreams,
    ApiClient? api,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _shared = sharedStreams ?? SharedStreams.instance,
       _api = api;

  /// The Stall 10 API: follows and follow requests are written through it
  /// (`/v1/follows`, `/v1/me/follow-requests`); there's no direct fallback.
  final ApiClient? _api;

  static String _enc(String s) => Uri.encodeComponent(s);

  final FirebaseFirestore _db;

  /// One listener per query, shared by every screen (see [SharedStreams]).
  final SharedStreams _shared;

  CollectionReference<Map<String, dynamic>> _follows(String uid) =>
      _db.collection('users').doc(uid).collection('follows');

  CollectionReference<Map<String, dynamic>> _requests(String owner) =>
      _db.collection('profiles').doc(owner).collection('followRequests');

  @override
  Stream<List<Follow>> watchFollows(String uid) => _shared.get(
    'follows/$uid',
    () =>
        countedSnapshots(
          _follows(uid).orderBy('createdAt', descending: true),
          'follows',
        ).map(
          (s) => [
            for (final d in s.docs)
              if (plainData(d.data()) case final m when Follow.isKnown(m))
                Follow.fromMap(m),
          ],
        ),
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
    () => _api.required.put('/v1/follows', {
      'type': target.type.name,
      'targetId': target.id,
      'groupId': ?target.groupId,
      'notify': notify,
    }),
  );

  @override
  Future<Result<void>> unfollow(String uid, String key) =>
      guard(() => _api.required.delete('/v1/follows/${_enc(key)}'));

  @override
  Future<Result<void>> setNotify(String uid, String key, bool notify) => guard(
    () => _api.required.patch('/v1/follows/${_enc(key)}', {'notify': notify}),
  );

  @override
  Stream<bool> watchFollowRequested(String uid, String owner) =>
      _requests(owner).doc(uid).snapshots().map((d) => d.exists);

  /// Follows a private profile: the server makes it a request the owner
  /// answers (`status: requested`); the follow itself is the same route.
  @override
  Future<Result<void>> requestFollow(AppUser me, String owner) => guard(
    () => _api.required.put('/v1/follows', {
      'type': FollowType.user.name,
      'targetId': owner,
      'notify': false,
    }),
  );

  @override
  Future<Result<void>> cancelFollowRequest(String uid, String owner) =>
      guard(() => _api.required.delete('/v1/follows/requests/${_enc(owner)}'));

  @override
  Stream<List<FollowRequest>> watchFollowRequests(String owner) => _shared.get(
    'followRequests/$owner',
    () =>
        countedSnapshots(
          _requests(owner).orderBy('createdAt'),
          'followRequests',
        ).map(
          (s) => [
            for (final d in s.docs)
              FollowRequest.fromMap(d.id, plainData(d.data())),
          ],
        ),
  );

  /// firestore.rules let the owner write the requester's follow only in
  /// the same batch that removes their request.
  /// Accepting twice is `not_found` the second time: it's done.
  @override
  Future<Result<void>> acceptFollowRequest(
    AppUser owner,
    FollowRequest request,
  ) => guard(() async {
    try {
      await _api.required.post(
        '/v1/me/follow-requests/${_enc(request.uid)}/accept',
        const {},
      );
    } on ApiException catch (e) {
      if (e.code != 'not_found') rethrow;
    }
  });

  @override
  Future<Result<void>> declineFollowRequest(String owner, String requester) =>
      guard(
        () => _api.required.delete('/v1/me/follow-requests/${_enc(requester)}'),
      );

  @override
  Stream<FollowCounts> watchCounts(String key) => _shared.get(
    'followCounts/$key',
    () => countedDocSnapshots(
      _db.collection('followCounts').doc(key),
      'followCounts',
    ).map((d) => FollowCounts.fromMap(d.data())),
  );
}
