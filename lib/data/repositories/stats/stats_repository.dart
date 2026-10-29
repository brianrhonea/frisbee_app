import '../../../domain/models/roster_player.dart';
import '../../../domain/models/stats.dart';
import '../../../utils/result.dart';

abstract class StatsRepository {
  /// Players available for stat tracking (the team roster).
  Stream<List<RosterPlayer>> watchPlayers(String teamId);

  /// Tournament folders, newest first.
  Stream<List<StatsTournament>> watchTournaments(String teamId);

  /// All games, newest first, with and without a tournament.
  Stream<List<StatsGame>> watchGames(String teamId);

  /// Creates or replaces a tournament. Returns its id.
  Future<Result<String>> saveTournament(String teamId, StatsTournament t);

  /// Creates or replaces a game. Returns its id.
  Future<Result<String>> saveGame(String teamId, StatsGame game);

  Future<Result<void>> deleteGame(String teamId, String gameId);
}
