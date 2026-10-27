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

  Future<Result<void>> regenerateInviteCode(Team team);

  Future<Result<void>> setMemberRole(String teamId, String uid, TeamRole role);

  /// Removes a member; also used by a member to leave the team.
  Future<Result<void>> removeMember(String teamId, String uid);

  Future<Result<void>> deleteTeam(Team team);

  Stream<List<RosterPlayer>> watchRoster(String teamId);

  /// Creates the player when [RosterPlayer.id] is empty, otherwise updates it.
  Future<Result<void>> savePlayer(String teamId, RosterPlayer player);

  Future<Result<void>> deletePlayer(String teamId, String playerId);
}
