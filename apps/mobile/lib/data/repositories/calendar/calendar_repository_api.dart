import '../../../domain/models/calendar.dart';
import '../../../domain/models/team_event.dart';
import '../../../utils/result.dart';
import '../../services/api_client.dart';
import '../../services/time_zone.dart';
import '../../services/pending_ids.dart';
import 'calendar_repository.dart';

/// [CalendarRepository] through the API (`/v1/me/calendars`,
/// `/v1/calendars/*` and `/v1/me/calendar-*`).
class CalendarRepositoryApi implements CalendarRepository {
  CalendarRepositoryApi({
    required ApiClient? api,
    Future<String> Function() timeZone = localTimeZone,
  }) : _api = api,
       _timeZone = timeZone;

  final ApiClient? _api;
  final _ids = PendingIds();

  /// The device's time zone, sent with repeats and "this and following"
  /// edits so times stay put across clock changes.
  final Future<String> Function() _timeZone;

  static const _noApi =
      "Shared calendars aren't available in this version of the app. "
      'Update the app, or use stall10.app.';

  ApiClient get _client =>
      _api ?? (throw const ApiException('unavailable', _noApi));

  @override
  bool get enabled => _api != null;

  static String _id(String id) => Uri.encodeComponent(id);
  static String _cal(String id) => '/v1/calendars/${_id(id)}';

  static List<Map<String, Object?>> _list(
    Map<String, Object?> json,
    String key,
  ) => [
    for (final v in (json[key] as List?) ?? const [])
      if (v is Map) v.cast<String, Object?>(),
  ];

  @override
  Future<Result<List<CalendarInfo>>> calendars() => guard(() async {
    final json = await _client.send('GET', '/v1/me/calendars');
    return [for (final c in _list(json, 'calendars')) CalendarInfo.fromMap(c)];
  });

  @override
  Future<Result<CalendarInfo>> create(String name, CalendarColor color) =>
      guard(
        () async => CalendarInfo.fromMap(
          await _client.post('/v1/me/calendars', {
            'name': name,
            'color': color.name,
          }),
        ),
      );

  @override
  Future<Result<void>> update(
    String calendarId, {
    String? name,
    CalendarColor? color,
  }) => guard(
    () =>
        _client.patch(_cal(calendarId), {'name': ?name, 'color': ?color?.name}),
  );

  @override
  Future<Result<void>> delete(String calendarId) =>
      guard(() => _client.delete(_cal(calendarId)));

  @override
  Future<Result<void>> invite(
    String calendarId,
    String uid,
    CalendarRole role,
  ) => guard(
    () => _client.post('${_cal(calendarId)}/invites', {
      'uid': uid,
      'role': role.name,
    }),
  );

  @override
  Future<Result<void>> cancelInvite(String calendarId, String uid) =>
      guard(() => _client.delete('${_cal(calendarId)}/invites/${_id(uid)}'));

  @override
  Future<Result<void>> setRole(
    String calendarId,
    String uid,
    CalendarRole role,
  ) => guard(
    () => _client.patch('${_cal(calendarId)}/members/${_id(uid)}', {
      'role': role.name,
    }),
  );

  @override
  Future<Result<void>> removeMember(String calendarId, String uid) =>
      guard(() => _client.delete('${_cal(calendarId)}/members/${_id(uid)}'));

  @override
  Future<Result<List<CalendarInvite>>> invites() => guard(() async {
    final json = await _client.send('GET', '/v1/me/calendar-invites');
    return [for (final i in _list(json, 'invites')) CalendarInvite.fromMap(i)];
  });

  @override
  Future<Result<void>> accept(String calendarId) => guard(
    () => _client.send(
      'POST',
      '/v1/me/calendar-invites/${_id(calendarId)}/accept',
    ),
  );

  @override
  Future<Result<void>> decline(String calendarId) => guard(
    () => _client.send(
      'POST',
      '/v1/me/calendar-invites/${_id(calendarId)}/decline',
    ),
  );

  @override
  Future<Result<List<CalendarEntry>>> events(DateTime from, DateTime to) =>
      guard(() async {
        final q = Uri(
          queryParameters: {
            'from': from.toUtc().toIso8601String(),
            'to': to.toUtc().toIso8601String(),
          },
        ).query;
        final json = await _client.send('GET', '/v1/me/calendar-events?$q');
        return [
          for (final e in _list(json, 'events')) ?CalendarEntry.fromMap(e),
        ];
      });

  @override
  Future<Result<TeamEvent>> event(String calendarId, String eventId) =>
      guard(() async {
        final json = await _client.send(
          'GET',
          '${_cal(calendarId)}/events/${_id(eventId)}',
        );
        final entry = CalendarEntry.fromMap(json);
        if (entry == null) {
          throw const ApiException('not_found', 'This event was deleted.');
        }
        return entry.event;
      });

  /// The fields `calendarEventSchema` takes.
  static Map<String, Object?> _body(TeamEvent e) => {
    'title': e.title,
    'type': e.type.name,
    'startsAt': e.startsAt.toUtc().toIso8601String(),
    'endsAt': e.endsAt?.toUtc().toIso8601String(),
    'location': e.location,
    'notes': e.notes,
  };

  static String _scope(SeriesScope scope) =>
      scope == SeriesScope.following ? '?scope=following' : '';

  @override
  Future<Result<String>> saveEvent(
    String calendarId,
    TeamEvent event, {
    Repeat? repeat,
    SeriesScope scope = SeriesScope.one,
  }) => guard(() async {
    final base = '${_cal(calendarId)}/events';
    final zoned = repeat != null || scope == SeriesScope.following;
    final body = {
      ..._body(event),
      if (event.id.isEmpty && repeat != null) 'repeat': repeat.toJson(),
      if (zoned) 'timeZone': await _timeZone(),
    };
    if (event.id.isEmpty) {
      // The same request retried keeps its id; a 409 means it landed.
      final id = _ids.idFor('event/$calendarId', body, PendingIds.mintId);
      try {
        final json = await _client.post(base, {...body, 'id': id});
        _ids.done(id);
        return json['id'] as String? ?? id;
      } on ApiException catch (e) {
        if (e.code != 'already_exists') rethrow;
        _ids.done(id);
        return id;
      }
    }
    await _client.patch('$base/${_id(event.id)}${_scope(scope)}', body);
    return event.id;
  });

  @override
  Future<Result<void>> deleteEvent(
    String calendarId,
    String eventId, {
    SeriesScope scope = SeriesScope.one,
  }) => guard(
    () => _client.delete(
      '${_cal(calendarId)}/events/${_id(eventId)}${_scope(scope)}',
    ),
  );

  @override
  Future<Result<CalendarFeed>> feed() => guard(
    () async =>
        CalendarFeed.fromMap(await _client.send('GET', '/v1/me/calendar-feed')),
  );

  @override
  Future<Result<CalendarFeed>> resetFeed() => guard(
    () async => CalendarFeed.fromMap(
      await _client.send('POST', '/v1/me/calendar-feed'),
    ),
  );

  @override
  Future<Result<void>> stopFeed() =>
      guard(() => _client.delete('/v1/me/calendar-feed'));
}
