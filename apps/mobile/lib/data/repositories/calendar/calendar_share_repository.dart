import '../../../domain/models/shared_calendar.dart';
import '../../../utils/result.dart';

/// Sharing the user's personal calendar with chosen people, and the
/// calendars others share with them (docs/requirements.md U11, D4).
/// Through the API: viewers never read anyone's events directly.
abstract class CalendarShareRepository {
  /// False without an API (no `API_BASE_URL`): screens hide sharing.
  bool get enabled;

  /// Who the user shares their calendar with.
  Future<Result<List<CalendarPerson>>> viewers();

  /// Replaces the list; an empty one stops sharing. Returns the saved list.
  Future<Result<List<CalendarPerson>>> setViewers(List<String> uids);

  /// Calendars shared with the user: events starting in [from, to).
  Future<Result<List<SharedCalendar>>> shared(DateTime from, DateTime to);
}
