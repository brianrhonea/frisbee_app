import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../domain/models/direct_message.dart';
import '../../services/firestore_utils.dart';
import 'people_repository.dart';

/// Reads `profiles/{uid}`: once per uid, then again when a listing is
/// asked for after [maxAge], so a new profile picture reaches every post,
/// comment and message within a few minutes without a listener per face.
class PeopleRepositoryFirebase extends PeopleRepository {
  PeopleRepositoryFirebase({
    FirebaseFirestore? firestore,
    this.maxAge = const Duration(minutes: 5),
    DateTime Function()? now,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _now = now ?? DateTime.now;

  final FirebaseFirestore _db;
  final DateTime Function() _now;

  /// How long a listing is served before it's fetched again.
  final Duration maxAge;

  final _cache = <String, UserProfile?>{};
  final _fetchedAt = <String, DateTime>{};
  final _pending = <String, Future<UserProfile?>>{};

  @override
  UserProfile? cached(String uid) => _cache[uid];

  @override
  Future<UserProfile?> person(String uid) {
    if (uid.isEmpty) return Future.value();
    final at = _fetchedAt[uid];
    final fresh = at != null && _now().difference(at) < maxAge;
    if (_cache.containsKey(uid) && fresh) return Future.value(_cache[uid]);
    return _pending[uid] ??= _fetch(uid);
  }

  @override
  void remember(UserProfile profile) {
    final before = _cache[profile.uid];
    _cache[profile.uid] = profile;
    _fetchedAt[profile.uid] = _now();
    if (!_same(before, profile)) notifyListeners();
  }

  Future<UserProfile?> _fetch(String uid) async {
    try {
      final d = await _db.collection('profiles').doc(uid).get();
      final p = d.exists ? UserProfile.fromMap(uid, plainData(d.data())) : null;
      final before = _cache[uid];
      final known = _cache.containsKey(uid);
      _cache[uid] = p;
      _fetchedAt[uid] = _now();
      if (!known || !_same(before, p)) notifyListeners();
      return p;
    } on Exception {
      // Keep what's cached; a later lookup retries.
      return _cache[uid];
    } finally {
      _pending.remove(uid);
    }
  }

  static bool _same(UserProfile? a, UserProfile? b) =>
      a?.name == b?.name &&
      a?.photoUrl == b?.photoUrl &&
      a?.username == b?.username;
}
