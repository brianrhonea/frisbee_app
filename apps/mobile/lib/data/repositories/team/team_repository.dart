import '../../../domain/models/app_user.dart';
import '../../../domain/models/invite_code.dart';
import '../../../domain/models/pending_invite.dart';
import '../../../domain/models/roster_player.dart';
import '../../../domain/models/team.dart';
import '../../../utils/result.dart';

/// How far deleting a team has got: [done] of [total] steps, now on
/// [step] ("Deleting chat").
typedef DeleteProgress = ({int done, int total, String step});

/// Why a club team can't be made without the API: only the API checks
/// the owner is 16 or over (firestore.rules refuses club teams otherwise).
const clubTeamNeedsServerMessage =
    "Club teams need a connection to Stall 10's server, which checks "
    "everyone on them is 16 or over, and this version of the app doesn't "
    'have one. Update the app, or pick another level (college, youth, '
    'league or pickup).';

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

  /// Owner only: switches [changes]' optional sections on (true) or off
  /// (false); the others keep what they have.
  Future<Result<void>> setSections(
    String teamId,
    Map<OptionalSection, bool> changes,
  );

  /// Admins (manageTeam) only: turns the team's public page on or off
  /// ([Team.publicPage]), its listing with it. Through the API only.
  Future<Result<void>> setPublicPage(String teamId, bool on);

  /// Admins (manageTeam) turn a team's "Allow join requests" on or off
  /// ([Team.allowJoinRequests]), its listing with it; off declines the
  /// requests waiting. Through the API only.
  Future<Result<void>> setAllowJoinRequests(String teamId, bool on);

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

  /// Owner only: the permissions [uid] has of their own (the per-person
  /// switches; a [RolePreset] is a set of them), on top of their roles.
  /// Through the API only (`PUT /v1/teams/:id/members/:uid/permissions`).
  Future<Result<void>> setMemberPermissions(
    String teamId,
    String uid,
    Set<TeamPermission> permissions,
  );

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

  /// Deletes the team and everything in it, for its sole owner. [name] is
  /// what they typed to confirm it (the API checks it matches the team's
  /// name). It takes a while, so [onProgress] hears each step.
  Future<Result<void>> deleteTeam(
    Team team, {
    required String name,
    void Function(DeleteProgress progress)? onProgress,
  });

  // ---- School and club communities -------------------------------------
  // A team is in a community once both agree: the team names it (orgId)
  // and the community lists it (linkedTeams). The communities Cloud
  // Functions then add and remove members by role (Team.orgMembers).

  /// Creates a team inside [org] (whose admin [owner] is), listed at once
  /// with the community [roles] that get on it. Returns the team id.
  Future<Result<String>> createTeamInCommunity(
    NewTeam team,
    AppUser owner,
    Team org,
    Set<String> roles,
  );

  /// Asks to put [team] in community [org]; its admins answer.
  Future<Result<void>> requestCommunityLink(
    Team team,
    TeamListing org,
    AppUser by,
  );

  /// Takes [team] out of its community, or withdraws its request. People
  /// the community added leave it.
  Future<Result<void>> leaveCommunity(Team team);

  /// Whether [teamId]'s request to join [orgId] is still waiting.
  Stream<bool> watchLinkRequested(String orgId, String teamId);

  /// Teams asking to join community [orgId], oldest first.
  Stream<List<TeamLinkRequest>> watchLinkRequests(String orgId);

  /// Lists the asking team in [org], with the [roles] that get on it.
  Future<Result<void>> acceptLinkRequest(
    Team org,
    TeamLinkRequest request,
    Set<String> roles,
  );

  Future<Result<void>> declineLinkRequest(String orgId, String teamId);

  /// Changes which community roles get on a listed team.
  Future<Result<void>> saveLinkedTeam(String orgId, LinkedTeam team);

  /// Drops a team from the community; people it added leave the team.
  Future<Result<void>> unlinkTeam(String orgId, String teamId);

  /// Roster sorted by number, then name. Only team admins may pass
  /// [withStatus] to include the paid mark; without it, it's left false.
  Stream<List<RosterPlayer>> watchRoster(
    String teamId, {
    bool withStatus = false,
  });

  /// Creates the player when [RosterPlayer.id] is empty, otherwise updates
  /// it; the result is the player's id. The server ignores
  /// [RosterPlayer.userId] here: linking an account is [linkPlayer].
  Future<Result<String>> savePlayer(String teamId, RosterPlayer player);

  Future<Result<void>> deletePlayer(String teamId, String playerId);

  /// Admins (manageTeam) only: puts each roster spot in [lines] (by id) on
  /// the O-line, D-line or both, or takes its line away (null). Through
  /// the API only (`PUT /v1/teams/:id/roster-lines`).
  Future<Result<void>> setRosterLines(
    String teamId,
    Map<String, RosterLine?> lines,
  );

  /// Who's invited to the team and hasn't answered, newest first, for
  /// those who may invite people. Through the API only.
  Future<Result<List<PendingInvite>>> pendingInvites(String teamId);

  /// Takes back the invite to [uid] (someone who may invite people).
  Future<Result<void>> withdrawInvite(String teamId, String uid);

  /// Links roster player [playerId] to the account [uid], or unlinks it
  /// when null, so their stats show on that player's profile. Members may
  /// claim an unlinked player for themselves or unlink their own; admins
  /// may link anyone.
  Future<Result<void>> linkPlayer(String teamId, String playerId, String? uid);
}
