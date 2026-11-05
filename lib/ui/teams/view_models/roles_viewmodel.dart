import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../domain/models/team.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

typedef RoleShift = ({String id, int by});

/// Colors the role editor offers, ARGB; 0 is no color.
const roleColors = [
  0,
  0xFFE53935,
  0xFFFB8C00,
  0xFFFDD835,
  0xFF43A047,
  0xFF00ACC1,
  0xFF1E88E5,
  0xFF8E24AA,
  0xFFD81B60,
  0xFF6D4C41,
  0xFF546E7A,
];

/// The owner's list of custom roles: create, edit, reorder and delete
/// them, like Discord's server roles. Assigning them to members is on the
/// Members tab ([TeamDetailViewModel.setMemberRoles]).
class RolesViewModel extends ChangeNotifier {
  RolesViewModel({
    required this.teamId,
    required TeamRepository teamRepository,
    required AuthRepository authRepository,
  }) : _teams = teamRepository,
       _auth = authRepository {
    save = Command1<void, CustomRole>(_save);
    delete = Command1<void, String>(_delete);
    shift = Command1<void, RoleShift>(_shift);
    _sub = _teams.watchTeam(teamId).listen((t) {
      _team = t;
      _loaded = true;
      notifyListeners();
    }, onError: _onError);
  }

  final String teamId;
  final TeamRepository _teams;
  final AuthRepository _auth;
  late final StreamSubscription<Team?> _sub;

  /// Creates the role when [CustomRole.isNew], otherwise updates it.
  late final Command1<void, CustomRole> save;

  /// Deletes a role and takes it from everyone who had it.
  late final Command1<void, String> delete;

  /// Moves a role up (-1) or down (+1) the list.
  late final Command1<void, RoleShift> shift;

  Team? _team;
  bool _loaded = false;
  Object? _error;

  String get uid => _auth.currentUser?.uid ?? '';
  Team? get team => _team;
  bool get loaded => _loaded;
  Object? get error => _error;

  bool get isOwner => _team?.roleOf(uid) == TeamRole.owner;
  bool get isGroup => _team?.isCommunity ?? false;

  /// Custom roles, top first.
  List<CustomRole> get roles => _team?.sortedRoles ?? const [];

  bool get canAdd => isOwner && roles.length < CustomRole.maxRoles;

  /// Permissions a role here can grant; groups don't keep stats.
  List<TeamPermission> get permissions => TeamPermission.forGroup(isGroup);

  /// How many members have role [id].
  int memberCount(String id) =>
      _team?.memberRoles.values.where((ids) => ids.contains(id)).length ?? 0;

  /// "Manage chats, Moderate", or "No permissions".
  String summaryOf(CustomRole role) => role.permissions.isEmpty
      ? 'No permissions'
      : [
          for (final p in TeamPermission.values)
            if (role.permissions.contains(p)) p.label,
        ].join(', ');

  Future<Result<void>> _write(
    Team team,
    Map<String, CustomRole> roles,
    Map<String, Set<String>> memberRoles,
  ) => _teams.saveRoles(team, roles: roles, memberRoles: memberRoles);

  Future<Result<void>> _save(CustomRole role) async {
    final team = _team;
    if (team == null) return Result.error(Exception('Team not loaded'));
    final name = role.name.trim();
    if (name.isEmpty) return Result.error(Exception('Give the role a name.'));
    if (role.isNew && roles.length >= CustomRole.maxRoles) {
      return Result.error(
        Exception('A team can have up to ${CustomRole.maxRoles} roles.'),
      );
    }
    final saved = role.isNew
        ? role.copyWith(
            id: newRoleId(),
            name: name,
            position: roles.isEmpty ? 0 : roles.last.position + 1,
          )
        : role.copyWith(name: name);
    return _write(team, {...team.roles, saved.id: saved}, team.memberRoles);
  }

  Future<Result<void>> _delete(String id) async {
    final team = _team;
    if (team == null) return Result.error(Exception('Team not loaded'));
    return _write(team, {...team.roles}..remove(id), {
      for (final e in team.memberRoles.entries) e.key: {...e.value}..remove(id),
    });
  }

  Future<Result<void>> _shift(RoleShift s) async {
    final team = _team;
    if (team == null) return Result.error(Exception('Team not loaded'));
    final list = [...roles];
    final from = list.indexWhere((r) => r.id == s.id);
    final to = from + s.by;
    if (from < 0 || to < 0 || to >= list.length) return const Result.ok(null);
    list.insert(to, list.removeAt(from));
    return _write(team, {
      for (final (i, r) in list.indexed) r.id: r.copyWith(position: i),
    }, team.memberRoles);
  }

  void _onError(Object e) {
    _error = e;
    _loaded = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
