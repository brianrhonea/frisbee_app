import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/meeting/meeting_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../domain/models/meeting.dart';
import '../../../domain/models/team.dart';
import '../../../utils/command.dart';

/// Backs the meeting page: details, who's invited and RSVPs.
class MeetingDetailViewModel extends ChangeNotifier {
  MeetingDetailViewModel({
    required this.teamId,
    required this.meetingId,
    required MeetingRepository meetingRepository,
    required TeamRepository teamRepository,
    required AuthRepository authRepository,
  }) : _meetings = meetingRepository,
       _auth = authRepository {
    setRsvp = Command1<void, MeetingRsvp?>(
      (a) => _meetings.setRsvp(teamId, meetingId, uid, a),
    );
    deleteMeeting = Command0<void>(
      () => _meetings.deleteMeeting(teamId, meetingId),
    );
    _subs = [
      _meetings.watchMeeting(teamId, meetingId).listen((m) {
        _meeting = m;
        _loaded = true;
        notifyListeners();
      }, onError: _onError),
      teamRepository.watchTeam(teamId).listen((t) {
        _team = t;
        notifyListeners();
      }, onError: _onError),
    ];
  }

  final String teamId;
  final String meetingId;
  final MeetingRepository _meetings;
  final AuthRepository _auth;
  late final List<StreamSubscription<Object?>> _subs;

  late final Command1<void, MeetingRsvp?> setRsvp;
  late final Command0<void> deleteMeeting;

  TeamMeeting? _meeting;
  TeamMeeting? get meeting => _meeting;

  Team? _team;

  bool _loaded = false;
  bool get loaded => (_loaded && _team != null) || _error != null;

  Object? _error;
  Object? get error => _error;

  String get uid => _auth.currentUser?.uid ?? '';

  /// Admins edit, start and delete meetings.
  bool get canEdit => _team?.canEdit(uid) ?? false;

  MeetingRsvp? get myRsvp => _meeting?.rsvpOf(uid);

  /// Whether the user waits for an admin before joining.
  bool get needsApproval => switch ((_meeting, _team)) {
    (final m?, final t?) => m.needsApproval(t, uid),
    _ => false,
  };

  String nameOf(String memberUid) => _team?.nameOf(memberUid) ?? 'Member';

  List<String> _names(Iterable<String> uids) =>
      [for (final u in uids) nameOf(u)]
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  /// Invitee names per answer.
  Map<MeetingRsvp, List<String>> get responses {
    final invited = _invited;
    return {
      for (final a in MeetingRsvp.values)
        a: _names(
          (_meeting?.responders(a) ?? const []).where(invited.contains),
        ),
    };
  }

  Set<String> get _invited => switch ((_meeting, _team)) {
    (final m?, final t?) => m.invitees(t).toSet(),
    _ => const {},
  };

  /// Invitees who haven't answered.
  List<String> get noResponse {
    final answered = _meeting?.rsvps.keys.toSet() ?? const {};
    return _names(_invited.where((u) => !answered.contains(u)));
  }

  int get inviteeCount => _invited.length;

  void _onError(Object e) {
    _error = e;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    setRsvp.dispose();
    deleteMeeting.dispose();
    super.dispose();
  }
}
