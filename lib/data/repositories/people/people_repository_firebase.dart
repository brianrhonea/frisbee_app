import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../domain/models/direct_message.dart';
import '../../services/firestore_utils.dart';
import 'people_repository.dart';

/// Reads `profiles/{uid}`, once per uid per app run. Usernames rarely
/// change, so a stale one for a session is fine.
class PeopleRepositoryFirebase implements PeopleRepository {
  PeopleRepositoryFirebase({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;
  final _cache = <String, UserProfile?>{};
  final _pending = <String, Future<UserProfile?>>{};

  @override
  UserProfile? cached(String uid) => _cache[uid];

  @override
  Future<UserProfile?> person(String uid) {
    if (uid.isEmpty) return Future.value();
    if (_cache.containsKey(uid)) return Future.value(_cache[uid]);
    return _pending[uid] ??= _fetch(uid);
  }

  Future<UserProfile?> _fetch(String uid) async {
    try {
      final d = await _db.collection('profiles').doc(uid).get();
      final p = d.exists ? UserProfile.fromMap(uid, plainData(d.data())) : null;
      _cache[uid] = p;
      return p;
    } on Exception {
      // Leave it uncached so a later message retries.
      return null;
    } finally {
      _pending.remove(uid);
    }
  }
}
