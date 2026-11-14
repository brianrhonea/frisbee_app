import '../../../domain/models/calendar.dart';
import '../../../domain/models/team_event.dart';
import '../../../utils/result.dart';

/// Calendars as in Outlook or Apple Calendar (docs/requirements.md U11,
/// D4): the user's own, invites to others', and the events on all of them.
/// Through the API, which checks each calendar's members; "My calendar"'s
/// own events are also read live from `users/{uid}/events`
/// (EventRepository.watchMyEvents).
abstract class CalendarRepository {
  /// False without an API (no `API_BASE_URL`): screens hide calendars.
  bool get enabled;

  /// Every calendar the user is on: My calendar first.
  Future<Result<List<CalendarInfo>>> calendars();

  Future<Result<CalendarInfo>> create(String name, CalendarColor color);

  /// Renames or recolors one of the user's calendars.
  Future<Result<void>> update(
    String calendarId, {
    String? name,
    CalendarColor? color,
  });

  /// Deletes one of the user's calendars (not My calendar) and its events.
  Future<Result<void>> delete(String calendarId);

  /// Invites [uid], or changes a pending invite's [role].
  Future<Result<void>> invite(String calendarId, String uid, CalendarRole role);

  Future<Result<void>> cancelInvite(String calendarId, String uid);

  Future<Result<void>> setRole(
    String calendarId,
    String uid,
    CalendarRole role,
  );

  /// The owner takes [uid] off, or the user leaves ([uid] is theirs).
  Future<Result<void>> removeMember(String calendarId, String uid);

  /// Invites waiting for the user.
  Future<Result<List<CalendarInvite>>> invites();

  Future<Result<void>> accept(String calendarId);

  Future<Result<void>> decline(String calendarId);

  /// Events starting in [from, to) on every calendar the user is on (at
  /// most 92 days).
  Future<Result<List<CalendarEntry>>> events(DateTime from, DateTime to);

  /// One event, for editing.
  Future<Result<TeamEvent>> event(String calendarId, String eventId);

  /// Adds [event] (empty id) or replaces it; returns its id.
  Future<Result<String>> saveEvent(String calendarId, TeamEvent event);

  Future<Result<void>> deleteEvent(String calendarId, String eventId);

  /// The user's subscription link.
  Future<Result<CalendarFeed>> feed();

  /// A new subscription link; the old one stops working.
  Future<Result<CalendarFeed>> resetFeed();

  /// Turns the subscription link off.
  Future<Result<void>> stopFeed();
}
