import 'team.dart';
import 'team_event.dart';

/// An event on the user's schedule: one of their teams' events or meetings,
/// or a personal event when [team] is null.
class ScheduleEntry {
  const ScheduleEntry({required this.event, this.team});

  final TeamEvent event;
  final Team? team;

  bool get isPersonal => team == null;

  /// A team meeting (see `TeamMeeting.toEvent`) rather than an event.
  bool get isMeeting => event.type == EventType.meeting;
}
