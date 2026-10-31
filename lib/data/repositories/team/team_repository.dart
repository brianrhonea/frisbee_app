import '../../../domain/models/app_user.dart';
import '../../../domain/models/roster_player.dart';
import '../../../domain/models/team.dart';
import '../../../utils/result.dart';

abstract class TeamRepository {
  /// Teams the user is a member of, sorted by name.
  Stream<List<Team>> watchMyTeams(String uid);

  /// Emits null if the team is deleted or the user loses access.
  Stream<Team?> watchTeam(String teamId);

  /// Returns the new team id.
  Future<Result<String>> createTeam(NewTeam team, AppUser owner);

  /// Joins the team with [inviteCode] as a player. Returns the team id.
  Future<Result<String>> joinTeam(String inviteCode, AppUser user);

  Future<Result<void>> updateTeam(Team team);

  /// The code other users enter to join as a player. Kept off the team so
  /// only owners, coaches and captains can read it; others get an error.
  Stream<String?> watchInviteCode(String teamId);

  /// Replaces the invite code; the old one stops working. Owner only.
  Future<Result<void>> regenerateInviteCode(String teamId);

  Future<Result<void>> setMemberRole(String teamId, String uid, TeamRole role);

  /// Gives a player stats access, or takes it away.
  Future<Result<void>> setStatKeeper(
    String teamId,
    String uid, {
    required bool on,
  });

  /// Makes [newOwnerUid] the owner; [ownerUid], the current owner, becomes
  /// a player.
  Future<Result<void>> transferOwnership(
    String teamId, {
    required String ownerUid,
    required String newOwnerUid,
  });

  /// Removes a member; also used by a member to leave the team.
  Future<Result<void>> removeMember(String teamId, String uid);

  Future<Result<void>> deleteTeam(Team team);

  /// Links the team to its USA Ultimate page, or unlinks it when [url] is
  /// null.
  Future<Result<void>> linkUsauTeam(String teamId, {String? url, String? name});

  /// Writes a roster sync in one batch and stamps the sync time.
  Future<Result<void>> applyRosterSync(
    String teamId,
    List<RosterPlayer> players,
  );

  /// Roster sorted by number, then name. Only team admins may pass
  /// [withStatus] to include paid and USA Ultimate status; without it those
  /// fields are left empty.
  Stream<List<RosterPlayer>> watchRoster(
    String teamId, {
    bool withStatus = false,
  });

  /// Creates the player when [RosterPlayer.id] is empty, otherwise updates it.
  Future<Result<void>> savePlayer(String teamId, RosterPlayer player);

  Future<Result<void>> deletePlayer(String teamId, String playerId);
}
