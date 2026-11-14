import 'shared_calendar.dart';
import 'team.dart';
import 'team_event.dart';

/// An event on the user's schedule: one of their teams' events or meetings,
/// an event on a calendar someone shares with them ([sharedBy]), or one of
/// their own personal events when it's neither.
class ScheduleEntry {
  const ScheduleEntry({required this.event, this.team, this.sharedBy})
    : assert(team == null || sharedBy == null);

  final TeamEvent event;
  final Team? team;

  /// Whose shared calendar it's on: read-only, never the user's to change.
  final CalendarPerson? sharedBy;

  /// The user's own personal event.
  bool get isPersonal => team == null && sharedBy == null;

  /// On someone else's shared calendar.
  bool get isShared => sharedBy != null;

  /// A team meeting (see `TeamMeeting.toEvent`) rather than an event.
  bool get isMeeting => event.type == EventType.meeting;

  /// Unique on a schedule: whose it is, then the event.
  String get key =>
      '${team?.id ?? (sharedBy == null ? 'me' : 'shared-${sharedBy!.uid}')}/${event.id}';
}
