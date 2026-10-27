import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../domain/models/play.dart';
import '../../../utils/result.dart';
import '../../services/firestore_utils.dart';
import 'play_repository.dart';

class PlayNotFoundException implements Exception {
  const PlayNotFoundException();

  @override
  String toString() => 'Play not found.';
}

class PlayRepositoryFirebase implements PlayRepository {
  PlayRepositoryFirebase({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _plays(String teamId) =>
      _db.collection('teams').doc(teamId).collection('plays');

  @override
  Stream<List<Play>> watchPlays(String teamId) =>
      _plays(teamId).snapshots().map(
        (snap) =>
            snap.docs
                .map((d) => Play.fromMap(d.id, plainData(d.data())))
                .toList()
              ..sort(
                (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
              ),
      );

  @override
  Future<Result<Play>> getPlay(String teamId, String playId) => guard(() async {
    final doc = await _plays(teamId).doc(playId).get();
    if (!doc.exists) throw const PlayNotFoundException();
    return Play.fromMap(doc.id, plainData(doc.data()));
  });

  @override
  Future<Result<String>> savePlay(String teamId, Play play, String uid) =>
      guard(() async {
        final col = _plays(teamId);
        final ref = play.isNew ? col.doc() : col.doc(play.id);
        await ref.set({
          ...play.toMap(),
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': uid,
        });
        return ref.id;
      });

  @override
  Future<Result<void>> deletePlay(String teamId, String playId) =>
      guard(() => _plays(teamId).doc(playId).delete());
}
