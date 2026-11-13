import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../domain/models/team.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// Which community roles get on a team: ones it already has, plus
/// optionally a new role (made first, owner only) named [newRole].
typedef TeamAccess = ({Set<String> roles, String? newRole});

typedef NewCommunityTeam = ({NewTeam team, TeamAccess access});

typedef LinkAnswer = ({TeamLinkRequest request, TeamAccess access});

/// A school or club community's Teams section: the teams it links, which
/// of them the user's roles put them on, and, for its admins (Manage
/// team), new teams, requests from teams that want in, and which roles
/// get on each team. The communities Cloud Functions do the joining.
class CommunityTeamsViewModel extends ChangeNotifier {
  CommunityTeamsViewModel({
    required this.orgId,
    required TeamRepository teamRepository,
    required AuthRepository authRepository,
  }) : _teams = teamRepository,
       _auth = authRepository {
    createTeam = Command1<String, NewCommunityTeam>(_createTeam);
    accept = Command1<void, LinkAnswer>(_accept);
    decline = Command1<void, String>(
      (teamId) => _teams.declineLinkRequest(orgId, teamId),
    );
    saveAccess = Command1<void, (LinkedTeam, TeamAccess)>(_saveAccess);
    unlink = Command1<void, String>(
      (teamId) => _teams.unlinkTeam(orgId, teamId),
    );
    _orgSub = _teams
        .watchTeam(orgId)
        .listen(
          (t) {
            _org = t;
            _loaded = true;
            _watchRequests();
            notifyListeners();
          },
          onError: (Object e) {
            _error = e;
            _loaded = true;
            notifyListeners();
          },
        );
    _mineSub = _teams.watchMyTeams(uid).listen((teams) {
      _myTeams = {for (final t in teams) t.id};
      notifyListeners();
    }, onError: (Object _) {});
  }

  final String orgId;
  final TeamRepository _teams;
  final AuthRepository _auth;
  late final StreamSubscription<Team?> _orgSub;
  StreamSubscription<List<TeamLinkRequest>>? _requestSub;
  late final StreamSubscription<List<Team>> _mineSub;

  /// Teams the user is actually on.
  Set<String> _myTeams = const {};

  late final Command1<String, NewCommunityTeam> createTeam;
  late final Command1<void, LinkAnswer> accept;
  late final Command1<void, String> decline;
  late final Command1<void, (LinkedTeam, TeamAccess)> saveAccess;
  late final Command1<void, String> unlink;

  Team? _org;
  bool _loaded = false;
  Object? _error;
  List<TeamLinkRequest> _requests = const [];

  Team? get org => _org;
  bool get loaded => _loaded;
  Object? get error => _error;
  String get uid => _auth.currentUser?.uid ?? '';

  /// Lists teams, answers requests and says which roles get on each.
  bool get canManage => _org?.has(uid, TeamPermission.manageTeam) ?? false;

  /// Invites people straight to any of its teams (Manage members).
  bool get canInvite => _org?.has(uid, TeamPermission.manageMembers) ?? false;

  /// [team] as a team to invite to: its admins' rules and the API check
  /// the community's link, so only what the invite needs is filled in.
  Team inviteTarget(LinkedTeam team) => Team(
    id: team.id,
    name: team.name,
    division: team.division,
    level: _org?.level ?? CompetitionLevel.college,
    ownerId: '',
    members: const {},
    orgId: orgId,
    orgName: _org?.name ?? '',
    orgLinked: true,
  );

  /// Only the owner makes roles, so only they may add one from here.
  bool get canMakeRoles => _org?.roleOf(uid) == TeamRole.owner;

  List<LinkedTeam> get teams => _org?.sortedLinkedTeams ?? const [];
  List<CustomRole> get roles => _org?.sortedRoles ?? const [];
  List<TeamLinkRequest> get requests => _requests;
  bool get full => teams.length >= LinkedTeam.max;

  /// Whether the user is on [team].
  bool isOn(LinkedTeam team) => _myTeams.contains(team.id);

  /// The user's roles give them [team], but the server hasn't added them
  /// yet (the communities Cloud Function does, within seconds).
  bool isJoining(LinkedTeam team) =>
      !isOn(team) && (_org?.teamsFor(uid).contains(team.id) ?? false);

  /// The names of the roles that get on [team], top role first.
  List<String> roleNames(LinkedTeam team) => [
    for (final r in roles)
      if (team.roles.contains(r.id)) r.name,
  ];

  void _watchRequests() {
    if (!canManage) {
      _requestSub?.cancel();
      _requestSub = null;
      _requests = const [];
      return;
    }
    _requestSub ??= _teams.watchLinkRequests(orgId).listen((r) {
      _requests = r;
      notifyListeners();
    }, onError: (Object _) => _requests = const []);
  }

  /// [access] as role ids, making its new role first if it asks for one.
  Future<Result<Set<String>>> _roleIds(TeamAccess access) async {
    final org = _org;
    final name = access.newRole?.trim() ?? '';
    if (org == null) return Result.error(Exception('Community not loaded'));
    if (name.isEmpty) return Result.ok(access.roles);
    final existing = org.roles.values
        .where((r) => r.name.toLowerCase() == name.toLowerCase())
        .firstOrNull;
    if (existing != null) return Result.ok({...access.roles, existing.id});
    if (org.roles.length >= CustomRole.maxRoles) {
      return Result.error(
        Exception('A community can have ${CustomRole.maxRoles} roles.'),
      );
    }
    final role = CustomRole(
      id: newRoleId(),
      name: name.length > CustomRole.maxNameLength
          ? name.substring(0, CustomRole.maxNameLength)
          : name,
      position: org.roles.length,
    );
    final saved = await _teams.saveRoles(
      org,
      roles: {...org.roles, role.id: role},
      memberRoles: org.memberRoles,
    );
    return switch (saved) {
      Ok() => Result.ok({...access.roles, role.id}),
      Error(:final error) => Result.error(error),
    };
  }

  Future<Result<String>> _createTeam(NewCommunityTeam t) async {
    final user = _auth.currentUser;
    final org = _org;
    if (user == null || org == null) {
      return Result.error(Exception('Not signed in'));
    }
    if (full) {
      return Result.error(
        Exception('A community can link ${LinkedTeam.max} teams.'),
      );
    }
    final ids = await _roleIds(t.access);
    return switch (ids) {
      Ok(:final value) => _teams.createTeamInCommunity(
        t.team,
        user,
        _org ?? org,
        value,
      ),
      Error(:final error) => Result.error(error),
    };
  }

  Future<Result<void>> _accept(LinkAnswer a) async {
    final org = _org;
    if (org == null) return Result.error(Exception('Community not loaded'));
    if (full) {
      return Result.error(
        Exception('A community can link ${LinkedTeam.max} teams.'),
      );
    }
    final ids = await _roleIds(a.access);
    return switch (ids) {
      Ok(:final value) => _teams.acceptLinkRequest(
        _org ?? org,
        a.request,
        value,
      ),
      Error(:final error) => Result.error(error),
    };
  }

  Future<Result<void>> _saveAccess((LinkedTeam, TeamAccess) t) async {
    final ids = await _roleIds(t.$2);
    return switch (ids) {
      Ok(:final value) => _teams.saveLinkedTeam(
        orgId,
        t.$1.copyWith(roles: value),
      ),
      Error(:final error) => Result.error(error),
    };
  }

  @override
  void dispose() {
    _orgSub.cancel();
    _mineSub.cancel();
    _requestSub?.cancel();
    super.dispose();
  }
}
