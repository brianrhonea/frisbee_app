import '../../../domain/models/ranking.dart';

/// Stall 10's team rankings and recent tournament results. Read-only:
/// the `rankings` Cloud Functions build them from public tournaments.
abstract class RankingRepository {
  /// Every division that has ranked teams.
  Stream<List<DivisionRanking>> watchRankings();

  /// Recently finished public tournaments, newest first.
  Stream<List<TournamentResult>> watchRecentResults();

  /// Rated players, best first; empty until the first nightly run.
  Stream<PlayerRanking> watchPlayerRankings();
}
