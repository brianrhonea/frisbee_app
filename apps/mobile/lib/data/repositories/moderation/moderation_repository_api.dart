import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../domain/models/moderation.dart';
import '../../../utils/result.dart';
import '../../services/api_client.dart';
import '../../services/firestore_utils.dart';
import '../auth/auth_repository.dart';
import 'moderation_repository.dart';

/// [ModerationRepository] through the API, with the block list read from
/// Firestore (firestore.rules let only its owner read it).
class ModerationRepositoryApi extends ModerationRepository {
  ModerationRepositoryApi({
    required ApiClient? api,
    required AuthRepository auth,
    FirebaseFirestore? firestore,
  }) : _api = api,
       _auth = auth,
       _db = firestore {
    _auth.addListener(_onAuth);
    _onAuth();
  }

  final ApiClient? _api;
  final AuthRepository _auth;
  final FirebaseFirestore? _db;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  String? _uid;
  BlockList _current = BlockList.empty;

  static const _noApi =
      "Reporting and blocking aren't available in this version of the app. "
      'Update the app, or use stall10.app.';

  ApiClient get _client =>
      _api ?? (throw const ApiException('unavailable', _noApi));

  @override
  bool get enabled => _api != null;

  @override
  BlockList get current => _current;

  void _onAuth() {
    final uid = _auth.currentUser?.uid;
    if (uid == _uid) return;
    _uid = uid;
    _sub?.cancel();
    _sub = null;
    _set(BlockList.empty);
    if (uid == null) return;
    _sub = (_db ?? FirebaseFirestore.instance)
        .collection('users')
        .doc(uid)
        .collection('blocks')
        .snapshots()
        .listen(_onBlocks, onError: (_) {});
  }

  void _onBlocks(QuerySnapshot<Map<String, dynamic>> s) {
    final mine = <BlockedAccount>[];
    final hidden = <String>{};
    for (final d in s.docs) {
      hidden.add(d.id);
      final m = plainData(d.data());
      if (m['mine'] == true) {
        mine.add(
          BlockedAccount(
            uid: d.id,
            name: m['name'] as String? ?? 'Player',
            username: m['username'] as String?,
            photoUrl: m['photoUrl'] as String?,
          ),
        );
      }
    }
    mine.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _set(BlockList(mine: mine, hidden: hidden));
  }

  void _set(BlockList b) {
    _current = b;
    notifyListeners();
  }

  /// Hides [uid] at once, before the listener hears of the block.
  void _hideNow(String uid) =>
      _set(BlockList(mine: _current.mine, hidden: {..._current.hidden, uid}));

  @override
  Future<Result<bool>> report(
    ReportTarget target,
    ReportReason reason, {
    String? details,
    bool block = false,
    String? authorId,
  }) => guard(() async {
    final trimmed = details?.trim() ?? '';
    final r = await _client.post('/v1/reports', {
      'target': target.toJson(),
      'reason': reason.wire,
      if (trimmed.isNotEmpty) 'details': trimmed,
      if (block) 'block': true,
    });
    final blocked = r['blocked'] == true;
    final author = switch (target) {
      PersonReport(:final uid) => uid,
      _ => authorId,
    };
    if (blocked && author != null) _hideNow(author);
    return blocked;
  });

  static String _id(String id) => Uri.encodeComponent(id);

  @override
  Future<Result<void>> block(String uid, {String? name}) => guard(() async {
    await _client.put('/v1/me/blocks/${_id(uid)}', const {});
    _set(
      BlockList(
        mine: [
          for (final b in _current.mine)
            if (b.uid != uid) b,
          BlockedAccount(uid: uid, name: name ?? 'Player'),
        ],
        hidden: {..._current.hidden, uid},
      ),
    );
  });

  @override
  Stream<bool> watchStaff(String uid) => (_db ?? FirebaseFirestore.instance)
      .collection('staff')
      .doc(uid)
      .snapshots()
      .map((d) => d.exists)
      .handleError((Object _) {});

  @override
  Future<Result<void>> unblock(String uid) =>
      guard(() => _client.delete('/v1/me/blocks/${_id(uid)}'));

  @override
  Future<Result<List<ReportInfo>>> teamReports(String teamId) =>
      guard(() async {
        final json = await _client.send(
          'GET',
          '/v1/teams/${_id(teamId)}/reports',
        );
        return [
          for (final r in (json['reports'] as List?) ?? const [])
            if (r is Map) ReportInfo.fromMap(r.cast<String, Object?>()),
        ];
      });

  @override
  Future<Result<void>> resolveTeamReport(
    String teamId,
    String reportId, {
    required bool remove,
  }) => guard(
    () => _client.post('/v1/teams/${_id(teamId)}/reports/${_id(reportId)}', {
      'action': remove ? 'remove' : 'dismiss',
    }),
  );

  @override
  void dispose() {
    _auth.removeListener(_onAuth);
    _sub?.cancel();
    super.dispose();
  }
}
