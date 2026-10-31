import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/meeting/meeting_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../domain/models/meeting.dart';
import '../../../domain/models/team.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

typedef MeetingMember = ({String uid, String name, TeamRole role});

/// Creates or edits a team meeting. Form state lives in the screen; this
/// loads the team and the original, and saves the submitted draft.
class MeetingEditorViewModel extends ChangeNotifier {
  MeetingEditorViewModel({
    required this.teamId,
    required this.meetingId,
    required MeetingRepository meetingRepository,
    required TeamRepository teamRepository,
    required AuthRepository authRepository,
    DateTime? initialDay,
  }) : _meetings = meetingRepository,
       _teams = teamRepository,
       _auth = authRepository,
       _initialDay = initialDay {
    load = Command0<void>(_load)..execute();
    save = Command1<String, TeamMeeting>(_save);
  }

  final String teamId;

  /// Null when creating a meeting.
  final String? meetingId;
  final MeetingRepository _meetings;
  final TeamRepository _teams;
  final AuthRepository _auth;
  final DateTime? _initialDay;

  late final Command0<void> load;

  /// Result value is the saved meeting id.
  late final Command1<String, TeamMeeting> save;

  bool get isNew => meetingId == null;

  String get _uid => _auth.currentUser?.uid ?? '';

  Team? _team;
  TeamMeeting? _original;

  bool get canEdit => _team?.canEdit(_uid) ?? false;

  /// Starting values for the form: a new meeting invites everyone.
  TeamMeeting get initial =>
      _original ??
      TeamMeeting(
        id: '',
        title: '',
        startsAt: _defaultStart(_initialDay ?? DateTime.now()),
        inviteRoles: {
          for (final r in TeamRole.values)
            if (!r.canEdit) r,
        },
      );

  /// 7 PM on [day], after practice.
  static DateTime _defaultStart(DateTime day) =>
      DateTime(day.year, day.month, day.day, 19);

  /// Roles that can be invited; admins always are.
  List<TeamRole> get invitableRoles =>
      TeamRole.values.where((r) => !r.canEdit).toList();

  /// Members who can be invited one by one, by name.
  List<MeetingMember> get invitableMembers {
    final team = _team;
    if (team == null) return const [];
    return [
      for (final MapEntry(key: uid, value: role) in team.members.entries)
        if (!role.canEdit) (uid: uid, name: team.nameOf(uid), role: role),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  Future<Result<void>> _load() async {
    try {
      _team = await _teams.watchTeam(teamId).first;
      final id = meetingId;
      if (id != null) {
        _original = await _meetings.watchMeeting(teamId, id).first;
        if (_original == null) {
          return Result.error(Exception('Meeting not found.'));
        }
      }
    } on Exception catch (e) {
      return Result.error(e);
    }
    notifyListeners();
    if (!canEdit) {
      return Result.error(Exception('Only admins can schedule meetings.'));
    }
    return const Result.ok(null);
  }

  Future<Result<String>> _save(TeamMeeting draft) async {
    final team = _team;
    if (team == null || !canEdit) {
      return Result.error(Exception('Only admins can schedule meetings.'));
    }
    if (draft.inviteUsers.length > TeamMeeting.maxInviteUsers) {
      return Result.error(
        Exception('Invite at most ${TeamMeeting.maxInviteUsers} people.'),
      );
    }
    // Per-person invites only for people not invited by role, and only
    // current members.
    final users = {
      for (final uid in draft.inviteUsers)
        if (team.roleOf(uid) case final role?)
          if (!role.canEdit && !draft.inviteRoles.contains(role)) uid,
    };
    return _meetings.saveMeeting(
      teamId,
      draft.copyWith(id: meetingId ?? '', inviteUsers: users),
      _uid,
    );
  }
}
