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
            ?_shown(d.id, DivisionRanking.fromMap(plainData(d.data()))),
        ],
      );

  /// [r] if it's shown: a ranked key (never youth, nothing unknown) that
  /// says the same as its doc id.
  static DivisionRanking? _shown(String id, DivisionRanking r) =>
      RankingChoice.parseKey(id) != null && r.key == id ? r : null;

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
