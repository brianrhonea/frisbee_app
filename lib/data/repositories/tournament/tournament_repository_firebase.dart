import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../domain/models/tournament.dart';
import '../../services/firestore_utils.dart';
import 'tournament_repository.dart';

/// Reads tournaments that the `scrapeUsauTournaments` Cloud Function
/// caches in `usau_tournaments`.
class TournamentRepositoryFirebase implements TournamentRepository {
  TournamentRepositoryFirebase({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  @override
  Stream<List<Tournament>> watchTournaments() => _db
      .collection('usau_tournaments')
      .orderBy('startDate')
      .snapshots()
      .map(
        (snap) => snap.docs
            .map((d) => Tournament.fromMap(d.id, plainData(d.data())))
            .toList(),
      );
}
