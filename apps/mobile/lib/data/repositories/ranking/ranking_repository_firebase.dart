import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../domain/models/ranking.dart';
import '../../services/firestore_utils.dart';
import 'ranking_repository.dart';

/// `rankings/{level-division}`, `tournamentResults/recent` and
/// `playerRankings/all`.
class RankingRepositoryFirebase implements RankingRepository {
  RankingRepositoryFirebase({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  @override
  Stream<List<DivisionRanking>> watchRankings() => _db
      .collection('rankings')
      .snapshots()
      .map(
        (snap) => [
          for (final d in snap.docs)
            DivisionRanking.fromMap(plainData(d.data())),
        ],
      );

  @override
  Stream<List<TournamentResult>> watchRecentResults() => _db
      .doc('tournamentResults/recent')
      .snapshots()
      .map(
        (s) => [
          for (final t
              in (plainData(s.data())['tournaments'] as List?) ?? const [])
            if (t is Map)
              TournamentResult.fromMap(Map<String, dynamic>.from(t)),
        ],
      );

  @override
  Stream<PlayerRanking> watchPlayerRankings() => _db
      .doc('playerRankings/all')
      .snapshots()
      .map((s) => PlayerRanking.fromMap(plainData(s.data())));
}
