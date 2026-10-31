import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../domain/models/team_event.dart';
import '../../../utils/result.dart';
import '../../services/firestore_utils.dart';
import 'event_repository.dart';

class EventRepositoryFirebase implements EventRepository {
  EventRepositoryFirebase({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _events(String teamId) =>
      _db.collection('teams').doc(teamId).collection('events');

  @override
  Stream<List<TeamEvent>> watchEvents(String teamId) => _events(teamId)
      .orderBy('startsAt')
      .snapshots()
      .map(
        (snap) => snap.docs
            .map((d) => TeamEvent.fromMap(d.id, plainData(d.data())))
            .toList(),
      );

  @override
  Stream<TeamEvent?> watchEvent(String teamId, String eventId) =>
      _events(teamId)
          .doc(eventId)
          .snapshots()
          .map(
            (d) =>
                d.exists ? TeamEvent.fromMap(d.id, plainData(d.data())) : null,
          );

  @override
  Future<Result<String>> saveEvent(
    String teamId,
    TeamEvent event,
    String uid, {
    bool clearVotes = false,
  }) => guard(() async {
    final col = _events(teamId);
    if (event.isNew) {
      final ref = col.doc();
      await ref.set({
        ...event.toEditableMap(),
        'rsvps': <String, Object>{},
        'reactions': <String, Object>{},
        'votes': <String, Object>{},
        'createdBy': uid,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return ref.id;
    }
    await col.doc(event.id).update({
      ...event.toEditableMap(),
      if (clearVotes) 'votes': <String, Object>{},
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return event.id;
  });

  @override
  Future<Result<void>> deleteEvent(String teamId, String eventId) =>
      guard(() => _events(teamId).doc(eventId).delete());

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
      if (status != RsvpStatus.going) ...{
        FieldPath(['reactions', uid]): FieldValue.delete(),
        FieldPath(['votes', uid]): FieldValue.delete(),
      },
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
}
