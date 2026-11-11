import '../../../domain/models/app_user.dart';
import '../../../domain/models/group_tournament.dart';
import '../../../domain/models/hosted_tournament.dart';
import '../../../domain/models/live_draft.dart';
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

  /// Every player's signup, by name; host managers only (skill and gender
  /// are private).
  Stream<List<PlayerSignup>> watchSignups(String tournamentId);

  /// One player's own signup; null if they haven't signed up.
  Stream<PlayerSignup?> watchSignup(String tournamentId, String uid);

  /// A division's captains' draft board; null until it starts.
  Stream<LiveDraft?> watchDraft(String tournamentId, String divisionId);

  /// Everyone's skill and gender in a draft, for the host and its
  /// captains. Null for anyone else, who isn't allowed to read it.
  Stream<Map<String, DraftDetail>?> watchDraftDetails(
    String tournamentId,
    String divisionId,
  );

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

  /// Host managers mark a team (or, for player entry, a player: the id is
  /// their uid) paid or unpaid.
  Future<Result<void>> savePayment(String tournamentId, EntryPayment payment);

  /// A player signs up, or changes their answers or signs back up after
  /// withdrawing. Rules only allow it while registration is open.
  Future<Result<void>> saveSignup(String tournamentId, PlayerSignup signup);

  /// A host manager accepts, waitlists or declines a signup, or the player
  /// withdraws it.
  Future<Result<void>> setSignupStatus(
    String tournamentId,
    String uid,
    SignupStatus status,
  );

  /// Saves the teams drafted from signups: the division's `teams`, its
  /// seeds (team ids, in order) and each team's captain as the one who
  /// reports its scores, in a single write.
  Future<Result<void>> saveDraftTeams(
    String tournamentId,
    TournamentDivision division,
    List<TournamentTeam> teams,
  );

  /// Replaces a division's games with [games] (seeds and settings saved
  /// with them).
  Future<Result<void>> publishSchedule(
    String tournamentId,
    TournamentDivision division,
    List<GroupGame> games,
  );

  /// A league's host turns the drafted teams into real teams (the server
  /// does it, since the app can't put other people on a team it creates):
  /// each captain owns theirs and the other players are its members. The
  /// division's teams, seeds and captains then use the real teams' ids.
  /// Only before the schedule is published; asking again changes nothing.
  Future<Result<void>> createLeagueTeams(
    String tournamentId,
    String divisionId,
  );

  /// The host starts a captains' draft with [captainIds] (the server
  /// shuffles them into a random order). [pickSeconds] 0 means no limit.
  Future<Result<void>> startDraft(
    String tournamentId,
    String divisionId,
    List<String> captainIds, {
    int pickSeconds = 0,
  });

  /// The captain on the clock (or the host) picks [uid].
  Future<Result<void>> draftPick(
    String tournamentId,
    String divisionId,
    String uid,
  );

  /// The host's pause, resume, undo and auto-pick (for a captain who's
  /// out of time).
  Future<Result<void>> draftControl(
    String tournamentId,
    String divisionId,
    DraftControl action,
  );

  /// The host turns the picks into the division's teams.
  Future<Result<void>> finishDraft(String tournamentId, String divisionId);

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

  /// Deletes the tournament with its divisions, games, entries, signups,
  /// drafts and payments.
  Future<Result<void>> deleteTournament(String tournamentId);
}

/// What the host can do to a running draft. Cancel deletes it (before
/// it's finished) so it can start over.
enum DraftControl { pause, resume, undo, autopick, cancel }
