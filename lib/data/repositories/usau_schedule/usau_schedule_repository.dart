import '../../../domain/models/usau_schedule.dart';
import '../../../utils/result.dart';

abstract class UsauScheduleRepository {
  /// The divisions with a published schedule on the USA Ultimate event page
  /// at [eventUrl] (a tournament's `url`). Empty when none are posted.
  Future<Result<List<UsauDivision>>> getDivisions(String eventUrl);

  /// [division]'s pools, games and brackets at [eventUrl]. With [refresh],
  /// fetches it again instead of using a cached copy.
  Future<Result<UsauDivisionSchedule>> getSchedule(
    String eventUrl,
    UsauDivision division, {
    bool refresh = false,
  });
}
