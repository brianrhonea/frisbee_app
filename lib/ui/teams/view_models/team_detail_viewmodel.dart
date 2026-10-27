import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/playbook/play_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../domain/models/play.dart';
import '../../../domain/models/roster_player.dart';
import '../../../domain/models/team.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

typedef RoleChange = ({String uid, TeamRole role});

/// Backs the team detail screen and its Roster / Members / Playbook tabs.
class TeamDetailViewModel extends ChangeNotifier {
  TeamDetailViewModel({
    required this.teamId,
    required TeamRepository teamRepository,
    required PlayRepository playRepository,
    required AuthRepository authRepository,
  }) : _teams = teamRepository,
       _plays = playRepository,
       _auth = authRepository {
    updateTeam = Command1<void, Team>(_teams.updateTeam);
    savePlayer = Command1<void, RosterPlayer>(
      (p) => _teams.savePlayer(teamId, p),
    );
    deletePlayer = Command1<void, String>(
      (id) => _teams.deletePlayer(teamId, id),
    );
    regenerateInviteCode = Command0<void>(_regenerateInviteCode);
    setMemberRole = Command1<void, RoleChange>(
      (c) => _teams.setMemberRole(teamId, c.uid, c.role),
    );
    removeMember = Command1<void, String>(
      (uid) => _teams.removeMember(teamId, uid),
    );
    leaveTeam = Command0<void>(() => _teams.removeMember(teamId, uid));
    deleteTeam = Command0<void>(_deleteTeam);
    deletePlay = Command1<void, String>((id) => _plays.deletePlay(teamId, id));

    _subs = [
      _teams.watchTeam(teamId).listen((t) {
        _team = t;
        _teamLoaded = true;
        notifyListeners();
      }, onError: _onError),
      _teams.watchRoster(teamId).listen((r) {
        _roster = r;
        notifyListeners();
      }, onError: _onError),
      _plays.watchPlays(teamId).listen((p) {
        _playList = p;
        notifyListeners();
      }, onError: _onError),
    ];
  }

  final String teamId;
  final TeamRepository _teams;
  final PlayRepository _plays;
  final AuthRepository _auth;
  late final List<StreamSubscription<Object?>> _subs;

  Team? _team;
  Team? get team => _team;

  bool _teamLoaded = false;

  /// True once the first team snapshot arrived (or failed).
  bool get loaded => _teamLoaded || _error != null;

  List<RosterPlayer> _roster = const [];
  List<RosterPlayer> get roster => _roster;

  List<Play> _playList = const [];
  List<Play> get plays => _playList;

  Object? _error;
  Object? get error => _error;

  String get uid => _auth.currentUser?.uid ?? '';
  TeamRole? get myRole => _team?.roleOf(uid);
  bool get canEdit => myRole?.canEdit ?? false;
  bool get isOwner => myRole == TeamRole.owner;

  /// Owners can manage anyone but themselves; coaches can remove players.
  bool canManage(String memberUid) {
    if (memberUid == uid) return false;
    final target = _team?.roleOf(memberUid);
    if (isOwner) return true;
    return myRole == TeamRole.coach && target == TeamRole.player;
  }

  late final Command1<void, Team> updateTeam;
  late final Command1<void, RosterPlayer> savePlayer;
  late final Command1<void, String> deletePlayer;
  late final Command0<void> regenerateInviteCode;
  late final Command1<void, RoleChange> setMemberRole;
  late final Command1<void, String> removeMember;
  late final Command0<void> leaveTeam;
  late final Command0<void> deleteTeam;
  late final Command1<void, String> deletePlay;

  void _onError(Object e) {
    _error = e;
    notifyListeners();
  }

  Future<Result<void>> _regenerateInviteCode() async {
    final t = _team;
    if (t == null) return Result.error(Exception('Team not loaded'));
    return _teams.regenerateInviteCode(t);
  }

  Future<Result<void>> _deleteTeam() async {
    final t = _team;
    if (t == null) return Result.error(Exception('Team not loaded'));
    return _teams.deleteTeam(t);
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}
