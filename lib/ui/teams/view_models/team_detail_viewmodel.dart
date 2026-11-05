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
typedef MemberRoles = ({String uid, Set<String> roleIds});

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
    setMemberRoles = Command1<void, MemberRoles>((c) async {
      final team = _team;
      if (team == null) return Result.error(Exception('No team'));
      return _teams.saveRoles(
        team,
        roles: team.roles,
        memberRoles: {...team.memberRoles, c.uid: c.roleIds},
      );
    });
    deletePlay = Command1<void, String>((id) => _plays.deletePlay(teamId, id));
    approveJoinRequest = Command1<void, GroupJoinRequest>(
      (r) => _teams.approveJoinRequest(teamId, r),
    );
    declineJoinRequest = Command1<void, String>(
      (uid) => _teams.declineJoinRequest(teamId, uid),
    );

    _subs = [
      _teams.watchTeam(teamId).listen((t) {
        _team = t;
        _teamLoaded = true;
        _watchRoster();
        _watchJoinRequests();
        _watchMeetings();
        _migrateOrganizers();
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
  StreamSubscription<List<TeamMeeting>>? _meetingSub;
  String? _meetingKey;
  bool _migrating = false;

  StreamSubscription<List<GroupJoinRequest>>? _requestSub;
  List<GroupJoinRequest> _joinRequests = const [];

  /// People asking to join the group, for owners and organizers.
  List<GroupJoinRequest> get joinRequests => _joinRequests;

  late final Command1<void, GroupJoinRequest> approveJoinRequest;
  late final Command1<void, String> declineJoinRequest;

  /// Only members who can manage members may read join requests.
  void _watchJoinRequests() {
    final team = _team;
    if (team != null && team.isCommunity && canManageMembers) {
      _requestSub ??= _teams.watchJoinRequests(teamId).listen((r) {
        _joinRequests = r;
        notifyListeners();
      }, onError: (Object _) => _joinRequests = const []);
    } else if (_requestSub != null) {
      _requestSub?.cancel();
      _requestSub = null;
      _joinRequests = const [];
    }
  }

  /// (Re)subscribes to meetings when the role or Manage events changes:
  /// they decide which meetings the member may see.
  void _watchMeetings() {
    final team = _team;
    final meetings = _meetings;
    if (team == null || meetings == null) return;
    final key =
        '${team.roleOf(uid)?.name}/'
        '${team.has(uid, TeamPermission.manageEvents)}';
    if (_meetingSub != null && key == _meetingKey) return;
    _meetingKey = key;
    _meetingSub?.cancel();
    _meetingSub = meetings.watchMeetings(team, uid).listen((m) {
      _meetingEvents = [
        for (final meeting in m)
          if (!meeting.isEnded) meeting.toEvent(),
      ];
      notifyListeners();
    }, onError: _onError);
  }

  /// Groups had organizers (the captain tier) before custom roles. When
  /// the owner opens such a group, move them into an "Organizer" role with
  /// the same powers, once.
  Future<void> _migrateOrganizers() async {
    final team = _team;
    if (team == null ||
        _migrating ||
        !team.needsOrganizerMigration ||
        team.roleOf(uid) != TeamRole.owner) {
      return;
    }
    _migrating = true;
    final organizers = {
      for (final e in team.members.entries)
        if (e.value == TeamRole.captain) e.key,
    };
    final existing = team.roles.values
        .where((r) => r.name == 'Organizer')
        .firstOrNull;
    final role =
        existing ??
        CustomRole(
          id: newRoleId(),
          name: 'Organizer',
          color: 0xFF1E88E5,
          position: team.roles.length,
          permissions: const {
            TeamPermission.manageTeam,
            TeamPermission.manageMembers,
            TeamPermission.manageChats,
            TeamPermission.manageEvents,
          },
        );
    final result = await _teams.saveRoles(
      team,
      roles: {...team.roles, role.id: role},
      memberRoles: {
        ...team.memberRoles,
        for (final uid in organizers) uid: {...?team.memberRoles[uid], role.id},
      },
      demote: organizers,
    );
    // Try again next time the team changes only if this failed.
    if (result is Error) _migrating = false;
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

  /// Events that have finished, most recent first.
  List<TeamEvent> get pastEvents {
    final upcoming = upcomingEvents.toSet();
    return [
      for (final e in events.reversed)
        if (!upcoming.contains(e)) e,
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
  bool get canEdit => _team?.canEdit(uid) ?? false;

  /// Invite, approve and remove members.
  bool get canManageMembers =>
      _team?.has(uid, TeamPermission.manageMembers) ?? false;

  /// Paid marks, USA Ultimate status and sync are for team admins; players
  /// see only names, positions and numbers.
  bool get canSeeRosterStatus => canEdit;
  bool get isOwner => myRole == TeamRole.owner;

  /// Tiers, custom roles and stats access are the owner's.
  bool get canSetRoles => myRole?.canSetRoles ?? false;

  /// Members who can manage members show the team's rotating invite code
  /// (InviteCodeViewModel). Groups have none: they're joined from the
  /// directory.
  bool get canShareCode => canManageMembers && !(_team?.isCommunity ?? true);

  /// Whether the member menu applies to [memberUid]: the owner manages
  /// anyone but themself; others with Manage members remove plain members.
  bool canManage(String memberUid) =>
      memberUid != uid && (canSetRoles || canRemove(memberUid));

  bool canRemove(String memberUid) =>
      memberUid != uid && (_team?.canRemove(uid, memberUid) ?? false);

  late final Command1<void, RosterPlayer> savePlayer;
  late final Command1<void, MemberRoles> setMemberRoles;
  late final Command1<void, String> deletePlayer;
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

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _rosterSub?.cancel();
    _requestSub?.cancel();
    _meetingSub?.cancel();
    super.dispose();
  }
}
