import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../domain/models/app_user.dart';
import '../../../domain/models/roster_player.dart';
import '../../../domain/models/team.dart';
import '../../../utils/result.dart';
import '../auth/auth_repository.dart';
import 'team_repository.dart';

/// Debug-only "view as" role: when set, the signed-in user appears to have
/// [role] on every team they belong to, to preview the app for each role.
/// Display only; firestore.rules still enforces the real role on writes.
class ViewAsRole extends ChangeNotifier {
  TeamRole? _role;
  TeamRole? get role => _role;

  set role(TeamRole? role) {
    if (role == _role) return;
    _role = role;
    notifyListeners();
  }
}

/// [TeamRepository] that rewrites the current user's role per [ViewAsRole].
/// Teams re-emit when the role changes, so open screens update in place.
class ViewAsTeamRepository implements TeamRepository {
  ViewAsTeamRepository({
    required TeamRepository inner,
    required AuthRepository authRepository,
    required ViewAsRole viewAs,
  }) : _inner = inner,
       _auth = authRepository,
       _viewAs = viewAs;

  final TeamRepository _inner;
  final AuthRepository _auth;
  final ViewAsRole _viewAs;

  Team _apply(Team team) {
    final role = _viewAs.role;
    final uid = _auth.currentUser?.uid;
    if (role == null || uid == null || !team.members.containsKey(uid)) {
      return team;
    }
    return team.copyWith(
      members: {...team.members, uid: role},
      statKeepers: role == TeamRole.player
          ? team.statKeepers.difference({uid})
          : null,
    );
  }

  /// [source] mapped through [apply], re-emitting its last value whenever
  /// the view-as role changes.
  Stream<T> _viewing<T>(Stream<T> source, T Function(T) apply) {
    late final StreamController<T> controller;
    StreamSubscription<T>? sub;
    late T last;
    var hasValue = false;
    void push() {
      if (hasValue) controller.add(apply(last));
    }

    controller = StreamController<T>(
      onListen: () {
        _viewAs.addListener(push);
        sub = source.listen(
          (v) {
            last = v;
            hasValue = true;
            push();
          },
          onError: controller.addError,
          onDone: controller.close,
        );
      },
      onCancel: () {
        _viewAs.removeListener(push);
        return sub?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Stream<List<Team>> watchMyTeams(String uid) => _viewing(
    _inner.watchMyTeams(uid),
    (teams) => [for (final t in teams) _apply(t)],
  );

  @override
  Stream<Team?> watchTeam(String teamId) => _viewing(
    _inner.watchTeam(teamId),
    (team) => team == null ? null : _apply(team),
  );

  @override
  Future<Result<String>> createTeam(NewTeam team, AppUser owner) =>
      _inner.createTeam(team, owner);

  @override
  Future<Result<String>> joinTeam(String inviteCode, AppUser user) =>
      _inner.joinTeam(inviteCode, user);

  @override
  Future<Result<void>> updateTeam(Team team) => _inner.updateTeam(team);

  @override
  Future<Result<void>> regenerateInviteCode(Team team) =>
      _inner.regenerateInviteCode(team);

  @override
  Future<Result<void>> setMemberRole(
    String teamId,
    String uid,
    TeamRole role,
  ) => _inner.setMemberRole(teamId, uid, role);

  @override
  Future<Result<void>> setStatKeeper(
    String teamId,
    String uid, {
    required bool on,
  }) => _inner.setStatKeeper(teamId, uid, on: on);

  @override
  Future<Result<void>> transferOwnership(
    String teamId, {
    required String ownerUid,
    required String newOwnerUid,
  }) => _inner.transferOwnership(
    teamId,
    ownerUid: ownerUid,
    newOwnerUid: newOwnerUid,
  );

  @override
  Future<Result<void>> removeMember(String teamId, String uid) =>
      _inner.removeMember(teamId, uid);

  @override
  Future<Result<void>> deleteTeam(Team team) => _inner.deleteTeam(team);

  @override
  Future<Result<void>> linkUsauTeam(
    String teamId, {
    String? url,
    String? name,
  }) => _inner.linkUsauTeam(teamId, url: url, name: name);

  @override
  Future<Result<void>> applyRosterSync(
    String teamId,
    List<RosterPlayer> players,
  ) => _inner.applyRosterSync(teamId, players);

  @override
  Stream<List<RosterPlayer>> watchRoster(String teamId) =>
      _inner.watchRoster(teamId);

  @override
  Future<Result<void>> savePlayer(String teamId, RosterPlayer player) =>
      _inner.savePlayer(teamId, player);

  @override
  Future<Result<void>> deletePlayer(String teamId, String playerId) =>
      _inner.deletePlayer(teamId, playerId);
}
