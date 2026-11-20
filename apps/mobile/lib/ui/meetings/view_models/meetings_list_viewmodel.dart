import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/meeting/meeting_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../domain/models/meeting.dart';
import '../../../domain/models/team.dart';

/// Backs a team's Meetings list (the website's MeetingsList): live
/// meetings first, then what's coming up, past ones on request. Admins
/// schedule them.
class MeetingsListViewModel extends ChangeNotifier {
  MeetingsListViewModel({
    required this.teamId,
    required MeetingRepository meetingRepository,
    required TeamRepository teamRepository,
    required AuthRepository authRepository,
    DateTime Function()? clock,
  }) : _meetings = meetingRepository,
       _auth = authRepository,
       _clock = clock ?? DateTime.now {
    _teamSub = teamRepository.watchTeam(teamId).listen((t) {
      _team = t;
      _teamLoaded = true;
      _watchMeetings();
      notifyListeners();
    }, onError: _onError);
  }

  final String teamId;
  final MeetingRepository _meetings;
  final AuthRepository _auth;
  final DateTime Function() _clock;
  late final StreamSubscription<Team?> _teamSub;
  StreamSubscription<List<TeamMeeting>>? _meetingSub;
  String? _meetingKey;

  Team? _team;
  bool _teamLoaded = false;
  List<TeamMeeting>? _all;

  Object? _error;
  Object? get error => _error;

  String get uid => _auth.currentUser?.uid ?? '';

  bool get loaded =>
      _error != null || (_teamLoaded && (_team == null || _all != null));

  /// The team's name, for the header (null until it loads).
  String? get teamName => _team?.name;

  /// Whether the user is on the team; others see no meetings.
  bool get isMember => _team?.roleOf(uid) != null;

  /// Whether the team has Meetings on (Settings › Sections).
  bool get meetingsOn => _team?.hasSection(OptionalSection.meetings) ?? true;

  /// Admins schedule meetings.
  bool get canCreate => _team?.has(uid, TeamPermission.manageEvents) ?? false;

  bool _showPast = false;

  /// Past meetings instead of upcoming ones.
  bool get showPast => _showPast;

  void setShowPast(bool past) {
    if (past == _showPast) return;
    _showPast = past;
    notifyListeners();
  }

  DateTime get _today {
    final now = _clock();
    return DateTime(now.year, now.month, now.day);
  }

  /// Over: ended, or not live and starting before today.
  bool _isPast(TeamMeeting m) =>
      m.isEnded || (!m.isLive && m.startsAt.isBefore(_today));

  List<TeamMeeting> get _meetingsList => _all ?? const [];

  /// Meetings under way now.
  List<TeamMeeting> get live => [
    for (final m in _meetingsList)
      if (m.isLive) m,
  ];

  /// Meetings still to come, soonest first.
  List<TeamMeeting> get upcoming => [
    for (final m in _meetingsList)
      if (!m.isLive && !_isPast(m)) m,
  ];

  /// Meetings that are over, newest first.
  List<TeamMeeting> get past => [
    for (final m in _meetingsList.reversed)
      if (_isPast(m)) m,
  ];

  MeetingRsvp? myRsvp(TeamMeeting m) => m.rsvpOf(uid);

  /// Unanswered and not over yet (MeetingDetailViewModel.needsRsvp).
  bool needsRsvp(TeamMeeting m) =>
      !m.isEnded &&
      myRsvp(m) == null &&
      (m.endsAt ?? m.startsAt).isAfter(_clock());

  /// Number of invitees attending.
  int attendingCount(TeamMeeting m) =>
      m.responders(MeetingRsvp.attending).length;

  /// (Re)subscribes when the role or Manage events changes: they decide
  /// which meetings the member may see.
  void _watchMeetings() {
    final team = _team;
    if (team == null || team.roleOf(uid) == null) {
      _meetingSub?.cancel();
      _meetingSub = null;
      _meetingKey = null;
      _all = const [];
      return;
    }
    final key =
        '${team.roleOf(uid)?.name}/'
        '${team.has(uid, TeamPermission.manageEvents)}';
    if (_meetingSub != null && key == _meetingKey) return;
    _meetingKey = key;
    _meetingSub?.cancel();
    _meetingSub = _meetings.watchMeetings(team, uid).listen((m) {
      _all = [...m]..sort((a, b) => a.startsAt.compareTo(b.startsAt));
      notifyListeners();
    }, onError: _onError);
  }

  void _onError(Object e) {
    _error = e;
    notifyListeners();
  }

  @override
  void dispose() {
    _teamSub.cancel();
    _meetingSub?.cancel();
    super.dispose();
  }
}
