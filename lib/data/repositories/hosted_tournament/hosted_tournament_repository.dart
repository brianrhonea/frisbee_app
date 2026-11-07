import '../../../domain/models/app_user.dart';
import '../../../domain/models/group_tournament.dart';
import '../../../domain/models/hosted_tournament.dart';
import '../../../domain/tournament_engine/progress.dart';
import '../../../utils/result.dart';

/// Tournaments a team, group or school/club hosts (`tournaments/{id}`),
/// with their divisions, entries, bid fee payments and games.
///
/// Published tournaments, their divisions, entries and games are public
/// to anyone signed in; drafts only to the host's managers (Manage
/// events). Payments are for the host's managers and the paying team's
/// admins.
abstract class HostedTournamentRepository {
  /// Null if it's deleted or the user can't see it.
  Stream<HostedTournament?> watchTournament(String id);

  /// Every tournament [hostId] hosts, newest first. Drafts are included
  /// only when [manager] is true (rules hide them from everyone else).
  Stream<List<HostedTournament>> watchHostedBy(
    String hostId, {
    required bool manager,
  });

  /// The tournaments team [teamId] has entered, soonest first; for its
  /// members.
  Stream<List<EnteredTournament>> watchEnteredBy(String teamId);

  /// Published tournaments that haven't ended, soonest first.
  Stream<List<HostedTournament>> watchUpcoming({int limit = 50});

  Stream<List<TournamentDivision>> watchDivisions(String tournamentId);

  Stream<List<TournamentEntry>> watchEntries(String tournamentId);

  /// Every team's payment; host managers only.
  Stream<List<EntryPayment>> watchPayments(String tournamentId);

  /// One team's payment, for that team's admins.
  Stream<EntryPayment?> watchPayment(String tournamentId, String teamId);

  /// In schedule order.
  Stream<List<GroupGame>> watchGames(String tournamentId, String divisionId);

  /// Creates the tournament when [HostedTournament.isNew], otherwise saves
  /// it. Returns its id.
  Future<Result<String>> saveTournament(
    HostedTournament tournament,
    AppUser by,
  );

  /// Creates or saves a division and keeps the tournament's division list
  /// in step. Returns its id.
  Future<Result<String>> saveDivision(
    HostedTournament tournament,
    TournamentDivision division,
  );

  /// Removes a division with no games, and its entry in the tournament's
  /// list.
  Future<Result<void>> deleteDivision(
    HostedTournament tournament,
    String divisionId,
  );

  Future<Result<void>> setStatus(String tournamentId, HostedStatus status);

  /// The host invites a team, or a team admin applies.
  Future<Result<void>> saveEntry(String tournamentId, TournamentEntry entry);

  /// The host accepts an entry: it gets a seed (last) in its division and
  /// its captains report scores.
  Future<Result<void>> acceptEntry(
    String tournamentId,
    TournamentDivision division,
    TournamentEntry entry,
  );

  /// Sets an entry's status other than accepted (waitlist, decline,
  /// withdraw). If the team was seeded it leaves the seed list.
  Future<Result<void>> setEntryStatus(
    String tournamentId,
    TournamentEntry entry,
    EntryStatus status, {
    TournamentDivision? division,
  });

  /// Host managers mark a team paid or unpaid.
  Future<Result<void>> savePayment(String tournamentId, EntryPayment payment);

  /// Replaces a division's games with [games] (seeds and settings saved
  /// with them).
  Future<Result<void>> publishSchedule(
    String tournamentId,
    TournamentDivision division,
    List<GroupGame> games,
  );

  /// A captain reports a score; the other captain confirms it.
  Future<Result<void>> reportScore(
    String tournamentId,
    String divisionId,
    String gameId,
    ScoreReport report,
  );

  Future<Result<void>> confirmScore(
    String tournamentId,
    String divisionId,
    GroupGame game,
    List<SlotFill> fills,
  );

  /// A host manager sets the final score directly.
  Future<Result<void>> setFinalScore(
    String tournamentId,
    String divisionId,
    String gameId, {
    required int scoreA,
    required int scoreB,
    required List<SlotFill> fills,
  });

  Future<Result<void>> applyFills(
    String tournamentId,
    String divisionId,
    List<SlotFill> fills,
  );

  /// Deletes the tournament with its divisions, games, entries and
  /// payments.
  Future<Result<void>> deleteTournament(String tournamentId);
}
