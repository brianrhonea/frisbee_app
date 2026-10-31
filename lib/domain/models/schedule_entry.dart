import 'team.dart';
import 'team_event.dart';

/// An event on the user's schedule: one of their teams' events, or a
/// personal event when [team] is null.
class ScheduleEntry {
  const ScheduleEntry({required this.event, this.team});

  final TeamEvent event;
  final Team? team;

  bool get isPersonal => team == null;
}
