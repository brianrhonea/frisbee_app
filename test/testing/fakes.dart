import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:frisbee_app/data/repositories/auth/auth_repository.dart';
import 'package:frisbee_app/data/repositories/chat/chat_repository.dart';
import 'package:frisbee_app/data/repositories/direct_message/direct_message_repository.dart';
import 'package:frisbee_app/data/repositories/event/event_repository.dart';
import 'package:frisbee_app/data/repositories/notification/notification_repository.dart';
import 'package:frisbee_app/data/repositories/playbook/play_repository.dart';
import 'package:frisbee_app/data/repositories/profile/profile_repository.dart';
import 'package:frisbee_app/data/repositories/ranking/ranking_repository.dart';
import 'package:frisbee_app/data/repositories/stats/stats_repository.dart';
import 'package:frisbee_app/data/repositories/team/team_repository.dart';
import 'package:frisbee_app/data/repositories/team_post/team_post_repository.dart';
import 'package:frisbee_app/data/repositories/theme/theme_repository.dart';
import 'package:frisbee_app/data/repositories/tournament/tournament_repository.dart';
import 'package:frisbee_app/data/repositories/usau_schedule/usau_schedule_repository.dart';
import 'package:frisbee_app/data/services/file_picker_service.dart';
import 'package:frisbee_app/data/services/image_compressor.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/data/services/account_service.dart';
import 'package:frisbee_app/domain/models/username.dart';
import 'package:frisbee_app/domain/models/chat.dart';
import 'package:frisbee_app/domain/models/direct_message.dart';
import 'package:frisbee_app/domain/models/invite_code.dart';
import 'package:frisbee_app/domain/models/notification.dart';
import 'package:frisbee_app/domain/models/play.dart';
import 'package:frisbee_app/domain/models/player_profile.dart';
import 'package:frisbee_app/domain/models/ranking.dart';
import 'package:frisbee_app/domain/models/roster_player.dart';
import 'package:frisbee_app/domain/models/stats.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/team_event.dart';
import 'package:frisbee_app/domain/models/team_post.dart';
import 'package:frisbee_app/domain/models/tournament.dart';
import 'package:frisbee_app/domain/models/usau_schedule.dart';
import 'package:frisbee_app/utils/result.dart';

const testUser = AppUser(uid: 'u1', email: 'a@b.com', displayName: 'Alex');

class FakeAuthRepository extends AuthRepository {
  FakeAuthRepository({AppUser? user, bool ready = true})
    : _user = user,
      _ready = ready;

  AppUser? _user;
  bool _ready;
  Exception? nextError;

  @override
  AppUser? get currentUser => _user;

  @override
  bool get isReady => _ready;

  void setUser(AppUser? user, {bool ready = true}) {
    _user = user;
    _ready = ready;
    notifyListeners();
  }

  Future<Result<void>> _run(void Function() action) async {
    final e = nextError;
    if (e != null) {
      nextError = null;
      return Result.error(e);
    }
    try {
      action();
    } on Exception catch (e) {
      return Result.error(e);
    }
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> signInWithEmail(String email, String password) =>
      _run(() => setUser(AppUser(uid: 'u1', email: email)));

  /// Username → email, for signing in with a username.
  final emailsByUsername = <String, String>{};

  @override
  Future<Result<void>> signIn(String emailOrUsername, String password) {
    final id = emailOrUsername.trim();
    if (isEmail(id)) return signInWithEmail(id, password);
    final email = emailsByUsername[Username.normalize(id)];
    if (email == null) {
      return Future.value(
        const Result.error(
          UsernameSignInException('Incorrect username or password.'),
        ),
      );
    }
    return signInWithEmail(email, password);
  }

  @override
  Future<Result<void>> signUpWithEmail({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String username,
  }) async {
    if (takenUsernames.contains(Username.normalize(username))) {
      return Result.error(UsernameTakenException(username));
    }
    final result = await _run(
      () => setUser(
        AppUser(uid: 'u1', email: email, displayName: '$firstName $lastName'),
      ),
    );
    if (result is Error) return result;
    return claimUsername(username);
  }

  /// Usernames someone else has.
  final takenUsernames = <String>{};

  /// Whether the signed-in user is still to pick one; off so most tests
  /// go straight in.
  bool usernameMissing = false;

  @override
  bool get needsUsername => _user != null && usernameMissing;

  @override
  Future<Result<bool>> isUsernameAvailable(String username) async {
    final name = Username.normalize(username);
    return Result.ok(
      Username.problem(name) == null && !takenUsernames.contains(name),
    );
  }

  @override
  Future<Result<void>> claimUsername(String username) async {
    final name = Username.normalize(username);
    if (takenUsernames.contains(name)) {
      return Result.error(UsernameTakenException(name));
    }
    takenUsernames.add(name);
    usernameMissing = false;
    setUser(_user?.withUsername(name));
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> signInWithGoogle() => _run(() => setUser(testUser));

  @override
  Future<Result<void>> signInWithApple() => _run(() => setUser(testUser));

  @override
  Future<Result<void>> sendPasswordReset(String email) => _run(() {});

  @override
  Future<Result<void>> updateDisplayName(String name) => _run(
    () => setUser(
      AppUser(uid: _user!.uid, email: _user!.email, displayName: name),
    ),
  );

  @override
  Future<Result<void>> signOut() => _run(() => setUser(null));

  @override
  Future<Result<void>> deleteAccount() => _run(() {
    if (!reauthenticated) throw Exception('Sign in again first.');
    deleted = true;
    _signedOutNotice = 'Account deleted successfully';
    setUser(null);
  });

  /// What [reauthMethod] says; password by default.
  SignInMethod? method = SignInMethod.password;

  /// The password [reauthenticate] accepts.
  String password = 'secret';
  bool reauthenticated = false;
  bool deleted = false;

  @override
  SignInMethod? get reauthMethod => currentUser == null ? null : method;

  @override
  Future<Result<void>> changePassword({
    required String current,
    required String next,
  }) => _run(() {
    if (current != password) throw Exception('Incorrect email or password.');
    password = next;
  });

  @override
  Future<Result<void>> reauthenticate({String? password}) => _run(() {
    if (method == SignInMethod.password && password != this.password) {
      throw Exception('Incorrect email or password.');
    }
    reauthenticated = true;
  });

  String? _signedOutNotice;

  @override
  String? get signedOutNotice => _signedOutNotice;

  @override
  void clearSignedOutNotice() => _signedOutNotice = null;
}

class FakeTeamRepository implements TeamRepository {
  final teams = <String, Team>{};
  final roster = <String, List<RosterPlayer>>{};
  final _teamsController = StreamController<void>.broadcast();
  String? joinedCode;

  /// Minted codes and link tokens by code. Every team also takes `CODE`
  /// plus its id, which never expires, so join tests needn't mint one.
  final inviteCodes = <String, InviteCode>{};

  /// Links minted, with how long each lasts.
  final linkExpiries = <String, InviteLinkExpiry>{};

  /// Set to fail minting, e.g. for someone the rules would refuse.
  Exception? mintError;

  var _minted = 0;

  /// The team [code] joins, or an error if it's unknown or expired.
  Result<String> _teamForCode(String code) {
    final minted = inviteCodes[code];
    if (minted != null) {
      return DateTime.now().isBefore(minted.expiresAt)
          ? Result.ok(minted.teamId)
          : Result.error(Exception('That invite has expired.'));
    }
    final team = teams.values.where((t) => 'CODE${t.id}' == code).firstOrNull;
    return team == null
        ? Result.error(Exception('No team found for that invite code.'))
        : Result.ok(team.id);
  }

  Future<Result<InviteCode>> _mint(
    String teamId,
    String code,
    Duration ttl,
  ) async {
    if (mintError case final e?) return Result.error(e);
    final minted = InviteCode(
      code: code,
      teamId: teamId,
      expiresAt: DateTime.now().add(ttl),
    );
    inviteCodes[code] = minted;
    return Result.ok(minted);
  }

  void _emit() {
    _syncCommunities();
    _teamsController.add(null);
  }

  /// teamId → community id → waiting link request.
  final linkRequests = <String, Map<String, TeamLinkRequest>>{};

  /// What the communities Cloud Functions do: link teams both sides agree
  /// on, and keep their members in step with the community's roles.
  void _syncCommunities() {
    for (final org in teams.values.where((t) => t.isOrganization).toList()) {
      for (final t in teams.values.where((t) => t.orgId == org.id).toList()) {
        final link = org.linkedTeams[t.id];
        final cur = teams[t.id]!;
        if (link == null) {
          if (!cur.orgLinked) continue;
          teams[t.id] = _without(cur, cur.orgMembers).copyWith(
            orgId: () => null,
            orgName: '',
            orgLinked: false,
            orgMembers: const {},
          );
          continue;
        }
        final want = {
          for (final e in org.memberRoles.entries)
            if (org.members.containsKey(e.key) &&
                e.value.any(link.roles.contains))
              e.key,
        };
        final add = want.where((u) => !cur.members.containsKey(u));
        final drop = cur.orgMembers.where((u) => !want.contains(u)).toSet();
        final next = _without(cur, drop);
        teams[t.id] = next.copyWith(
          members: {...next.members, for (final u in add) u: TeamRole.player},
          memberNames: {
            ...next.memberNames,
            for (final u in add) u: org.nameOf(u),
          },
          orgLinked: true,
          orgName: org.name,
          orgMembers: {...cur.orgMembers.difference(drop), ...add},
        );
        _mirror(t.id, org);
      }
    }
  }

  /// Team copies of community roles go to exactly the members holding
  /// the community role (communities functions' mirrorUpdate).
  void _mirror(String teamId, Team org) {
    final t = teams[teamId]!;
    if (t.orgRoles.isEmpty) return;
    final copies = t.orgRoles.keys.toSet();
    final memberRoles = <String, Set<String>>{};
    for (final uid in t.members.keys) {
      final held = org.members.containsKey(uid)
          ? org.memberRoles[uid] ?? const <String>{}
          : const <String>{};
      final roles = {
        for (final r in t.memberRoles[uid] ?? const <String>{})
          if (!copies.contains(r)) r,
        for (final e in t.orgRoles.entries)
          if (held.contains(e.value) && t.roles.containsKey(e.key)) e.key,
      };
      if (roles.isNotEmpty) memberRoles[uid] = roles;
    }
    teams[teamId] = t.copyWith(
      memberRoles: memberRoles,
      memberPerms: memberPermsFor(memberRoles, t.roles),
    );
  }

  Team _without(Team t, Set<String> uids) => t.copyWith(
    members: {
      for (final e in t.members.entries)
        if (!uids.contains(e.key) || e.value == TeamRole.owner) e.key: e.value,
    },
    memberRoles: {
      for (final e in t.memberRoles.entries)
        if (!uids.contains(e.key)) e.key: e.value,
    },
  );

  @override
  Future<Result<String>> createTeamInCommunity(
    NewTeam team,
    AppUser owner,
    Team org,
    Set<String> roles,
  ) async {
    final made = await createTeam(team.inCommunity(org), owner);
    final id = (made as Ok<String>).value;
    final o = teams[org.id]!;
    teams[org.id] = o.copyWith(
      linkedTeams: {
        ...o.linkedTeams,
        id: LinkedTeam(
          id: id,
          name: team.name,
          division: team.division,
          roles: roles,
        ),
      },
    );
    _emit();
    return made;
  }

  @override
  Future<Result<void>> requestCommunityLink(
    Team team,
    TeamListing org,
    AppUser by,
  ) async {
    teams[team.id] = teams[team.id]!.copyWith(
      orgId: () => org.id,
      orgName: org.name,
    );
    (linkRequests[org.id] ??= {})[team.id] = TeamLinkRequest(
      teamId: team.id,
      teamName: team.name,
      division: team.division,
      requestedBy: by.uid,
      requestedByName: by.label,
    );
    _emit();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> leaveCommunity(Team team) async {
    final cur = teams[team.id]!;
    if (cur.orgId case final orgId?) linkRequests[orgId]?.remove(team.id);
    final org = teams[cur.orgId];
    if (org != null) {
      teams[org.id] = org.copyWith(
        linkedTeams: {...org.linkedTeams}..remove(team.id),
      );
    }
    teams[team.id] = _without(cur, cur.orgMembers).copyWith(
      orgId: () => null,
      orgName: '',
      orgLinked: false,
      orgMembers: const {},
    );
    _emit();
    return const Result.ok(null);
  }

  @override
  Stream<bool> watchLinkRequested(String orgId, String teamId) async* {
    yield linkRequests[orgId]?.containsKey(teamId) ?? false;
    yield* _teamsController.stream.map(
      (_) => linkRequests[orgId]?.containsKey(teamId) ?? false,
    );
  }

  @override
  Stream<List<TeamLinkRequest>> watchLinkRequests(String orgId) async* {
    yield [...?linkRequests[orgId]?.values];
    yield* _teamsController.stream.map(
      (_) => [...?linkRequests[orgId]?.values],
    );
  }

  @override
  Future<Result<void>> acceptLinkRequest(
    Team org,
    TeamLinkRequest request,
    Set<String> roles,
  ) async {
    linkRequests[org.id]?.remove(request.teamId);
    return saveLinkedTeam(
      org.id,
      LinkedTeam(
        id: request.teamId,
        name: request.teamName,
        division: request.division,
        roles: roles,
      ),
    );
  }

  @override
  Future<Result<void>> declineLinkRequest(String orgId, String teamId) async {
    linkRequests[orgId]?.remove(teamId);
    _emit();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> saveLinkedTeam(String orgId, LinkedTeam team) async {
    final o = teams[orgId]!;
    teams[orgId] = o.copyWith(linkedTeams: {...o.linkedTeams, team.id: team});
    _emit();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> unlinkTeam(String orgId, String teamId) async {
    final o = teams[orgId]!;
    teams[orgId] = o.copyWith(linkedTeams: {...o.linkedTeams}..remove(teamId));
    _emit();
    return const Result.ok(null);
  }

  @override
  Stream<List<Team>> watchMyTeams(String uid) async* {
    List<Team> mine() =>
        teams.values.where((t) => t.members.containsKey(uid)).toList();
    yield mine();
    yield* _teamsController.stream.map((_) => mine());
  }

  @override
  Stream<Team?> watchTeam(String teamId) async* {
    yield teams[teamId];
    yield* _teamsController.stream.map((_) => teams[teamId]);
  }

  @override
  Future<Result<String>> createTeam(NewTeam team, AppUser owner) async {
    final id = 't${teams.length + 1}';
    teams[id] = Team(
      id: id,
      name: team.name,
      division: team.division,
      level: team.level,
      city: team.city,
      ownerId: owner.uid,
      members: {owner.uid: TeamRole.owner},
      kind: team.kind,
      description: team.description,
      requiresApproval: team.requiresApproval,
      location: team.location,
      orgId: team.orgId,
      orgName: team.orgName,
    );
    if (team.kind.isGroupLike) {
      listings[id] = team.listing(id);
    }
    _emit();
    return Result.ok(id);
  }

  /// teamId → pending join requests.
  final joinRequests = <String, List<GroupJoinRequest>>{};

  void _addMember(String teamId, String uid, String name) {
    final t = teams[teamId]!;
    teams[teamId] = t.copyWith(
      members: {...t.members, uid: TeamRole.player},
      memberNames: {...t.memberNames, uid: name},
    );
  }

  @override
  Future<Result<void>> joinGroup(String teamId, AppUser user) async {
    final t = teams[teamId];
    if (t == null || !t.isCommunity || t.requiresApproval) {
      return Result.error(Exception('permission-denied'));
    }
    _addMember(teamId, user.uid, user.label);
    _emit();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> requestToJoin(String teamId, AppUser user) async {
    (joinRequests[teamId] ??= []).add(
      GroupJoinRequest(uid: user.uid, name: user.label),
    );
    _emit();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> cancelJoinRequest(String teamId, String uid) =>
      declineJoinRequest(teamId, uid);

  @override
  Stream<bool> watchMyJoinRequest(String teamId, String uid) async* {
    bool mine() => (joinRequests[teamId] ?? []).any((r) => r.uid == uid);
    yield mine();
    yield* _teamsController.stream.map((_) => mine());
  }

  @override
  Stream<List<GroupJoinRequest>> watchJoinRequests(String teamId) async* {
    yield [...?joinRequests[teamId]];
    yield* _teamsController.stream.map((_) => [...?joinRequests[teamId]]);
  }

  @override
  Future<Result<void>> approveJoinRequest(
    String teamId,
    GroupJoinRequest request,
  ) async {
    _addMember(teamId, request.uid, request.name);
    joinRequests[teamId]?.removeWhere((r) => r.uid == request.uid);
    _emit();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> declineJoinRequest(String teamId, String uid) async {
    joinRequests[teamId]?.removeWhere((r) => r.uid == uid);
    _emit();
    return const Result.ok(null);
  }

  /// uid → pending invitations.
  final invites = <String, List<TeamInvite>>{};

  @override
  Future<Result<void>> inviteToTeam(Team team, String uid, AppUser from) async {
    final mine = invites[uid] ??= [];
    mine
      ..removeWhere((i) => i.teamId == team.id)
      ..insert(
        0,
        TeamInvite(
          teamId: team.id,
          teamName: team.name,
          kind: team.kind,
          invitedBy: from.uid,
          invitedByName: from.label,
        ),
      );
    _emit();
    return const Result.ok(null);
  }

  @override
  Stream<List<TeamInvite>> watchMyInvites(String uid) async* {
    List<TeamInvite> mine() => List.of(invites[uid] ?? const []);
    yield mine();
    yield* _teamsController.stream.map((_) => mine());
  }

  @override
  Future<Result<void>> acceptInvite(TeamInvite invite, AppUser user) async {
    if (!teams.containsKey(invite.teamId)) {
      return Result.error(Exception('Team not found'));
    }
    _addMember(invite.teamId, user.uid, user.label);
    invites[user.uid]?.removeWhere((i) => i.teamId == invite.teamId);
    _emit();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> declineInvite(String uid, String teamId) async {
    invites[uid]?.removeWhere((i) => i.teamId == teamId);
    _emit();
    return const Result.ok(null);
  }

  @override
  Future<Result<String>> resolveInviteCode(String inviteCode) async =>
      _teamForCode(inviteCode);

  @override
  Future<Result<String>> joinTeam(String inviteCode, AppUser user) async {
    joinedCode = inviteCode;
    final found = _teamForCode(inviteCode);
    if (found case Error(:final error)) return Result.error(error);
    final team = teams[(found as Ok<String>).value];
    if (team == null) return Result.error(Exception('No team'));
    teams[team.id] = Team(
      id: team.id,
      name: team.name,
      division: team.division,
      level: team.level,
      ownerId: team.ownerId,
      members: {...team.members, user.uid: TeamRole.player},
    );
    _emit();
    return Result.ok(team.id);
  }

  @override
  Future<Result<void>> updateTeam(Team team) async {
    teams[team.id] = team;
    listings[team.id] = TeamListing.of(team);
    _emit();
    return const Result.ok(null);
  }

  /// The public team directory; teams appear here only once listed.
  final listings = <String, TeamListing>{};

  /// Teams whose listing was (re)published.
  final published = <String>[];

  @override
  Future<Result<List<TeamListing>>> searchTeams(String query) async =>
      Result.ok([
        for (final l in listings.values)
          if (l.matches(query)) l,
      ]);

  @override
  Stream<TeamListing?> watchListing(String teamId) async* {
    yield listings[teamId];
    yield* _teamsController.stream.map((_) => listings[teamId]);
  }

  @override
  Future<Result<void>> publishListing(Team team) async {
    published.add(team.id);
    listings[team.id] = TeamListing.of(team);
    _emit();
    return const Result.ok(null);
  }

  @override
  Future<Result<InviteCode>> createInviteCode(String teamId, String uid) =>
      _mint(teamId, 'C${++_minted}$teamId', InviteCode.codeLifetime);

  @override
  Future<Result<InviteCode>> createInviteLink(
    String teamId,
    String uid,
    InviteLinkExpiry expiry,
  ) {
    final token = 'L${++_minted}$teamId';
    linkExpiries[token] = expiry;
    return _mint(teamId, token, expiry.duration);
  }

  @override
  Future<Result<void>> setMemberRole(
    String teamId,
    String uid,
    TeamRole role,
  ) async => const Result.ok(null);

  @override
  Future<Result<void>> setStatKeeper(
    String teamId,
    String uid, {
    required bool on,
  }) async {
    final t = teams[teamId];
    if (t == null) return Result.error(Exception('No team'));
    teams[teamId] = Team(
      id: t.id,
      name: t.name,
      division: t.division,
      level: t.level,
      city: t.city,
      ownerId: t.ownerId,
      members: t.members,
      memberNames: t.memberNames,
      statKeepers: on
          ? {...t.statKeepers, uid}
          : ({...t.statKeepers}..remove(uid)),
    );
    _emit();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> transferOwnership(
    String teamId, {
    required String ownerUid,
    required String newOwnerUid,
  }) async {
    final t = teams[teamId];
    if (t == null) return Result.error(Exception('No team'));
    teams[teamId] = Team(
      id: t.id,
      name: t.name,
      division: t.division,
      level: t.level,
      city: t.city,
      ownerId: newOwnerUid,
      members: {
        ...t.members,
        newOwnerUid: TeamRole.owner,
        ownerUid: TeamRole.player,
      },
      memberNames: t.memberNames,
      statKeepers: t.statKeepers,
    );
    _emit();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> removeMember(String teamId, String uid) async =>
      const Result.ok(null);

  int rolesSaved = 0;

  @override
  Future<Result<void>> saveRoles(
    Team team, {
    required Map<String, CustomRole> roles,
    required Map<String, Set<String>> memberRoles,
  }) async {
    final t = teams[team.id];
    if (t == null) return Result.error(Exception('No team'));
    final cleaned = cleanMemberRoles(memberRoles, roles, t.members.keys);
    teams[team.id] = t.copyWith(
      roles: roles,
      memberRoles: cleaned,
      memberPerms: memberPermsFor(cleaned, roles),
    );
    rolesSaved++;
    _emit();
    return const Result.ok(null);
  }

  int migrations = 0;

  @override
  Future<Result<void>> migrateTiersToRoles(Team team) async {
    final t = teams[team.id];
    if (t == null) return Result.error(Exception('No team'));
    final tierRoles = t.legacyTierRoles();
    final roles = {...t.roles, for (final r in tierRoles.values) r.id: r};
    final memberRoles = {
      ...t.memberRoles,
      for (final e in t.members.entries)
        if (tierRoles[e.value] case final r?)
          e.key: {...?t.memberRoles[e.key], r.id},
    };
    final cleaned = cleanMemberRoles(memberRoles, roles, t.members.keys);
    teams[team.id] = t.copyWith(
      roles: roles,
      memberRoles: cleaned,
      memberPerms: memberPermsFor(cleaned, roles),
      members: {
        for (final e in t.members.entries)
          e.key: tierRoles.containsKey(e.value) ? TeamRole.player : e.value,
      },
    );
    migrations++;
    _emit();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> deleteTeam(Team team) async {
    teams.remove(team.id);
    _emit();
    return const Result.ok(null);
  }

  final syncs = <List<RosterPlayer>>[];

  @override
  Future<Result<void>> linkUsauTeam(
    String teamId, {
    String? url,
    String? name,
  }) async {
    final t = teams[teamId];
    if (t == null) return Result.error(Exception('No team'));
    teams[teamId] = Team(
      id: t.id,
      name: t.name,
      division: t.division,
      level: t.level,
      city: t.city,
      ownerId: t.ownerId,
      members: t.members,
      memberNames: t.memberNames,
      statKeepers: t.statKeepers,
      usauUrl: url,
      usauName: url == null ? null : name,
    );
    _emit();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> applyRosterSync(
    String teamId,
    List<RosterPlayer> players,
  ) async {
    syncs.add(players);
    return const Result.ok(null);
  }

  final _rosterChanges = StreamController<void>.broadcast();

  List<RosterPlayer> _rosterOf(String teamId, bool withStatus) => [
    for (final p in roster[teamId] ?? const <RosterPlayer>[])
      withStatus
          ? p
          : RosterPlayer(
              id: p.id,
              name: p.name,
              number: p.number,
              position: p.position,
              userId: p.userId,
            ),
  ];

  @override
  Stream<List<RosterPlayer>> watchRoster(
    String teamId, {
    bool withStatus = false,
  }) async* {
    yield _rosterOf(teamId, withStatus);
    yield* _rosterChanges.stream.map((_) => _rosterOf(teamId, withStatus));
  }

  /// (teamId, playerId, uid) for each [linkPlayer] call.
  final links = <(String, String, String?)>[];

  @override
  Future<Result<void>> linkPlayer(
    String teamId,
    String playerId,
    String? uid,
  ) async {
    links.add((teamId, playerId, uid));
    final list = roster[teamId] ?? const <RosterPlayer>[];
    roster[teamId] = [
      for (final p in list)
        p.id == playerId
            ? RosterPlayer(
                id: p.id,
                name: p.name,
                number: p.number,
                position: p.position,
                userId: uid,
                onUsau: p.onUsau,
                paid: p.paid,
              )
            : p,
    ];
    _rosterChanges.add(null);
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> savePlayer(String teamId, RosterPlayer player) async =>
      const Result.ok(null);

  @override
  Future<Result<void>> deletePlayer(String teamId, String playerId) async =>
      const Result.ok(null);
}

class FakePlayRepository implements PlayRepository {
  final plays = <String, Play>{};

  /// Per-team plays; teams not listed here see [plays].
  final byTeam = <String, List<Play>>{};
  int saves = 0;

  @override
  Stream<List<Play>> watchPlays(String teamId) =>
      Stream.value(byTeam[teamId] ?? plays.values.toList());

  @override
  Future<Result<Play>> getPlay(String teamId, String playId) async {
    final p = plays[playId];
    return p == null ? Result.error(Exception('missing')) : Result.ok(p);
  }

  @override
  Future<Result<String>> savePlay(String teamId, Play play, String uid) async {
    saves++;
    final id = play.isNew ? 'p${plays.length + 1}' : play.id;
    plays[id] = play.copyWith(id: id);
    return Result.ok(id);
  }

  @override
  Future<Result<void>> deletePlay(String teamId, String playId) async {
    plays.remove(playId);
    return const Result.ok(null);
  }
}

class FakeTournamentRepository implements TournamentRepository {
  FakeTournamentRepository(this.tournaments);

  final List<Tournament> tournaments;

  @override
  Stream<List<Tournament>> watchTournaments() => Stream.value(tournaments);
}

class FakeUsauScheduleRepository implements UsauScheduleRepository {
  FakeUsauScheduleRepository({this.schedules = const {}});

  /// Each division's schedule; a division mapped to null fails to load.
  final Map<UsauDivision, UsauDivisionSchedule?> schedules;
  final requests = <(UsauDivision, bool)>[];

  /// When set, schedule loads wait for it to complete.
  Completer<void>? hold;

  @override
  Future<Result<List<UsauDivision>>> getDivisions(String eventUrl) async =>
      Result.ok(schedules.keys.toList());

  @override
  Future<Result<UsauDivisionSchedule>> getSchedule(
    String eventUrl,
    UsauDivision division, {
    bool refresh = false,
  }) async {
    requests.add((division, refresh));
    await hold?.future;
    final s = schedules[division];
    return s == null ? Result.error(Exception('No schedule')) : Result.ok(s);
  }
}

Team teamWith(
  Map<String, TeamRole> members, {
  String id = 't1',
  Set<String> statKeepers = const {},
}) => Team(
  id: id,
  statKeepers: statKeepers,
  name: 'Team',
  division: Division.mixed,
  level: CompetitionLevel.club,
  ownerId: members.entries.firstWhere((e) => e.value == TeamRole.owner).key,
  members: members,
);

class FakeRankingRepository implements RankingRepository {
  FakeRankingRepository(this.divisions);

  final List<RankingDivision> divisions;

  @override
  Stream<List<RankingDivision>> watchDivisions() => Stream.value(divisions);
}

class FakeEventRepository implements EventRepository {
  final events = <String, TeamEvent>{};

  /// Per-team events for multi-team tests; teams not listed here see
  /// [events].
  final byTeam = <String, Map<String, TeamEvent>>{};
  final _changes = StreamController<void>.broadcast();
  bool? lastClearVotes;

  void emit() => _changes.add(null);

  List<TeamEvent> _sorted(String teamId) =>
      (byTeam[teamId] ?? events).values.toList()
        ..sort((a, b) => a.startsAt.compareTo(b.startsAt));

  @override
  Stream<List<TeamEvent>> watchEvents(
    String teamId, {
    DateTime? since,
    Set<String>? audience,
  }) async* {
    sinceRequests.add(since);
    audienceRequests.add(audience);
    List<TeamEvent> seen() => [
      for (final e in _since(_sorted(teamId), since))
        if (audience == null || e.audience.any(audience.contains)) e,
    ];
    yield seen();
    yield* _changes.stream.map((_) => seen());
  }

  /// The `audience` each watchEvents call asked with.
  final audienceRequests = <Set<String>?>[];

  /// The `since` each watchEvents call asked for.
  final sinceRequests = <DateTime?>[];

  static List<TeamEvent> _since(List<TeamEvent> events, DateTime? since) =>
      since == null
      ? events
      : [
          for (final e in events)
            if (!e.startsAt.isBefore(
              DateTime(since.year, since.month, since.day),
            ))
              e,
        ];

  @override
  Stream<TeamEvent?> watchEvent(String teamId, String eventId) async* {
    yield events[eventId];
    yield* _changes.stream.map((_) => events[eventId]);
  }

  List<TeamEvent> _public(String teamId) => [
    for (final e in _sorted(teamId))
      if (e.isPublic)
        TeamEvent(
          id: e.id,
          title: e.title,
          type: e.type,
          startsAt: e.startsAt,
          endsAt: e.endsAt,
          location: e.location,
          notes: e.notes,
          isPublic: true,
        ),
  ];

  @override
  Stream<List<TeamEvent>> watchPublicEvents(
    String teamId, {
    DateTime? since,
  }) async* {
    yield _since(_public(teamId), since);
    yield* _changes.stream.map((_) => _since(_public(teamId), since));
  }

  @override
  Future<Result<String>> saveEvent(
    String teamId,
    TeamEvent event,
    String uid, {
    bool clearVotes = false,
  }) async {
    lastClearVotes = clearVotes;
    final id = event.isNew ? 'e${events.length + 1}' : event.id;
    events[id] = event.copyWith(id: id);
    emit();
    return Result.ok(id);
  }

  @override
  Future<Result<void>> deleteEvent(String teamId, String eventId) async {
    (byTeam[teamId] ?? events).remove(eventId);
    emit();
    return const Result.ok(null);
  }

  TeamEvent _with(
    String eventId, {
    Map<String, RsvpStatus>? rsvps,
    Map<String, Set<Reaction>>? reactions,
    Map<String, List<String>>? votes,
  }) {
    final e = events[eventId]!;
    return TeamEvent(
      id: e.id,
      title: e.title,
      type: e.type,
      startsAt: e.startsAt,
      endsAt: e.endsAt,
      location: e.location,
      notes: e.notes,
      poll: e.poll,
      rsvps: rsvps ?? e.rsvps,
      reactions: reactions ?? e.reactions,
      votes: votes ?? e.votes,
      createdBy: e.createdBy,
    );
  }

  @override
  Future<Result<void>> setRsvp(
    String teamId,
    String eventId,
    String uid,
    RsvpStatus? status,
  ) async {
    final e = events[eventId]!;
    final rsvps = {...e.rsvps};
    status == null ? rsvps.remove(uid) : rsvps[uid] = status;
    final going = status == RsvpStatus.going;
    events[eventId] = _with(
      eventId,
      rsvps: rsvps,
      reactions: going ? null : ({...e.reactions}..remove(uid)),
      votes: going ? null : ({...e.votes}..remove(uid)),
    );
    emit();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> setReaction(
    String teamId,
    String eventId,
    String uid,
    Reaction reaction, {
    required bool on,
  }) async {
    final reactions = {...events[eventId]!.reactions};
    final mine = {...?reactions[uid]};
    on ? mine.add(reaction) : mine.remove(reaction);
    reactions[uid] = mine;
    events[eventId] = _with(eventId, reactions: reactions);
    emit();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> setVotes(
    String teamId,
    String eventId,
    String uid,
    List<String> optionIds,
  ) async {
    final votes = {...events[eventId]!.votes};
    optionIds.isEmpty ? votes.remove(uid) : votes[uid] = optionIds;
    events[eventId] = _with(eventId, votes: votes);
    emit();
    return const Result.ok(null);
  }

  /// Personal events, keyed by uid then event id.
  final mine = <String, Map<String, TeamEvent>>{};

  List<TeamEvent> _mineSorted(String uid) =>
      (mine[uid] ?? const {}).values.toList()
        ..sort((a, b) => a.startsAt.compareTo(b.startsAt));

  @override
  Stream<List<TeamEvent>> watchMyEvents(String uid, {DateTime? since}) async* {
    yield _since(_mineSorted(uid), since);
    yield* _changes.stream.map((_) => _since(_mineSorted(uid), since));
  }

  @override
  Stream<TeamEvent?> watchMyEvent(String uid, String eventId) async* {
    yield mine[uid]?[eventId];
    yield* _changes.stream.map((_) => mine[uid]?[eventId]);
  }

  @override
  Future<Result<String>> saveMyEvent(String uid, TeamEvent event) async {
    final events = mine[uid] ??= {};
    final id = event.isNew ? 'm${events.length + 1}' : event.id;
    events[id] = event.copyWith(id: id);
    emit();
    return Result.ok(id);
  }

  @override
  Future<Result<void>> deleteMyEvent(String uid, String eventId) async {
    mine[uid]?.remove(eventId);
    emit();
    return const Result.ok(null);
  }
}

class FakeThemeRepository extends ThemeRepository {
  ThemeMode _mode = ThemeMode.system;

  @override
  ThemeMode get themeMode => _mode;

  @override
  Future<Result<void>> setThemeMode(ThemeMode mode) async {
    _mode = mode;
    notifyListeners();
    return const Result.ok(null);
  }
}

class FakeChatRepository implements ChatRepository {
  final rooms = <String, ChatRoom>{};
  final folders = <String, ChatFolder>{};
  final messages = <String, List<ChatMessage>>{};
  final files = <String, Uint8List>{};
  int generalEnsured = 0;
  int voiceEnsured = 0;

  /// Whether ensureVoiceRooms adds the default voice channels.
  bool seedVoice = true;
  Exception? sendError;
  final _changes = StreamController<void>.broadcast();

  void emit() => _changes.add(null);

  /// Subscribes to changes before the first value, so changes made by a
  /// listener reacting to that value aren't lost.
  Stream<T> _watch<T>(T Function() read) {
    late StreamController<T> controller;
    StreamSubscription<void>? sub;
    controller = StreamController<T>(
      onListen: () {
        sub = _changes.stream.listen((_) => controller.add(read()));
        controller.add(read());
      },
      onCancel: () => sub?.cancel(),
    );
    return controller.stream;
  }

  /// Room ('r:id') and folder ('f:id') → the team it was saved to. Ones
  /// put straight into [rooms] and [folders] belong to every team.
  final teamOf = <String, String>{};
  var _made = 0;

  bool _on(String key, String teamId) => (teamOf[key] ?? teamId) == teamId;

  @override
  Stream<List<ChatRoom>> watchRooms(Team team, String uid) => _watch(
    () => sortRooms(
      rooms.values.where(
        (r) =>
            _on('r:${r.id}', team.id) &&
            (team.has(uid, TeamPermission.manageChats) ||
                r.accessFor(team, uid).canRead),
      ),
    ),
  );

  /// [teamId]'s rooms, whoever may read them.
  List<ChatRoom> roomsOf(String teamId) => [
    for (final r in rooms.values)
      if (_on('r:${r.id}', teamId)) r,
  ];

  @override
  Stream<List<ChatFolder>> watchFolders(String teamId) => _watch(
    () => sortFolders(folders.values.where((f) => _on('f:${f.id}', teamId))),
  );

  @override
  Future<Result<String>> saveFolder(
    String teamId,
    ChatFolder folder,
    String uid,
  ) async {
    final id = folder.isNew ? 'folder${folders.length + 1}' : folder.id;
    folders[id] = ChatFolder.fromMap(id, folder.toMap());
    teamOf['f:$id'] = teamId;
    emit();
    return Result.ok(id);
  }

  @override
  Future<Result<void>> deleteFolder(
    String teamId,
    String folderId,
    List<ChatRoom> rooms,
  ) async {
    folders.remove(folderId);
    for (final r in [...this.rooms.values]) {
      if (r.folderId == folderId) this.rooms[r.id] = r.withFolder(null);
    }
    emit();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> arrange(
    String teamId, {
    List<ChatFolder> folders = const [],
    List<ChatRoom> rooms = const [],
  }) async {
    for (final f in folders) {
      this.folders[f.id] = this.folders[f.id]!.copyWith(position: f.position);
    }
    for (final r in rooms) {
      this.rooms[r.id] = this.rooms[r.id]!
          .withFolder(r.folderId)
          .withPosition(r.position);
    }
    emit();
    return const Result.ok(null);
  }

  @override
  Stream<ChatRoom?> watchRoom(String teamId, String roomId) =>
      _watch(() => rooms[roomId]);

  @override
  Future<Result<String>> saveRoom(
    String teamId,
    ChatRoom room,
    String uid,
  ) async {
    final id = room.isNew ? 'room${rooms.length + 1}_${_made++}' : room.id;
    rooms[id] = ChatRoom.fromMap(id, {...room.toMap(), 'createdBy': uid});
    teamOf['r:$id'] = teamId;
    emit();
    return Result.ok(id);
  }

  @override
  Future<Result<void>> deleteRoom(String teamId, String roomId) async {
    rooms.remove(roomId);
    messages.remove(roomId);
    emit();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> ensureGeneralRoom(String teamId, String uid) async {
    generalEnsured++;
    rooms.putIfAbsent(ChatRoom.generalId, ChatRoom.general);
    emit();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> ensureVoiceRooms(String teamId, String uid) async {
    voiceEnsured++;
    if (!seedVoice) return const Result.ok(null);
    final defaults = ChatRoom.defaultVoiceRooms();
    if (folders.containsKey(ChatRoom.voiceFolderId) ||
        defaults.any((r) => rooms.containsKey(r.id))) {
      return const Result.ok(null);
    }
    folders[ChatRoom.voiceFolderId] = ChatRoom.defaultVoiceFolder();
    for (final r in defaults) {
      rooms[r.id] = r;
    }
    emit();
    return const Result.ok(null);
  }

  @override
  Stream<List<ChatMessage>> watchMessages(
    String teamId,
    String roomId, {
    required int limit,
  }) => _watch(() {
    final all = messages[roomId] ?? const <ChatMessage>[];
    return all.skip(all.length > limit ? all.length - limit : 0).toList();
  });

  @override
  Future<Result<List<ChatMessage>>> fetchOlderMessages(
    String teamId,
    String roomId, {
    required ChatMessage before,
    required int limit,
  }) async => Result.ok(
    olderThan(messages[roomId] ?? const <ChatMessage>[], before, limit),
  );

  @override
  Future<Result<void>> sendMessage(
    String teamId,
    String roomId, {
    required AppUser author,
    required String text,
    List<NewAttachment> attachments = const [],
  }) async {
    if (sendError case final e?) return Result.error(e);
    final list = messages.putIfAbsent(roomId, () => []);
    final id = 'm${list.length + 1}';
    list.add(
      ChatMessage(
        id: id,
        authorId: author.uid,
        authorName: author.label,
        text: text.trim(),
        createdAt: DateTime(2026, 10, 30, 12, list.length),
        attachments: [
          for (final (i, a) in attachments.indexed)
            ChatAttachment(
              path: '$roomId/$id/$i',
              name: a.name,
              contentType: a.contentType,
              size: a.size,
            ),
        ],
      ),
    );
    for (final (i, a) in attachments.indexed) {
      files['$roomId/$id/$i'] = a.bytes;
    }
    emit();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> deleteMessage(
    String teamId,
    String roomId,
    ChatMessage message,
  ) async {
    messages[roomId]?.removeWhere((m) => m.id == message.id);
    emit();
    return const Result.ok(null);
  }

  @override
  Future<Result<Uint8List>> downloadAttachment(ChatAttachment a) async {
    final f = files[a.path];
    return f == null ? Result.error(Exception('missing')) : Result.ok(f);
  }
}

class FakeFilePickerService implements FilePickerService {
  /// Returned by the next [pick].
  List<PickedFile> next = const [];
  final saved = <String>[];

  @override
  ImageCompressor compressor = const ImageCompressor();

  static PickedFile file(String name, int size) =>
      PickedFile(name: name, size: size, read: () async => Uint8List(size));

  @override
  Future<List<PickedFile>> pick({bool imagesOnly = false}) async => next;

  /// Returned by the next [pickVideo].
  PickedFile? nextVideo;

  @override
  Future<PickedFile?> pickVideo(List<String> extensions) async => nextVideo;

  @override
  Future<bool> save(String fileName, Uint8List bytes, String mimeType) async {
    saved.add(fileName);
    return true;
  }
}

class FakeDirectMessageRepository implements DirectMessageRepository {
  final profiles = <UserProfile>[];
  final conversations = <String, Conversation>{};
  final messages = <String, List<ChatMessage>>{};
  final reads = <String>[];
  final _changes = StreamController<void>.broadcast();

  void emit() => _changes.add(null);

  Stream<T> _watch<T>(T Function() read) {
    late StreamController<T> controller;
    StreamSubscription<void>? sub;
    controller = StreamController<T>(
      onListen: () {
        sub = _changes.stream.listen((_) => controller.add(read()));
        controller.add(read());
      },
      onCancel: () => sub?.cancel(),
    );
    return controller.stream;
  }

  @override
  Future<Result<List<UserProfile>>> searchPeople(
    String query, {
    required String excludeUid,
  }) async => Result.ok([
    for (final p in profiles)
      if (p.uid != excludeUid && p.matches(query)) p,
  ]);

  @override
  Stream<List<Conversation>> watchConversations(String uid) => _watch(
    () => conversations.values
        .where((c) => c.participants.contains(uid) && c.hasMessages)
        .map((c) => c.withMyReadAt(privateReads[c.id]))
        .toList(),
  );

  @override
  Stream<Conversation?> watchConversation(String id, {required String uid}) =>
      _watch(() => conversations[id]?.withMyReadAt(privateReads[id]));

  /// Read receipts setting by uid; on unless set.
  final readReceipts = <String, bool>{};

  /// Private read times by conversation id.
  final privateReads = <String, DateTime>{};

  @override
  Stream<bool> watchReadReceipts(String uid) =>
      _watch(() => readReceipts[uid] ?? true);

  @override
  Future<Result<void>> setReadReceipts(String uid, {required bool on}) async {
    readReceipts[uid] = on;
    emit();
    return const Result.ok(null);
  }

  @override
  Future<Result<String>> openConversation(AppUser me, UserProfile other) async {
    final id = Conversation.idFor(me.uid, other.uid);
    conversations.putIfAbsent(
      id,
      () => Conversation(
        id: id,
        participants: id.split('_'),
        names: {me.uid: me.label, other.uid: other.name},
      ),
    );
    emit();
    return Result.ok(id);
  }

  @override
  Stream<List<ChatMessage>> watchMessages(String id, {required int limit}) =>
      _watch(() => List.of(messages[id] ?? const <ChatMessage>[]));

  @override
  Future<Result<List<ChatMessage>>> fetchOlderMessages(
    String id, {
    required ChatMessage before,
    required int limit,
  }) async => Result.ok(
    olderThan(messages[id] ?? const <ChatMessage>[], before, limit),
  );

  @override
  Future<Result<void>> sendMessage(
    String id, {
    required AppUser author,
    required String text,
    List<NewAttachment> attachments = const [],
  }) async {
    final list = messages.putIfAbsent(id, () => []);
    final at = DateTime(2026, 10, 30, 12, list.length);
    list.add(
      ChatMessage(
        id: 'm${list.length + 1}',
        authorId: author.uid,
        authorName: author.label,
        text: text.trim(),
        createdAt: at,
      ),
    );
    final c = conversations[id]!;
    conversations[id] = Conversation(
      id: id,
      participants: c.participants,
      names: c.names,
      lastMessage: messagePreview(text, attachments.length),
      lastMessageAt: at,
      lastSenderId: author.uid,
      readAt: {...c.readAt, author.uid: at},
    );
    emit();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> deleteMessage(String id, ChatMessage message) async {
    messages[id]?.removeWhere((m) => m.id == message.id);
    emit();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> markRead(
    String id,
    String uid, {
    required bool shareReceipt,
  }) async {
    reads.add(id);
    privateReads[id] = DateTime(2100);
    if (!shareReceipt) {
      emit();
      return const Result.ok(null);
    }
    final c = conversations[id]!;
    conversations[id] = Conversation(
      id: id,
      participants: c.participants,
      names: c.names,
      lastMessage: c.lastMessage,
      lastMessageAt: c.lastMessageAt,
      lastSenderId: c.lastSenderId,
      readAt: {...c.readAt, uid: DateTime(2100)},
    );
    emit();
    return const Result.ok(null);
  }

  @override
  Future<Result<Uint8List>> downloadAttachment(ChatAttachment a) async =>
      Result.error(Exception('missing'));
}

class FakeNotificationRepository implements NotificationRepository {
  FakeNotificationRepository({
    this.prefs = const NotificationPreferences(),
    List<AppNotification> feed = const [],
    this.status = PushStatus.notDetermined,
    this.pushSupported = true,
    this.offerPush = false,
  }) : feed = [...feed];

  /// What [shouldOfferPush] answers; off so most tests see no offer.
  bool offerPush;
  var pushOfferDismissed = false;

  @override
  Future<bool> shouldOfferPush() async => offerPush && !pushOfferDismissed;

  @override
  Future<void> dismissPushOffer() async => pushOfferDismissed = true;

  NotificationPreferences prefs;
  final List<AppNotification> feed;
  PushStatus status;
  @override
  final bool pushSupported;
  final synced = <String>[];
  final unregistered = <String>[];
  final opened = StreamController<String>.broadcast();
  final _changes = StreamController<void>.broadcast();

  void emit() => _changes.add(null);

  Stream<T> _watch<T>(T Function() read) {
    late StreamController<T> controller;
    StreamSubscription<void>? sub;
    controller = StreamController<T>(
      onListen: () {
        sub = _changes.stream.listen((_) => controller.add(read()));
        controller.add(read());
      },
      onCancel: () => sub?.cancel(),
    );
    return controller.stream;
  }

  Future<Result<void>> _update(NotificationPreferences next) async {
    prefs = next;
    emit();
    return const Result.ok(null);
  }

  @override
  Stream<NotificationPreferences> watchPreferences(String uid) =>
      _watch(() => prefs);

  @override
  Future<Result<void>> setCategory(
    String uid,
    NotificationCategory category, {
    required bool on,
  }) => _update(
    NotificationPreferences(
      categories: {...prefs.categories, category: on},
      teams: prefs.teams,
      mutedRooms: prefs.mutedRooms,
    ),
  );

  @override
  Future<Result<void>> setTeamCategory(
    String uid,
    String teamId,
    NotificationCategory category, {
    required bool on,
  }) => _update(
    NotificationPreferences(
      categories: prefs.categories,
      teams: {
        ...prefs.teams,
        teamId: {...?prefs.teams[teamId], category: on},
      },
      mutedRooms: prefs.mutedRooms,
    ),
  );

  @override
  Future<Result<void>> resetTeam(String uid, String teamId) => _update(
    NotificationPreferences(
      categories: prefs.categories,
      teams: {...prefs.teams}..remove(teamId),
      mutedRooms: prefs.mutedRooms,
    ),
  );

  @override
  Future<Result<void>> setRoomMuted(
    String uid,
    String teamId,
    String roomId, {
    required bool muted,
  }) {
    final key = NotificationPreferences.roomKey(teamId, roomId);
    return _update(
      NotificationPreferences(
        categories: prefs.categories,
        teams: prefs.teams,
        mutedRooms: muted
            ? {...prefs.mutedRooms, key}
            : ({...prefs.mutedRooms}..remove(key)),
      ),
    );
  }

  @override
  Stream<List<AppNotification>> watchFeed(String uid) =>
      _watch(() => List.of(feed));

  @override
  Future<Result<void>> markRead(String uid, Iterable<String> ids) async {
    final set = ids.toSet();
    for (var i = 0; i < feed.length; i++) {
      final n = feed[i];
      if (!set.contains(n.id)) continue;
      feed[i] = AppNotification(
        id: n.id,
        category: n.category,
        title: n.title,
        body: n.body,
        route: n.route,
        teamId: n.teamId,
        createdAt: n.createdAt,
        read: true,
        count: n.count,
        followBack: n.followBack,
      );
    }
    emit();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> delete(String uid, Iterable<String> ids) async {
    final set = ids.toSet();
    feed.removeWhere((n) => set.contains(n.id));
    emit();
    return const Result.ok(null);
  }

  @override
  Future<PushStatus> pushStatus() async => status;

  @override
  Future<Result<PushStatus>> enablePush(String uid) async {
    if (status == PushStatus.notDetermined) status = PushStatus.enabled;
    return Result.ok(status);
  }

  /// What [registerDevice] fails with, if anything.
  Exception? registerError;
  final registered = <String>[];

  @override
  Future<Result<void>> registerDevice(String uid) async {
    if (registerError case final e?) return Result.error(e);
    registered.add(uid);
    return const Result.ok(null);
  }

  @override
  Future<void> syncDevice(String uid) async => synced.add(uid);

  @override
  Future<void> unregisterDevice(String uid) async => unregistered.add(uid);

  @override
  Stream<String> get openedRoutes => opened.stream;
}

class FakeTeamPostRepository implements TeamPostRepository {
  /// teamId → posts.
  final posts = <String, List<TeamPost>>{};
  final _changes = StreamController<void>.broadcast();

  /// Whether each watch asked for public posts only, in order.
  final watches = <bool>[];

  List<TeamPost> _of(String teamId, bool publicOnly) => [
    for (final p in posts[teamId] ?? const <TeamPost>[])
      if (!publicOnly || p.isPublic) p,
  ]..sort(TeamPost.newestFirst);

  @override
  Stream<List<TeamPost>> watchPosts(
    String teamId, {
    bool publicOnly = false,
    int? limit,
  }) async* {
    watches.add(publicOnly);
    List<TeamPost> page() {
      final all = _of(teamId, publicOnly);
      return limit == null ? all : all.take(limit).toList();
    }

    yield page();
    yield* _changes.stream.map((_) => page());
  }

  @override
  Future<Result<List<TeamPost>>> fetchPostsBefore(
    String teamId, {
    bool publicOnly = false,
    required DateTime before,
    int limit = 20,
  }) async => Result.ok(
    _of(teamId, publicOnly)
        .where((p) => p.createdAt != null && p.createdAt!.isBefore(before))
        .take(limit)
        .toList(),
  );

  @override
  Stream<List<TeamPost>> watchTournamentPosts(
    String groupId,
    String tournamentKey,
  ) async* {
    List<TeamPost> of() => [
      for (final p in _of(groupId, true))
        if (p.tournamentKey == tournamentKey) p,
    ];
    yield of();
    yield* _changes.stream.map((_) => of());
  }

  /// Photos uploaded by [savePost], by name.
  final uploaded = <String>[];

  @override
  Future<Result<void>> savePost(
    String teamId,
    PostDraft draft,
    AppUser author,
  ) async {
    final post = draft.post;
    final list = posts.putIfAbsent(teamId, () => []);
    final images = [
      ...post.images,
      for (final a in draft.newImages)
        ChatAttachment(
          path: 'teams/$teamId/posts/${a.name}',
          name: a.name,
          contentType: a.contentType,
          size: a.size,
        ),
    ];
    uploaded.addAll(draft.newImages.map((a) => a.name));
    if (post.isNew) {
      list.add(
        TeamPost(
          id: 'p${list.length + 1}',
          title: post.title,
          body: post.body,
          location: post.location,
          links: post.links,
          images: images,
          isPublic: post.isPublic,
          tournamentKey: post.tournamentKey,
          authorId: author.uid,
          authorName: author.label,
          createdAt: DateTime.now(),
        ),
      );
    } else {
      final i = list.indexWhere((p) => p.id == post.id);
      if (i < 0) return Result.error(Exception('No post'));
      list[i] = post.copyWith(images: images);
    }
    _changes.add(null);
    return const Result.ok(null);
  }

  @override
  Future<Result<Uint8List>> downloadImage(ChatAttachment image) async =>
      Result.ok(Uint8List.fromList(_png));

  @override
  Future<Result<void>> deletePost(String teamId, String postId) async {
    posts[teamId]?.removeWhere((p) => p.id == postId);
    _changes.add(null);
    return const Result.ok(null);
  }
}

/// A 1×1 PNG, for image widgets in tests.
const _png = <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
];

/// Profiles kept in memory. Records what was published.
class FakeProfileRepository implements ProfileRepository {
  final profiles = <String, PlayerProfile>{};
  final published = <ProfileSummary>[];
  final _changes = StreamController<String>.broadcast();

  @override
  Stream<PlayerProfile?> watchProfile(String uid) async* {
    yield _asSeen(uid);
    yield* _changes.stream.where((id) => id == uid).map((_) => _asSeen(uid));
  }

  void put(PlayerProfile p) {
    profiles[p.uid] = p;
    _changes.add(p.uid);
  }

  /// Who's looking, and whose private profiles they may see (accepted
  /// follows); others come back locked, like the rules make them.
  String? viewer;
  final allowed = <String>{};

  PlayerProfile? _asSeen(String uid) {
    final p = profiles[uid];
    if (p == null || !p.isPrivate || uid == viewer || allowed.contains(uid)) {
      return p;
    }
    return PlayerProfile(
      uid: p.uid,
      name: p.name,
      photoUrl: p.photoUrl,
      username: p.username,
      isPrivate: true,
      locked: true,
    );
  }

  /// Lets [viewer] see [uid]'s private profile, as accepting them does.
  void allow(String uid) {
    allowed.add(uid);
    _changes.add(uid);
  }

  @override
  Future<Result<void>> saveVisibility(AppUser user, ProfileVisibility v) async {
    final p =
        profiles[user.uid] ?? PlayerProfile(uid: user.uid, name: user.label);
    final d = p.details;
    final s = p.summary;
    put(
      PlayerProfile(
        uid: p.uid,
        name: p.name,
        photoUrl: p.photoUrl,
        username: p.username,
        isPrivate: p.isPrivate,
        details: ProfileDetails(
          bio: d.bio,
          pronouns: d.pronouns,
          hometown: d.hometown,
          school: d.school,
          throwingHand: d.throwingHand,
          playingSince: d.playingSince,
          visibility: v,
        ),
        summary: ProfileSummary(
          teams: v.teams ? s.teams : const [],
          seasons: v.stats ? s.seasons : const {},
          games: v.games ? s.games : const [],
          updatedAt: s.updatedAt,
        ),
      ),
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> setPrivate(AppUser user, bool private) async {
    final p =
        profiles[user.uid] ?? PlayerProfile(uid: user.uid, name: user.label);
    put(
      PlayerProfile(
        uid: p.uid,
        name: p.name,
        photoUrl: p.photoUrl,
        username: p.username,
        details: p.details,
        summary: p.summary,
        isPrivate: private,
      ),
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> saveDetails(
    AppUser user,
    ProfileDetails details, {
    required List<String> tags,
  }) async {
    final old = profiles[user.uid];
    put(
      PlayerProfile(
        uid: user.uid,
        name: user.label,
        details: details,
        summary: old?.summary ?? const ProfileSummary(),
        isPrivate: old?.isPrivate ?? false,
      ),
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> publishSummary(
    AppUser user,
    ProfileSummary summary, {
    required List<String> tags,
  }) async {
    published.add(summary);
    final old = profiles[user.uid];
    put(
      PlayerProfile(
        uid: user.uid,
        name: user.label,
        details: old?.details ?? const ProfileDetails(),
        summary: summary,
        isPrivate: old?.isPrivate ?? false,
      ),
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<List<PlayerProfile>>> searchPlayers(String query) async =>
      Result.ok([
        for (final p in profiles.values)
          if (p.matches(query)) p,
      ]);
}

/// Tracked games kept in memory, by team.
class FakeStatsRepository implements StatsRepository {
  final games = <String, List<StatsGame>>{};

  @override
  Stream<List<StatsGame>> watchGames(String teamId) async* {
    yield games[teamId] ?? const [];
  }

  @override
  Stream<List<RosterPlayer>> watchPlayers(String teamId) async* {
    yield const [];
  }

  @override
  Stream<List<StatsTournament>> watchTournaments(String teamId) async* {
    yield const [];
  }

  @override
  Future<Result<String>> saveTournament(String teamId, StatsTournament t) =>
      throw UnimplementedError();

  @override
  Future<Result<String>> saveGame(String teamId, StatsGame game) =>
      throw UnimplementedError();

  @override
  Future<Result<void>> deleteGame(String teamId, String gameId) =>
      throw UnimplementedError();

  @override
  Future<Result<void>> deleteTournament(String teamId, String tournamentId) =>
      throw UnimplementedError();
}

/// Messages before [before] in [all] (oldest first), at most [limit].
List<ChatMessage> olderThan(
  List<ChatMessage> all,
  ChatMessage before,
  int limit,
) {
  final i = all.indexWhere((m) => m.id == before.id);
  final older = i < 0 ? const <ChatMessage>[] : all.sublist(0, i);
  return older.skip(older.length > limit ? older.length - limit : 0).toList();
}
