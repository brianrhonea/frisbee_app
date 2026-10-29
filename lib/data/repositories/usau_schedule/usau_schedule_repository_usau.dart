import '../../../domain/models/usau_schedule.dart';
import '../../../utils/result.dart';
import '../../services/usau/usau_client.dart';
import '../../services/usau/usau_parser.dart';
import 'usau_schedule_repository.dart';

/// Scrapes event schedules from USA Ultimate when first opened and keeps
/// them in memory for the rest of the session.
class UsauScheduleRepositoryUsau implements UsauScheduleRepository {
  UsauScheduleRepositoryUsau({required UsauClient client}) : _client = client;

  final UsauClient _client;
  final _divisions = <String, Future<List<UsauDivision>>>{};
  final _schedules = <(String, UsauDivision), Future<UsauDivisionSchedule>>{};

  @override
  Future<Result<List<UsauDivision>>> getDivisions(String eventUrl) => guard(() {
    _checkUrl(eventUrl);
    return _cached(
      _divisions,
      eventUrl,
      () => _client.fetchEventDivisions(eventUrl),
    );
  });

  @override
  Future<Result<UsauDivisionSchedule>> getSchedule(
    String eventUrl,
    UsauDivision division, {
    bool refresh = false,
  }) => guard(() async {
    _checkUrl(eventUrl);
    final key = (eventUrl, division);
    // A refresh can skip the event page and postback once the schedule's
    // own URL is known.
    final previous = refresh ? _schedules.remove(key) : null;
    final known = previous == null ? null : await _urlOf(previous);
    return _cached(
      _schedules,
      key,
      () => known != null
          ? _client.fetchDivisionScheduleAt(known)
          : _client.fetchDivisionSchedule(eventUrl, division),
    );
  });

  Future<String?> _urlOf(Future<UsauDivisionSchedule> schedule) async {
    try {
      final url = (await schedule).url;
      return _isUsau(url) ? url : null;
    } on Exception {
      return null;
    }
  }

  /// Shares one fetch per [key] and drops it on failure so a retry fetches
  /// again.
  Future<T> _cached<K, T>(
    Map<K, Future<T>> cache,
    K key,
    Future<T> Function() fetch,
  ) async {
    final pending = cache[key] ??= fetch();
    try {
      return await pending;
    } catch (_) {
      if (identical(cache[key], pending)) cache.remove(key);
      rethrow;
    }
  }

  static bool _isUsau(String url) =>
      Uri.tryParse(url)?.host == Uri.parse(usauBase).host;

  /// Tournament URLs come from scraped pages; only fetch USAU itself.
  static void _checkUrl(String url) {
    if (!_isUsau(url)) throw Exception('Not a USA Ultimate event page: $url');
  }
}
