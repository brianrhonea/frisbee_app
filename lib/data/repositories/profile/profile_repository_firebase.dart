import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../domain/models/direct_message.dart';
import '../../services/firestore_utils.dart';
import 'profile_repository.dart';

class ProfileRepositoryFirebase implements ProfileRepository {
  ProfileRepositoryFirebase({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  @override
  Stream<UserProfile?> watchProfile(String uid) => _db
      .collection('profiles')
      .doc(uid)
      .snapshots()
      .map(
        (d) => d.exists ? UserProfile.fromMap(uid, plainData(d.data())) : null,
      );
}
