import '../../../domain/models/app_user.dart';
import '../../../domain/models/invite_code.dart';
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

  /// The id of the team [inviteCode] joins, without joining it (for invite
  /// links). Fails if no team has that code, or it has expired.
  Future<Result<String>> resolveInviteCode(String inviteCode);

  /// Joins an open community group as a member, no code needed.
  Future<Result<void>> joinGroup(String teamId, AppUser user);

  /// Asks to join a group that requires approval.
  Future<Result<void>> requestToJoin(String teamId, AppUser user);

  /// Withdraws the user's own join request.
  Future<Result<void>> cancelJoinRequest(String teamId, String uid);

  /// Whether [uid] has a pending request to join [teamId].
  Stream<bool> watchMyJoinRequest(String teamId, String uid);

  /// Pending join requests, oldest first. Owners and organizers only.
  Stream<List<GroupJoinRequest>> watchJoinRequests(String teamId);

  /// Adds the requester as a member and clears the request.
  Future<Result<void>> approveJoinRequest(
    String teamId,
    GroupJoinRequest request,
  );

  Future<Result<void>> declineJoinRequest(String teamId, String uid);

  /// Invites [uid] to join [team]. Owners and organizers only; inviting
  /// again refreshes the invite.
  Future<Result<void>> inviteToTeam(Team team, String uid, AppUser from);

  /// [uid]'s pending invitations, newest first.
  Stream<List<TeamInvite>> watchMyInvites(String uid);

  /// Joins the invite's team as a player and clears the invite.
  Future<Result<void>> acceptInvite(TeamInvite invite, AppUser user);

  Future<Result<void>> declineInvite(String uid, String teamId);

  /// Saves the team's details and its public directory listing.
  Future<Result<void>> updateTeam(Team team);

  /// Teams in the public directory whose name or city words start with the
  /// words of [query].
  Future<Result<List<TeamListing>>> searchTeams(String query);

  /// The team's public directory listing; null if it has none yet.
  Stream<TeamListing?> watchListing(String teamId);

  /// Writes the team's directory listing from its details, e.g. for teams
  /// created before the directory existed. Owners, coaches and captains.
  Future<Result<void>> publishListing(Team team);

  /// Mints a short code that joins [teamId] as a player for
  /// [InviteCode.codeLifetime]. Owners, coaches and captains of a team (not
  /// a group); [uid] is theirs.
  Future<Result<InviteCode>> createInviteCode(String teamId, String uid);

  /// Mints a token for an invite link that joins [teamId] as a player
  /// until [expiry] passes. Same people as [createInviteCode].
  Future<Result<InviteCode>> createInviteLink(
    String teamId,
    String uid,
    InviteLinkExpiry expiry,
  );

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

  /// Owner only: replaces [team]'s custom roles and who has them, saving
  /// each member's permissions with them ([rolesData]).
  Future<Result<void>> saveRoles(
    Team team, {
    required Map<String, CustomRole> roles,
    required Map<String, Set<String>> memberRoles,
  });

  /// Moves members on the legacy coach and captain tiers into custom
  /// roles with the same powers ([Team.legacyTierRoles]): gives them the
  /// roles, opens every chat room and folder that was open to their tier
  /// to their role too, then makes them players. Each step is safe to
  /// repeat, so a failed run is finished the next time.
  Future<Result<void>> migrateTiersToRoles(Team team);

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

  /// Links roster player [playerId] to the account [uid], or unlinks it
  /// when null, so their stats show on that player's profile. Members may
  /// claim an unlinked player for themselves or unlink their own; admins
  /// may link anyone.
  Future<Result<void>> linkPlayer(String teamId, String playerId, String? uid);
}
