import 'model_utils.dart';

/// What a notification is about. Each category can be turned off for every
/// team, and the [perTeam] ones can be overridden for one team.
///
/// Stored by name in `users/{uid}/settings/notifications`; the Cloud
/// Functions in functions/src/notifications read the same names, so keep
/// the two in step.
enum NotificationCategory {
  chat(
    'Team chat',
    'New messages in team chat rooms you can read',
    perTeam: true,
  ),
  directMessages('Direct messages', 'New private messages', perTeam: false),
  eventChanges(
    'Event changes',
    'Team events added, changed or cancelled',
    perTeam: true,
  ),
  eventReminders(
    'Event reminders',
    'A reminder a day before each team or personal event',
    perTeam: true,
  ),
  teamActivity(
    'Team activity',
    'New and updated plays, and requests to join your groups',
    perTeam: true,
  ),
  meetings(
    'Meetings',
    "Meeting invites, and when a meeting you're attending starts",
    perTeam: true,
  ),
  posts(
    'Posts you follow',
    'New posts from people, teams and tournaments whose bell you turned on',
    perTeam: true,
  );

  const NotificationCategory(
    this.label,
    this.description, {
    required this.perTeam,
  });

  final String label;
  final String description;

  /// Whether a team can override this category.
  final bool perTeam;

  static Iterable<NotificationCategory> get teamCategories =>
      values.where((c) => c.perTeam);
}

/// Which notifications a user wants. Everything is on until turned off.
///
/// [teams] holds per-team overrides: a category set there wins over
/// [categories] for that team. [mutedRooms] silences single chat rooms
/// (see [roomKey]).
class NotificationPreferences {
  const NotificationPreferences({
    this.categories = const {},
    this.teams = const {},
    this.mutedRooms = const {},
  });

  final Map<NotificationCategory, bool> categories;
  final Map<String, Map<NotificationCategory, bool>> teams;
  final Set<String> mutedRooms;

  static String roomKey(String teamId, String roomId) => '$teamId/$roomId';

  bool isOn(NotificationCategory category) => categories[category] ?? true;

  /// Whether [category] is on for [teamId], after its override.
  bool isOnFor(NotificationCategory category, String teamId) =>
      teams[teamId]?[category] ?? isOn(category);

  bool hasOverrides(String teamId) => teams[teamId]?.isNotEmpty ?? false;

  bool isRoomMuted(String teamId, String roomId) =>
      mutedRooms.contains(roomKey(teamId, roomId));

  factory NotificationPreferences.fromMap(Map<String, dynamic> map) {
    Map<NotificationCategory, bool> parse(Object? raw) => {
      if (raw is Map)
        for (final c in NotificationCategory.values)
          if (raw[c.name] is bool) c: raw[c.name] as bool,
    };
    return NotificationPreferences(
      categories: parse(map['categories']),
      teams: {
        for (final e in ((map['teams'] as Map?) ?? const {}).entries)
          if (parse(e.value) case final o when o.isNotEmpty) '${e.key}': o,
      },
      mutedRooms: {
        for (final r in (map['mutedRooms'] as List? ?? const [])) '$r',
      },
    );
  }
}

/// An entry in the in-app notification feed (`users/{uid}/notifications`),
/// written by Cloud Functions. Chat and direct messages collapse into one
/// entry per room or conversation; [count] is how many arrived since it was
/// last read.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.category,
    required this.title,
    this.body = '',
    this.route,
    this.teamId,
    this.createdAt,
    this.read = false,
    this.count = 1,
  });

  final String id;
  final NotificationCategory category;
  final String title;
  final String body;

  /// Where tapping it goes, e.g. `/teams/t1/chats/general`.
  final String? route;
  final String? teamId;
  final DateTime? createdAt;
  final bool read;
  final int count;

  factory AppNotification.fromMap(String id, Map<String, dynamic> map) =>
      AppNotification(
        id: id,
        category: enumByName(
          NotificationCategory.values,
          map['category'],
          NotificationCategory.teamActivity,
        ),
        title: map['title'] as String? ?? '',
        body: map['body'] as String? ?? '',
        route: map['route'] as String?,
        teamId: map['teamId'] as String?,
        createdAt: parseDate(map['createdAt']),
        read: map['read'] as bool? ?? false,
        count: (map['count'] as num?)?.toInt() ?? 1,
      );
}

/// Whether this device can show push notifications.
enum PushStatus {
  /// No push on this platform (Windows); the in-app feed still works.
  unsupported,

  /// The user hasn't been asked yet.
  notDetermined,

  /// Turned off in the system settings.
  denied,
  enabled,
}
