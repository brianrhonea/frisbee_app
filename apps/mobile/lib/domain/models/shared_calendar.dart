import 'model_utils.dart';
import 'team_event.dart';

/// Someone on a calendar share list, or sharing theirs, as their profile
/// shows them (`CalendarPerson` in packages/shared/src/calendar.ts).
class CalendarPerson {
  const CalendarPerson({
    required this.uid,
    required this.name,
    this.username,
    this.photoUrl,
  });

  final String uid;
  final String name;
  final String? username;
  final String? photoUrl;

  factory CalendarPerson.fromMap(Map<String, Object?> map) => CalendarPerson(
    uid: map['uid'] as String? ?? '',
    name: (map['name'] as String?)?.trim().isNotEmpty == true
        ? (map['name'] as String).trim()
        : 'Player',
    username: (map['username'] as String?)?.trim().isNotEmpty == true
        ? map['username'] as String
        : null,
    photoUrl: (map['photoUrl'] as String?)?.isNotEmpty == true
        ? map['photoUrl'] as String
        : null,
  );

  @override
  bool operator ==(Object other) => other is CalendarPerson && other.uid == uid;

  @override
  int get hashCode => uid.hashCode;
}

/// Someone's personal calendar shared with the user (docs/requirements.md
/// D4): read-only, with each event's title, type, time and place, never
/// its notes.
class SharedCalendar {
  const SharedCalendar({required this.owner, required this.events});

  final CalendarPerson owner;
  final List<TeamEvent> events;

  factory SharedCalendar.fromMap(Map<String, Object?> map) => SharedCalendar(
    owner: CalendarPerson.fromMap(
      (map['owner'] as Map?)?.cast<String, Object?>() ?? const {},
    ),
    events: [
      for (final e in (map['events'] as List?) ?? const [])
        if (e is Map)
          if (parseDate(e['startsAt']) case final startsAt?)
            TeamEvent(
              id: e['id'] as String? ?? '',
              title: e['title'] as String? ?? 'Event',
              type: enumByName(EventType.values, e['type'], EventType.other),
              startsAt: startsAt,
              endsAt: parseDate(e['endsAt']),
              location: e['location'] as String? ?? '',
            ),
    ],
  );
}
