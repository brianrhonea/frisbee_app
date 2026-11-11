import '../../../domain/models/app_user.dart';
import '../../../domain/models/group_tournament.dart';
import '../../../domain/tournament_engine/progress.dart';
import '../../../utils/result.dart';

/// Tournaments a community group runs, and their games. Organizers see
/// every tournament; members only the ones they play in.
abstract class GroupTournamentRepository {
  /// Newest first. Organizers get all of them; others only those they're
  /// on a team in.
  Stream<List<GroupTournament>> watchTournaments(
    String groupId, {
    required String uid,
    required bool organizer,
  });

  /// The group's tournaments as anyone signed in sees them, soonest last.
  Stream<List<TournamentListing>> watchListings(String groupId);

  /// Null if it's deleted or the user can't see it.
  Stream<GroupTournament?> watchTournament(String groupId, String id);

  /// In schedule order.
  Stream<List<GroupGame>> watchGames(String groupId, String tournamentId);

  /// Creates the tournament when [GroupTournament.isNew], otherwise saves
  /// its name, settings and teams, and keeps its public listing in step.
  /// Returns its id. Organizers only.
  Future<Result<String>> saveTournament(
    String groupId,
    GroupTournament tournament,
    AppUser by,
  );

  /// Replaces every game with [games] and marks the tournament scheduled.
  Future<Result<void>> publishSchedule(
    String groupId,
    GroupTournament tournament,
    List<GroupGame> games,
  );

  /// A captain reports (or, disagreeing, re-reports) a score; the other
  /// captain then confirms it.
  Future<Result<void>> reportScore(
    String groupId,
    String tournamentId,
    String gameId,
    ScoreReport report,
  );

  /// The other captain agrees with the report: the game is final, and
  /// [fills] move the teams on in the same write.
  Future<Result<void>> confirmScore(
    String groupId,
    String tournamentId,
    GroupGame game,
    List<SlotFill> fills,
  );

  /// An organizer sets the final score directly.
  Future<Result<void>> setFinalScore(
    String groupId,
    String tournamentId,
    String gameId, {
    required int scoreA,
    required int scoreB,
    required List<SlotFill> fills,
  });

  /// Writes teams into waiting games, e.g. bracket seeds from pools.
  Future<Result<void>> applyFills(
    String groupId,
    String tournamentId,
    List<SlotFill> fills,
  );

  Future<Result<void>> setStatus(
    String groupId,
    String tournamentId,
    TournamentStatus status,
  );

  /// Deletes the tournament and its games.
  Future<Result<void>> deleteTournament(String groupId, String tournamentId);
}
