import 'calendar.dart';
import 'team.dart';
import 'team_event.dart';

/// An event on the user's schedule: one of their teams' events or meetings,
/// an event on one of their other calendars ([calendar]: ones they made or
/// accepted an invite to), or one on My calendar when it's neither.
class ScheduleEntry {
  const ScheduleEntry({required this.event, this.team, this.calendar})
    : assert(team == null || calendar == null);

  final TeamEvent event;
  final Team? team;

  /// The calendar it's on, other than the user's own My calendar. Read and
  /// changed through the API ([CalendarInfo.canEdit] says whether the user
  /// may).
  final CalendarInfo? calendar;

  /// On the user's own My calendar (`users/{uid}/events`).
  bool get isPersonal => team == null && calendar == null;

  /// On another calendar: its own color, no page of its own.
  bool get isOnCalendar => calendar != null;

  /// On someone else's calendar.
  bool get isShared => calendar != null && !calendar!.isMine;

  /// A team meeting (see `TeamMeeting.toEvent`) rather than an event.
  bool get isMeeting => event.type == EventType.meeting;

  /// Unique on a schedule: whose it is, then the event.
  String get key =>
      '${team?.id ?? (calendar == null ? 'me' : 'cal-${calendar!.id}')}/${event.id}';
}
