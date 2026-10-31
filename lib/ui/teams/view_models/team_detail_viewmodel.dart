import 'dart:async';

import 'package:flutter/material.dart' show DateUtils;
import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/event/event_repository.dart';
import '../../../data/repositories/meeting/meeting_repository.dart';
import '../../../data/repositories/playbook/play_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../domain/models/meeting.dart';
import '../../../domain/models/play.dart';
import '../../../domain/models/roster_player.dart';
import '../../../domain/models/team.dart';
import '../../../domain/models/team_event.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

typedef RoleChange = ({String uid, TeamRole role});
typedef StatsAccess = ({String uid, bool on});

/// Backs the team sections: Team Events, Roster, Playbook and Members.
/// The team home page has its own `TeamHomeViewModel`.
class TeamDetailViewModel extends ChangeNotifier {
  TeamDetailViewModel({
    required this.teamId,
    required TeamRepository teamRepository,
    required PlayRepository playRepository,
    required EventRepository eventRepository,
    required AuthRepository authRepository,
    MeetingRepository? meetingRepository,
    DateTime Function()? clock,
  }) : _teams = teamRepository,
       _plays = playRepository,
       _meetings = meetingRepository,
       _auth = authRepository,
       _clock = clock ?? DateTime.now {
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
    setStatKeeper = Command1<void, StatsAccess>(
      (c) => _teams.setStatKeeper(teamId, c.uid, on: c.on),
    );
    transferOwnership = Command1<void, String>(
      (newOwner) => _teams.transferOwnership(
        teamId,
        ownerUid: uid,
        newOwnerUid: newOwner,
      ),
    );
    removeMember = Command1<void, String>(
      (uid) => _teams.removeMember(teamId, uid),
    );
    deletePlay = Command1<void, String>((id) => _plays.deletePlay(teamId, id));

    _subs = [
      _teams.watchTeam(teamId).listen((t) {
        _team = t;
        _teamLoaded = true;
        _watchRoster();
        _watchInviteCode();
        _watchMeetings();
        notifyListeners();
      }, onError: _onError),
      _plays.watchPlays(teamId).listen((p) {
        _playList = p;
        notifyListeners();
      }, onError: _onError),
      eventRepository.watchEvents(teamId).listen((e) {
        _teamEvents = e;
        notifyListeners();
      }, onError: _onError),
    ];
  }

  final String teamId;
  final TeamRepository _teams;
  final PlayRepository _plays;
  final MeetingRepository? _meetings;
  final AuthRepository _auth;
  final DateTime Function() _clock;
  late final List<StreamSubscription<Object?>> _subs;
  StreamSubscription<List<RosterPlayer>>? _rosterSub;
  StreamSubscription<String?>? _inviteSub;
  StreamSubscription<List<TeamMeeting>>? _meetingSub;
  TeamRole? _meetingRole;

  String? _inviteCode;

  /// Shown to owners, coaches and captains only; null for everyone else.
  String? get inviteCode => _inviteCode;

  /// Only admins may read the code, so watch it only while the role allows.
  void _watchInviteCode() {
    if (_team != null && canShareCode) {
      _inviteSub ??= _teams.watchInviteCode(teamId).listen((c) {
        _inviteCode = c;
        notifyListeners();
      }, onError: (Object _) => _inviteCode = null);
    } else if (_inviteSub != null) {
      _inviteSub?.cancel();
      _inviteSub = null;
      _inviteCode = null;
    }
  }

  /// (Re)subscribes to meetings when the role changes: it decides which
  /// meetings the member may see.
  void _watchMeetings() {
    final team = _team;
    final meetings = _meetings;
    if (team == null || meetings == null) return;
    final role = team.roleOf(uid);
    if (_meetingSub != null && role == _meetingRole) return;
    _meetingRole = role;
    _meetingSub?.cancel();
    _meetingSub = meetings.watchMeetings(team, uid).listen((m) {
      _meetingEvents = [
        for (final meeting in m)
          if (!meeting.isEnded) meeting.toEvent(),
      ];
      notifyListeners();
    }, onError: _onError);
  }

  bool? _rosterWithStatus;

  /// (Re)subscribes to the roster once the role is known, and when it
  /// changes: only admins may read paid and USA Ultimate status.
  void _watchRoster() {
    if (_team == null) return;
    final withStatus = canSeeRosterStatus;
    if (_rosterSub != null && withStatus == _rosterWithStatus) return;
    _rosterWithStatus = withStatus;
    _rosterSub?.cancel();
    _rosterSub = _teams.watchRoster(teamId, withStatus: withStatus).listen((r) {
      _roster = r;
      notifyListeners();
    }, onError: _onError);
  }

  Team? _team;
  Team? get team => _team;

  bool _teamLoaded = false;

  /// True once the first team snapshot arrived (or failed).
  bool get loaded => _teamLoaded || _error != null;

  List<RosterPlayer> _roster = const [];
  List<RosterPlayer> get roster => _roster;

  bool _unconfirmedOnly = false;

  /// Roster tab shows only players not yet on USA Ultimate or unpaid.
  bool get unconfirmedOnly => _unconfirmedOnly;

  void setUnconfirmedOnly(bool value) {
    _unconfirmedOnly = value;
    notifyListeners();
  }

  List<RosterPlayer> get visibleRoster => _unconfirmedOnly && canSeeRosterStatus
      ? [
          for (final p in _roster)
            if (!p.confirmed) p,
        ]
      : _roster;

  int get onUsauCount => _roster.where((p) => p.onUsau ?? false).length;
  int get paidCount => _roster.where((p) => p.paid).length;
  int get confirmedCount => _roster.where((p) => p.confirmed).length;

  /// Flips a player's Paid mark.
  void togglePaid(RosterPlayer p) =>
      savePlayer.execute(p.copyWith(paid: !p.paid));

  List<Play> _playList = const [];
  List<Play> get plays => _playList;

  List<TeamEvent> _teamEvents = const [];

  /// Meetings the user can see, as schedule entries
  /// ([EventType.meeting]).
  List<TeamEvent> _meetingEvents = const [];

  /// All events and meetings, sorted by start time.
  List<TeamEvent> get events =>
      [..._teamEvents, ..._meetingEvents]
        ..sort((a, b) => a.startsAt.compareTo(b.startsAt));

  /// Events that haven't finished yet, soonest first.
  List<TeamEvent> get upcomingEvents {
    final now = _clock();
    return [
      for (final e in events)
        if (!(e.endsAt ?? e.startsAt.add(const Duration(hours: 2))).isBefore(
          now,
        ))
          e,
    ];
  }

  /// Events starting on the calendar day of [day].
  List<TeamEvent> eventsOn(DateTime day) => [
    for (final e in events)
      if (DateUtils.isSameDay(e.startsAt, day)) e,
  ];

  Object? _error;
  Object? get error => _error;

  String get uid => _auth.currentUser?.uid ?? '';
  TeamRole? get myRole => _team?.roleOf(uid);
  bool get canEdit => myRole?.canEdit ?? false;

  /// Paid marks, USA Ultimate status and sync are for team admins; players
  /// see only names, positions and numbers.
  bool get canSeeRosterStatus => canEdit;
  bool get isOwner => myRole == TeamRole.owner;
  bool get canSetRoles => myRole?.canSetRoles ?? false;
  bool get canShareCode => myRole?.canShareCode ?? false;
  bool get canRegenerateCode => myRole?.canRegenerateCode ?? false;

  /// Whether the member menu applies to [memberUid]: the owner manages
  /// anyone but themself; coaches and captains remove players.
  bool canManage(String memberUid) {
    if (memberUid == uid) return false;
    final target = _team?.roleOf(memberUid);
    final me = myRole;
    if (target == null || me == null) return false;
    return me.canSetRoles || me.canRemove(target);
  }

  bool canRemove(String memberUid) {
    final target = _team?.roleOf(memberUid);
    return memberUid != uid &&
        target != null &&
        (myRole?.canRemove(target) ?? false);
  }

  late final Command1<void, RosterPlayer> savePlayer;
  late final Command1<void, String> deletePlayer;
  late final Command0<void> regenerateInviteCode;
  late final Command1<void, RoleChange> setMemberRole;

  /// Gives a player stats access, or takes it away. Owner only.
  late final Command1<void, StatsAccess> setStatKeeper;

  /// Hands the team to the given member; the owner becomes a player.
  late final Command1<void, String> transferOwnership;
  late final Command1<void, String> removeMember;
  late final Command1<void, String> deletePlay;

  void _onError(Object e) {
    _error = e;
    notifyListeners();
  }

  Future<Result<void>> _regenerateInviteCode() =>
      _teams.regenerateInviteCode(teamId);

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _rosterSub?.cancel();
    _inviteSub?.cancel();
    _meetingSub?.cancel();
    super.dispose();
  }
}
