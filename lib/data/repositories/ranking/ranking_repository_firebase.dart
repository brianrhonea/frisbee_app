import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../domain/models/ranking.dart';
import '../../services/firestore_utils.dart';
import 'ranking_repository.dart';

/// Reads rankings that the `scrapeUsauRankings` Cloud Function caches in
/// `usau_rankings` (one document per division).
class RankingRepositoryFirebase implements RankingRepository {
  RankingRepositoryFirebase({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  @override
  Stream<List<RankingDivision>> watchDivisions() => _db
      .collection('usau_rankings')
      .snapshots()
      .map(
        (snap) =>
            snap.docs
                .map((d) => RankingDivision.fromMap(d.id, plainData(d.data())))
                .toList()
              ..sort((a, b) => a.label.compareTo(b.label)),
      );
}
