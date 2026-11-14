import 'dart:ui' show Color;

import 'model_utils.dart';
import 'team_event.dart';

/// Calendars, as in Outlook or Apple Calendar (docs/requirements.md U11,
/// D4; `packages/shared/src/calendar.ts`). Everyone has "My calendar"
/// (id: their uid; its events are `users/{uid}/events`) and may make more.
/// The owner invites people as Can view or Can edit; nothing is shared
/// until they accept. Viewers never see notes.

/// A calendar's color (`calendarColors`), drawn the same on the website.
enum CalendarColor {
  green(Color(0xFF3FA34D)),
  blue(Color(0xFF2F7FD8)),
  purple(Color(0xFF8B5CF6)),
  pink(Color(0xFFE0559B)),
  red(Color(0xFFE5484D)),
  orange(Color(0xFFF08C2E)),
  yellow(Color(0xFFD9A400)),
  teal(Color(0xFF14A3A3)),
  gray(Color(0xFF7C8A86));

  const CalendarColor(this.color);
  final Color color;

  String get label => name[0].toUpperCase() + name.substring(1);
}

/// What someone may do on a calendar.
enum CalendarRole {
  owner('Owner'),
  edit('Can edit'),
  view('Can view');

  const CalendarRole(this.label);
  final String label;

  bool get canEdit => this != view;

  /// What an invite or a member change may grant.
  static const shareable = [view, edit];
}

/// Someone on a calendar, as their profile shows them (`CalendarPerson`).
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

/// Someone on a calendar with their role, or invited with one.
typedef CalendarMember = ({CalendarPerson person, CalendarRole role});

List<CalendarMember> _members(Object? list) => [
  for (final m in (list as List?) ?? const [])
    if (m is Map)
      (
        person: CalendarPerson.fromMap(m.cast<String, Object?>()),
        role: enumByName(CalendarRole.values, m['role'], CalendarRole.view),
      ),
];

/// A calendar as the user sees it (`CalendarInfo`). [members] and
/// [pending] are only filled in for its owner.
class CalendarInfo {
  const CalendarInfo({
    required this.id,
    required this.name,
    required this.color,
    required this.owner,
    required this.role,
    this.isDefault = false,
    this.members = const [],
    this.pending = const [],
  });

  final String id;
  final String name;
  final CalendarColor color;
  final CalendarPerson owner;

  /// The user's role.
  final CalendarRole role;

  /// "My calendar": can't be deleted.
  final bool isDefault;
  final List<CalendarMember> members;
  final List<CalendarMember> pending;

  bool get isMine => role == CalendarRole.owner;
  bool get canEdit => role.canEdit;

  /// Other people are on it or invited, so notes aren't only the user's.
  bool get isShared => !isMine || members.length > 1 || pending.isNotEmpty;

  /// "Training", or "Training · Pat" on someone else's.
  String get label => isMine ? name : '$name · ${owner.name}';

  factory CalendarInfo.fromMap(Map<String, Object?> map) => CalendarInfo(
    id: map['id'] as String? ?? '',
    name: map['name'] as String? ?? 'Calendar',
    color: enumByName(CalendarColor.values, map['color'], CalendarColor.green),
    owner: CalendarPerson.fromMap(
      (map['owner'] as Map?)?.cast<String, Object?>() ?? const {},
    ),
    role: enumByName(CalendarRole.values, map['role'], CalendarRole.view),
    isDefault: map['isDefault'] == true,
    members: _members(map['members']),
    pending: _members(map['pending']),
  );
}

/// An invite waiting for the user (`CalendarInvite`).
class CalendarInvite {
  const CalendarInvite({
    required this.calendarId,
    required this.calendarName,
    required this.color,
    required this.role,
    required this.from,
  });

  final String calendarId;
  final String calendarName;
  final CalendarColor color;
  final CalendarRole role;
  final CalendarPerson from;

  factory CalendarInvite.fromMap(Map<String, Object?> map) => CalendarInvite(
    calendarId: map['calendarId'] as String? ?? '',
    calendarName: map['calendarName'] as String? ?? 'Calendar',
    color: enumByName(CalendarColor.values, map['color'], CalendarColor.green),
    role: enumByName(CalendarRole.values, map['role'], CalendarRole.view),
    from: CalendarPerson.fromMap(
      (map['from'] as Map?)?.cast<String, Object?>() ?? const {},
    ),
  );
}

/// An event on one of the user's calendars (`CalendarEvent`), as a
/// [TeamEvent] so schedules can show it. [TeamEvent.notes] is empty for
/// viewers.
class CalendarEntry {
  const CalendarEntry({required this.calendarId, required this.event});

  final String calendarId;
  final TeamEvent event;

  static CalendarEntry? fromMap(Map<String, Object?> map) {
    // The API sends UTC; schedules show local times.
    final startsAt = parseDate(map['startsAt'])?.toLocal();
    if (startsAt == null) return null;
    return CalendarEntry(
      calendarId: map['calendarId'] as String? ?? '',
      event: TeamEvent(
        id: map['id'] as String? ?? '',
        title: map['title'] as String? ?? 'Event',
        type: enumByName(EventType.values, map['type'], EventType.other),
        startsAt: startsAt,
        endsAt: parseDate(map['endsAt'])?.toLocal(),
        location: map['location'] as String? ?? '',
        notes: map['notes'] as String? ?? '',
      ),
    );
  }
}

/// The user's private subscription link (`CalendarFeedResponse`).
class CalendarFeed {
  const CalendarFeed({this.url, this.webcal});

  /// https, for Google Calendar and Outlook on the web; null until made.
  final String? url;

  /// webcal://, which Apple Calendar and Outlook open to subscribe.
  final String? webcal;

  bool get isOn => url != null;

  factory CalendarFeed.fromMap(Map<String, Object?> map) => CalendarFeed(
    url: map['url'] as String?,
    webcal: map['webcal'] as String?,
  );
}
