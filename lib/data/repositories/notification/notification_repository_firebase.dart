import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logging/logging.dart';

import '../../../domain/models/notification.dart';
import '../../../utils/result.dart';
import '../../services/firestore_utils.dart';
import '../../services/push_service.dart';
import '../../services/shared_streams.dart';
import 'notification_repository.dart';

/// Preferences live in `users/{uid}/settings/notifications`, the feed in
/// `users/{uid}/notifications` and push targets in `users/{uid}/devices`,
/// keyed by FID. Only the owner can read any of them; the feed is written
/// by Cloud Functions.
class NotificationRepositoryFirebase implements NotificationRepository {
  NotificationRepositoryFirebase({
    required PushService push,
    FirebaseFirestore? firestore,
    DateTime Function()? clock,
    SharedStreams? sharedStreams,
  }) : _push = push,
       _db = firestore ?? FirebaseFirestore.instance,
       _clock = clock ?? DateTime.now,
       _shared = sharedStreams ?? SharedStreams.instance;

  /// One listener per query, shared by every screen (see [SharedStreams]).
  final SharedStreams _shared;

  final PushService _push;
  final FirebaseFirestore _db;
  final DateTime Function() _clock;
  final _log = Logger('NotificationRepository');

  static const feedLimit = 100;

  String? _fid;
  StreamSubscription<String>? _registrations;

  DocumentReference<Map<String, dynamic>> _prefs(String uid) => _db
      .collection('users')
      .doc(uid)
      .collection('settings')
      .doc('notifications');

  CollectionReference<Map<String, dynamic>> _feed(String uid) =>
      _db.collection('users').doc(uid).collection('notifications');

  CollectionReference<Map<String, dynamic>> _devices(String uid) =>
      _db.collection('users').doc(uid).collection('devices');

  Future<void> _merge(String uid, Map<String, Object?> data) => _prefs(uid).set(
    {...data, 'updatedAt': FieldValue.serverTimestamp()},
    SetOptions(merge: true),
  );

  @override
  Stream<NotificationPreferences> watchPreferences(String uid) => _shared.get(
    'notificationPrefs/$uid',
    () => countedDocSnapshots(
      _prefs(uid),
      'notificationPrefs',
    ).map((d) => NotificationPreferences.fromMap(plainData(d.data() ?? {}))),
  );

  @override
  Future<Result<void>> setCategory(
    String uid,
    NotificationCategory category, {
    required bool on,
  }) => guard(
    () => _merge(uid, {
      'categories': {category.name: on},
    }),
  );

  @override
  Future<Result<void>> setTeamCategory(
    String uid,
    String teamId,
    NotificationCategory category, {
    required bool on,
  }) => guard(
    () => _merge(uid, {
      'teams': {
        teamId: {category.name: on},
      },
    }),
  );

  @override
  Future<Result<void>> resetTeam(String uid, String teamId) => guard(
    () => _merge(uid, {
      'teams': {teamId: FieldValue.delete()},
    }),
  );

  @override
  Future<Result<void>> setRoomMuted(
    String uid,
    String teamId,
    String roomId, {
    required bool muted,
  }) {
    final key = NotificationPreferences.roomKey(teamId, roomId);
    return guard(
      () => _merge(uid, {
        'mutedRooms': muted
            ? FieldValue.arrayUnion([key])
            : FieldValue.arrayRemove([key]),
      }),
    );
  }

  @override
  Stream<List<AppNotification>> watchFeed(String uid) => _shared.get(
    'notifications/$uid',
    () =>
        countedSnapshots(
          _feed(uid).orderBy('createdAt', descending: true).limit(feedLimit),
          'notifications',
        ).map(
          (snap) => [
            for (final d in snap.docs)
              AppNotification.fromMap(d.id, plainData(d.data())),
          ],
        ),
  );

  @override
  Future<Result<void>> markRead(String uid, Iterable<String> ids) =>
      guard(() async {
        final all = ids.toList();
        for (var i = 0; i < all.length; i += 450) {
          final batch = _db.batch();
          for (final id in all.skip(i).take(450)) {
            batch.update(_feed(uid).doc(id), {'read': true});
          }
          await batch.commit();
        }
      });

  @override
  Future<Result<void>> delete(String uid, Iterable<String> ids) =>
      guard(() => deleteDocs(_db, [for (final id in ids) _feed(uid).doc(id)]));

  @override
  bool get pushSupported => _push.isSupported;

  @override
  Future<PushStatus> pushStatus() => _push.status();

  @override
  Future<Result<PushStatus>> enablePush(String uid) => guard(() async {
    final status = await _push.requestPermission();
    if (status == PushStatus.enabled) await _register(uid);
    return status;
  });

  @override
  Future<void> syncDevice(String uid) async {
    try {
      // Reminders are worded in the user's local time.
      await _merge(uid, {
        'utcOffsetMinutes': _clock().timeZoneOffset.inMinutes,
      });
      if (await _push.status() == PushStatus.enabled) await _register(uid);
    } on Exception catch (e) {
      _log.warning('Device sync failed', e);
    }
  }

  Future<void> _register(String uid) async {
    final fid = await _push.register();
    if (fid != null) await _saveDevice(uid, fid);
    await _registrations?.cancel();
    _registrations = _push.registrations.listen(
      (fid) => _saveDevice(uid, fid),
      onError: (Object e) => _log.warning('FCM registration failed', e),
    );
  }

  Future<void> _saveDevice(String uid, String fid) async {
    final previous = _fid;
    _fid = fid;
    if (previous != null && previous != fid) {
      await _devices(uid).doc(previous).delete();
    }
    await _devices(uid).doc(fid).set({
      'platform': _push.platform,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> unregisterDevice(String uid) async {
    await _registrations?.cancel();
    _registrations = null;
    final fid = _fid;
    _fid = null;
    if (fid == null) return;
    try {
      await _devices(uid).doc(fid).delete();
      await _push.unregister();
    } on Exception catch (e) {
      _log.warning('Device unregister failed', e);
    }
  }

  @override
  Stream<String> get openedRoutes => _push.openedRoutes;
}
