import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../domain/models/recurrence.dart';
import '../../../domain/models/team_event.dart';
import '../../../utils/result.dart';
import '../../services/firestore_utils.dart';
import '../../services/shared_streams.dart';
import 'event_repository.dart';
import '../../../domain/models/word_filter.dart';

class EventRepositoryFirebase implements EventRepository {
  EventRepositoryFirebase({
    FirebaseFirestore? firestore,
    SharedStreams? sharedStreams,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _shared = sharedStreams ?? SharedStreams.instance;

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

  @override
  Future<Result<String>> saveEvent(
    String teamId,
    TeamEvent event,
    String uid, {
    bool clearVotes = false,
    Repeat? repeat,
    SeriesScope scope = SeriesScope.one,
  }) => guard(() async {
    event = event.copyWith(
      title: cleanText(event.title),
      location: cleanText(event.location),
      notes: cleanText(event.notes),
    );
    final col = _events(teamId);
    final batch = _db.batch();
    void public(String id, TeamEvent e, {required bool isNew}) {
      final ref = _publicEvents(teamId).doc(id);
      if (e.isPublic) {
        batch.set(ref, {
          ...e.toPublicMap(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else if (!isNew) {
        // Deleting a missing doc is fine, so no need to check it was public.
        batch.delete(ref);
      }
    }

    if (event.isNew) {
      final events = _occurrences(col.doc().id, event, repeat);
      for (final e in events) {
        batch.set(col.doc(e.id), {
          ...e.toEditableMap(),
          if (e.series case final series?) 'series': series.toMap(),
          'public': e.isPublic,
          'rsvps': <String, Object>{},
          'reactions': <String, Object>{},
          'votes': <String, Object>{},
          'createdBy': uid,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        public(e.id, e, isNew: true);
      }
      await batch.commit();
      return events.first.id;
    }
    final later = scope == SeriesScope.following
        ? await _later(col, event.id, event)
        : const <TeamEvent>[];
    // One id per bulk write, so the change notice goes out once.
    final writeId = later.isEmpty ? null : col.doc().id;
    void update(TeamEvent e, {required bool lead}) {
      batch.update(col.doc(e.id), {
        ...e.toEditableMap(),
        'public': e.isPublic,
        if (clearVotes) 'votes': <String, Object>{},
        if (writeId != null) 'seriesWrite': {'id': writeId, 'lead': lead},
        'updatedAt': FieldValue.serverTimestamp(),
      });
      public(e.id, e, isNew: false);
    }

    update(event, lead: true);
    for (final e in later) {
      update(e, lead: false);
    }
    await batch.commit();
    return event.id;
  });

  /// [event] as one event, or with [repeat] as a series in [seriesId]:
  /// one per occurrence, ids `${seriesId}_${index}`.
  static List<TeamEvent> _occurrences(
    String seriesId,
    TeamEvent event,
    Repeat? repeat,
  ) {
    if (repeat == null) return [event.copyWith(id: seriesId)];
    final problem = repeatProblem(event.startsAt, repeat);
    if (problem != null) throw ArgumentError(problem);
    final times = seriesTimes(event.startsAt, event.endsAt, repeat);
    return [
      for (final (i, (start, end)) in times.indexed)
        event.copyWith(
          id: occurrenceId(seriesId, i),
          startsAt: start,
          endsAt: () => end,
          series: () => EventSeries(
            id: seriesId,
            index: i,
            count: times.length,
            freq: repeat.freq,
            until: repeat.until,
          ),
        ),
    ];
  }

  /// The events after [id] in its series, as [edited] (its new details)
  /// moved by the same change of date and time; ones already deleted are
  /// skipped. Empty when it isn't in a series.
  static Future<List<TeamEvent>> _later(
    CollectionReference<Map<String, dynamic>> col,
    String id,
    TeamEvent edited,
  ) async {
    final current = _parseOne(await col.doc(id).get());
    final series = current?.series;
    if (current == null || series == null) return const [];
    final move = moveLater(current.startsAt, edited.startsAt, edited.endsAt);
    final docs = await Future.wait(
      series.laterIds.map((l) => col.doc(l).get()),
    );
    return [
      for (final d in docs)
        if (_parseOne(d) case final stored?)
          () {
            final (start, end) = move(stored.startsAt);
            return edited.copyWith(
              id: stored.id,
              startsAt: start,
              endsAt: () => end,
            );
          }(),
    ];
  }

  /// The ids of [id] and, for [SeriesScope.following], its series' later
  /// events that still exist.
  static Future<List<String>> _withLater(
    CollectionReference<Map<String, dynamic>> col,
    String id,
    SeriesScope scope,
  ) async {
    if (scope == SeriesScope.one) return [id];
    final series = _parseOne(await col.doc(id).get())?.series;
    if (series == null) return [id];
    final docs = await Future.wait(
      series.laterIds.map((l) => col.doc(l).get()),
    );
    return [
      id,
      for (final d in docs)
        if (d.exists) d.id,
    ];
  }

  @override
  Future<Result<void>> deleteEvent(
    String teamId,
    String eventId, {
    SeriesScope scope = SeriesScope.one,
  }) => guard(() async {
    final col = _events(teamId);
    final ids = await _withLater(col, eventId, scope);
    if (ids.length > 1) {
      // Marked first, so the cancellation notice goes out once.
      final writeId = col.doc().id;
      final mark = _db.batch();
      for (final id in ids) {
        mark.update(col.doc(id), {
          'seriesWrite': {'id': writeId, 'lead': id == eventId, 'delete': true},
        });
      }
      await mark.commit();
    }
    final batch = _db.batch();
    for (final id in ids) {
      batch
        ..delete(col.doc(id))
        ..delete(_publicEvents(teamId).doc(id));
    }
    await batch.commit();
  });

  // Responses use field-path updates so concurrent members never clobber
  // each other's entries.

  @override
  Future<Result<void>> setRsvp(
    String teamId,
    String eventId,
    String uid,
    RsvpStatus? status,
  ) => guard(
    () => _events(teamId).doc(eventId).update({
      FieldPath(['rsvps', uid]): status?.name ?? FieldValue.delete(),
      // The note goes with the answer (firestore.rules validRsvpNote).
      if (status == null) FieldPath(['rsvpNotes', uid]): FieldValue.delete(),
      if (status != RsvpStatus.going) ...{
        FieldPath(['reactions', uid]): FieldValue.delete(),
        FieldPath(['votes', uid]): FieldValue.delete(),
      },
    }),
  );

  @override
  Future<Result<void>> setRsvpNote(
    String teamId,
    String eventId,
    String uid,
    String note,
  ) => guard(
    () => _events(teamId).doc(eventId).update({
      FieldPath(['rsvpNotes', uid]): note.isEmpty
          ? FieldValue.delete()
          : cleanText(note),
    }),
  );

  @override
  Future<Result<void>> setReaction(
    String teamId,
    String eventId,
    String uid,
    Reaction reaction, {
    required bool on,
  }) => guard(
    () => _events(teamId).doc(eventId).update({
      FieldPath(['reactions', uid]): on
          ? FieldValue.arrayUnion([reaction.name])
          : FieldValue.arrayRemove([reaction.name]),
    }),
  );

  @override
  Future<Result<void>> setVotes(
    String teamId,
    String eventId,
    String uid,
    List<String> optionIds,
  ) => guard(
    () => _events(teamId).doc(eventId).update({
      FieldPath(['votes', uid]): optionIds.isEmpty
          ? FieldValue.delete()
          : optionIds,
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

  @override
  Future<Result<String>> saveMyEvent(
    String uid,
    TeamEvent event, {
    Repeat? repeat,
    SeriesScope scope = SeriesScope.one,
  }) => guard(() async {
    final col = _myEvents(uid);
    Map<String, dynamic> data(TeamEvent e) => {
      ...e.toEditableMap(),
      'poll': null,
    };
    final batch = _db.batch();
    if (event.isNew) {
      final events = _occurrences(col.doc().id, event, repeat);
      for (final e in events) {
        batch.set(col.doc(e.id), {
          ...data(e),
          if (e.series case final series?) 'series': series.toMap(),
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
      return events.first.id;
    }
    final later = scope == SeriesScope.following
        ? await _later(col, event.id, event)
        : const <TeamEvent>[];
    for (final e in [event, ...later]) {
      batch.update(col.doc(e.id), {
        ...data(e),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    return event.id;
  });

  @override
  Future<Result<void>> deleteMyEvent(
    String uid,
    String eventId, {
    SeriesScope scope = SeriesScope.one,
  }) => guard(() async {
    final col = _myEvents(uid);
    final batch = _db.batch();
    for (final id in await _withLater(col, eventId, scope)) {
      batch.delete(col.doc(id));
    }
    await batch.commit();
  });
}
