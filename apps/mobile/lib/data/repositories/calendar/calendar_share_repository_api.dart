import '../../../domain/models/shared_calendar.dart';
import '../../../utils/result.dart';
import '../../services/api_client.dart';
import 'calendar_share_repository.dart';

/// [CalendarShareRepository] through the API (`/v1/me/calendar/*`).
class CalendarShareRepositoryApi implements CalendarShareRepository {
  CalendarShareRepositoryApi({required ApiClient? api}) : _api = api;

  final ApiClient? _api;

  static const _noApi = 'Calendar sharing needs a connection to Stall 10.';

  ApiClient get _client =>
      _api ?? (throw const ApiException('unavailable', _noApi));

  @override
  bool get enabled => _api != null;

  static List<CalendarPerson> _people(Map<String, Object?> json) => [
    for (final v in (json['viewers'] as List?) ?? const [])
      if (v is Map) CalendarPerson.fromMap(v.cast<String, Object?>()),
  ];

  @override
  Future<Result<List<CalendarPerson>>> viewers() => guard(
    () async => _people(await _client.send('GET', '/v1/me/calendar/viewers')),
  );

  @override
  Future<Result<List<CalendarPerson>>> setViewers(List<String> uids) => guard(
    () async => _people(
      await _client.put('/v1/me/calendar/viewers', {'viewers': uids}),
    ),
  );

  @override
  Future<Result<List<SharedCalendar>>> shared(DateTime from, DateTime to) =>
      guard(() async {
        final q = Uri(
          queryParameters: {
            'from': from.toUtc().toIso8601String(),
            'to': to.toUtc().toIso8601String(),
          },
        ).query;
        final json = await _client.send('GET', '/v1/me/calendar/shared?$q');
        return [
          for (final c in (json['calendars'] as List?) ?? const [])
            if (c is Map) SharedCalendar.fromMap(c.cast<String, Object?>()),
        ];
      });
}
