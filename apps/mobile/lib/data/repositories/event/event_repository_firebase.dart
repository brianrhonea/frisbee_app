import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../domain/models/recurrence.dart';
import '../../../domain/models/team_event.dart';
import '../../../utils/result.dart';
import '../../services/api_client.dart';
import '../../services/firestore_utils.dart';
import '../../services/shared_streams.dart';
import '../../services/time_zone.dart';
import 'event_repository.dart';
import '../../../domain/models/word_filter.dart';

class EventRepositoryFirebase implements EventRepository {
  EventRepositoryFirebase({
    FirebaseFirestore? firestore,
    SharedStreams? sharedStreams,
    ApiClient? api,
    Future<String> Function() timeZone = localTimeZone,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _shared = sharedStreams ?? SharedStreams.instance,
       _api = api,
       _timeZone = timeZone;

  /// The Stall 10 API: every event write goes through it
  /// (`/v1/teams/:teamId/events`, `/v1/calendars/:id/events`); there's no
  /// direct fallback.
  final ApiClient? _api;

  /// The device's time zone, sent with a repeat and with "this and
  /// following" edits so the server keeps each event's wall-clock time
  /// across clock changes.
  final Future<String> Function() _timeZone;

  static String _enc(String s) => Uri.encodeComponent(s);

  static String _scope(SeriesScope scope) =>
      scope == SeriesScope.following ? '?scope=following' : '';

  final FirebaseFirestore _db;

  /// One listener per query, shared by every screen (see [SharedStreams]).
  final SharedStreams _shared;

  /// [since] as a day, so callers asking within the same day share a query.
  static DateTime? _day(DateTime? since) =>
      since == null ? null : DateTime(since.year, since.month, since.day);

  static Query<Map<String, dynamic>> _from(
    Query<Map<String, dynamic>> col,
    DateTime? since,
  ) =>
      (since == null
              ? col
              : col.where(
                  'startsAt',
                  isGreaterThanOrEqualTo: Timestamp.fromDate(since),
                ))
          .orderBy('startsAt');

  CollectionReference<Map<String, dynamic>> _events(String teamId) =>
      _db.collection('teams').doc(teamId).collection('events');

  /// Public copies of events marked [TeamEvent.isPublic], keyed like
  /// events, so people outside the team never read responses.
  CollectionReference<Map<String, dynamic>> _publicEvents(String teamId) =>
      _db.collection('teams').doc(teamId).collection('publicEvents');

  CollectionReference<Map<String, dynamic>> _myEvents(String uid) =>
      _db.collection('users').doc(uid).collection('events');

  static List<TeamEvent> _parse(QuerySnapshot<Map<String, dynamic>> snap) =>
      snap.docs
          .map((d) => TeamEvent.fromMap(d.id, plainData(d.data())))
          .toList();

  static TeamEvent? _parseOne(DocumentSnapshot<Map<String, dynamic>> d) =>
      d.exists ? TeamEvent.fromMap(d.id, plainData(d.data())) : null;

  @override
  Stream<List<TeamEvent>> watchEvents(
    String teamId, {
    DateTime? since,
    Set<String>? audience,
  }) {
    final day = _day(since);
    final when = day?.toIso8601String() ?? 'all';
    if (audience == null) {
      return _shared.get(
        'events/$teamId/$when',
        () =>
            countedSnapshots(_from(_events(teamId), day), 'events').map(_parse),
      );
    }
    final ids = audience.toList()..sort();
    return _shared.get(
      'events/$teamId/$when/${ids.join(',')}',
      () => mergeLatest<TeamEvent>(
        [
          for (final id in ids)
            countedSnapshots(
              _from(_events(teamId).where('audience', arrayContains: id), day),
              'events',
            ).map(_parse),
        ],
        key: (e) => e.id,
      ).map((l) => l..sort((a, b) => a.startsAt.compareTo(b.startsAt))),
    );
  }

  @override
  Stream<TeamEvent?> watchEvent(String teamId, String eventId) =>
      _events(teamId).doc(eventId).snapshots().map(_parseOne);

  @override
  Stream<List<TeamEvent>> watchPublicEvents(String teamId, {DateTime? since}) {
    final day = _day(since);
    return _shared.get(
      'publicEvents/$teamId/${day?.toIso8601String() ?? 'all'}',
      () => countedSnapshots(
        _from(_publicEvents(teamId), day),
        'publicEvents',
      ).map(_parse).map(_markPublic),
    );
  }

  static List<TeamEvent> _markPublic(List<TeamEvent> events) => [
    for (final e in events) e.copyWith(isPublic: true),
  ];

  /// A team event as the API takes it (`saveTeamEventRequestSchema`).
  static Map<String, Object?> _teamBody(TeamEvent e) => {
    'title': cleanText(e.title),
    'type': e.type.name,
    'startsAt': e.startsAt.toUtc().toIso8601String(),
    'endsAt': e.endsAt?.toUtc().toIso8601String(),
    'location': cleanText(e.location),
    'notes': cleanText(e.notes),
    'poll': e.poll?.toMap(),
    'public': e.isPublic,
    if (e.audience.isNotEmpty) 'audience': e.audience.toList()..sort(),
  };

  /// New: `POST /v1/teams/:teamId/events` with an id the client picked (a
  /// series' events are `{id}_{index}`; a replay is a 409). Edit: `PATCH`,
  /// with `?scope=following` for this and the later events. The server
  /// works out the series from `repeat` and `timeZone`, writes the public
  /// copies, and starts the votes over when the poll changed.
  @override
  Future<Result<String>> saveEvent(
    String teamId,
    TeamEvent event,
    String uid, {
    bool clearVotes = false,
    Repeat? repeat,
    SeriesScope scope = SeriesScope.one,
  }) => guard(() async {
    final api = _api.required;
    final base = '/v1/teams/${_enc(teamId)}/events';
    final zoned = repeat != null || scope == SeriesScope.following;
    if (event.isNew) {
      if (repeat != null) {
        final problem = repeatProblem(event.startsAt, repeat);
        if (problem != null) throw ApiException('invalid_argument', problem);
      }
      final id = _events(teamId).doc().id;
      final r = await api.post(base, {
        ..._teamBody(event),
        'id': id,
        'repeat': ?repeat?.toJson(),
        if (zoned) 'timeZone': await _timeZone(),
      });
      return r['id'] as String? ?? id;
    }
    await api.patch('$base/${_enc(event.id)}${_scope(scope)}', {
      ..._teamBody(event),
      if (zoned) 'timeZone': await _timeZone(),
    });
    return event.id;
  });

  @override
  Future<Result<void>> deleteEvent(
    String teamId,
    String eventId, {
    SeriesScope scope = SeriesScope.one,
  }) => guard(
    () => _api.required.delete(
      '/v1/teams/${_enc(teamId)}/events/${_enc(eventId)}${_scope(scope)}',
    ),
  );

  String _eventPath(String teamId, String eventId) =>
      '/v1/teams/${_enc(teamId)}/events/${_enc(eventId)}';

  /// `PUT .../rsvp`: the answer (null takes it back, and its note).
  @override
  Future<Result<void>> setRsvp(
    String teamId,
    String eventId,
    String uid,
    RsvpStatus? status,
  ) => guard(
    () => _api.required.put('${_eventPath(teamId, eventId)}/rsvp', {
      'status': status?.name,
    }),
  );

  /// `PUT .../rsvp` again with the answer already given, and the note
  /// (empty removes it).
  @override
  Future<Result<void>> setRsvpNote(
    String teamId,
    String eventId,
    String uid,
    String note,
  ) => guard(() async {
    final api = _api.required;
    final current = (await _events(teamId).doc(eventId).get()).data();
    final status = ((current?['rsvps'] as Map?) ?? const {})[uid];
    if (status is! String) {
      throw const ApiException(
        'failed_precondition',
        'Answer first, then add a note.',
      );
    }
    await api.put('${_eventPath(teamId, eventId)}/rsvp', {
      'status': status,
      'note': note.isEmpty ? null : cleanText(note),
    });
  });

  @override
  Future<Result<void>> setReaction(
    String teamId,
    String eventId,
    String uid,
    Reaction reaction, {
    required bool on,
  }) => guard(
    () => _api.required.put('${_eventPath(teamId, eventId)}/reaction', {
      'reaction': reaction.name,
      'on': on,
    }),
  );

  @override
  Future<Result<void>> setVotes(
    String teamId,
    String eventId,
    String uid,
    List<String> optionIds,
  ) => guard(
    () => _api.required.put('${_eventPath(teamId, eventId)}/votes', {
      'optionIds': optionIds,
    }),
  );

  @override
  Stream<List<TeamEvent>> watchMyEvents(String uid, {DateTime? since}) {
    final day = _day(since);
    return _shared.get(
      'myEvents/$uid/${day?.toIso8601String() ?? 'all'}',
      () =>
          countedSnapshots(_from(_myEvents(uid), day), 'myEvents').map(_parse),
    );
  }

  @override
  Stream<TeamEvent?> watchMyEvent(String uid, String eventId) =>
      _myEvents(uid).doc(eventId).snapshots().map(_parseOne);

  /// Personal events are "My calendar" (the caller's uid) in
  /// `/v1/calendars/:id/events`.
  static Map<String, Object?> _myBody(TeamEvent e) => {
    'title': e.title,
    'type': e.type.name,
    'startsAt': e.startsAt.toUtc().toIso8601String(),
    'endsAt': e.endsAt?.toUtc().toIso8601String(),
    'location': e.location,
    'notes': e.notes,
  };

  @override
  Future<Result<String>> saveMyEvent(
    String uid,
    TeamEvent event, {
    Repeat? repeat,
    SeriesScope scope = SeriesScope.one,
  }) => guard(() async {
    final api = _api.required;
    final base = '/v1/calendars/${_enc(uid)}/events';
    final zoned = repeat != null || scope == SeriesScope.following;
    final body = {
      ..._myBody(event),
      if (event.isNew && repeat != null) 'repeat': repeat.toJson(),
      if (zoned) 'timeZone': await _timeZone(),
    };
    if (event.isNew) {
      final r = await api.post(base, body);
      return r['id'] as String? ?? '';
    }
    await api.patch('$base/${_enc(event.id)}${_scope(scope)}', body);
    return event.id;
  });

  @override
  Future<Result<void>> deleteMyEvent(
    String uid,
    String eventId, {
    SeriesScope scope = SeriesScope.one,
  }) => guard(
    () => _api.required.delete(
      '/v1/calendars/${_enc(uid)}/events/${_enc(eventId)}${_scope(scope)}',
    ),
  );
}
