/// Which meeting room, if any, the user has open on this device, so the
/// app doesn't alert them that a meeting they're already in has started.
class MeetingPresence {
  String? _current;

  static String _key(String teamId, String meetingId) => '$teamId/$meetingId';

  void enter(String teamId, String meetingId) =>
      _current = _key(teamId, meetingId);

  void leave(String teamId, String meetingId) {
    if (_current == _key(teamId, meetingId)) _current = null;
  }

  bool isIn(String teamId, String meetingId) =>
      _current == _key(teamId, meetingId);
}
