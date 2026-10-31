import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../domain/models/app_user.dart';
import '../../../domain/models/chat.dart';
import '../../../domain/models/meeting.dart';
import '../../../domain/models/meeting_playback.dart';
import '../../../domain/models/team.dart';
import '../../../utils/result.dart';
import '../../services/firestore_utils.dart';
import '../../services/meeting_token_service.dart';
import 'meeting_repository.dart';

/// Meetings live at `teams/{teamId}/meetings/{meetingId}`, with `messages`
/// (the chat) and `requests/{uid}` (join requests) beneath.
class MeetingRepositoryFirebase implements MeetingRepository {
  MeetingRepositoryFirebase({
    required MeetingTokenService tokens,
    FirebaseFirestore? firestore,
  }) : _tokens = tokens,
       _db = firestore ?? FirebaseFirestore.instance;

  final MeetingTokenService _tokens;
  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _meetings(String teamId) =>
      _db.collection('teams').doc(teamId).collection('meetings');

  CollectionReference<Map<String, dynamic>> _requests(
    String teamId,
    String meetingId,
  ) => _meetings(teamId).doc(meetingId).collection('requests');

  CollectionReference<Map<String, dynamic>> _messages(
    String teamId,
    String meetingId,
  ) => _meetings(teamId).doc(meetingId).collection('messages');

  static List<TeamMeeting> _parse(QuerySnapshot<Map<String, dynamic>> snap) => [
    for (final d in snap.docs) TeamMeeting.fromMap(d.id, plainData(d.data())),
  ];

  static List<TeamMeeting> _sorted(Iterable<TeamMeeting> meetings) =>
      meetings.toList()..sort((a, b) => a.startsAt.compareTo(b.startsAt));

  @override
  Stream<List<TeamMeeting>> watchMeetings(Team team, String uid) {
    final role = team.roleOf(uid);
    if (role == null) return Stream.value(const []);
    if (role.canEdit) {
      return _meetings(team.id).snapshots().map((s) => _sorted(_parse(s)));
    }
    // Rules only allow queries limited to meetings the member can see, so
    // ask by role and by uid and merge the two. Sorted here rather than in
    // the query, which would need a composite index per filter.
    return _merge(
      _meetings(
        team.id,
      ).where('inviteRoles', arrayContains: role.name).snapshots().map(_parse),
      _meetings(
        team.id,
      ).where('inviteUsers', arrayContains: uid).snapshots().map(_parse),
    );
  }

  Stream<List<TeamMeeting>> _merge(
    Stream<List<TeamMeeting>> a,
    Stream<List<TeamMeeting>> b,
  ) {
    List<TeamMeeting>? lastA, lastB;
    late StreamController<List<TeamMeeting>> controller;
    final subs = <StreamSubscription<List<TeamMeeting>>>[];
    void emit() {
      if (lastA == null || lastB == null) return;
      controller.add(
        _sorted(
          {
            for (final m in [...lastA!, ...lastB!]) m.id: m,
          }.values,
        ),
      );
    }

    controller = StreamController(
      onListen: () {
        subs
          ..add(
            a.listen((m) {
              lastA = m;
              emit();
            }, onError: controller.addError),
          )
          ..add(
            b.listen((m) {
              lastB = m;
              emit();
            }, onError: controller.addError),
          );
      },
      onCancel: () async {
        for (final s in subs) {
          await s.cancel();
        }
      },
    );
    return controller.stream;
  }

  @override
  Stream<TeamMeeting?> watchMeeting(String teamId, String meetingId) =>
      _meetings(teamId)
          .doc(meetingId)
          .snapshots()
          .map(
            (d) => d.exists
                ? TeamMeeting.fromMap(d.id, plainData(d.data()))
                : null,
          );

  @override
  Future<Result<String>> saveMeeting(
    String teamId,
    TeamMeeting meeting,
    String uid,
  ) => guard(() async {
    if (meeting.isNew) {
      final ref = _meetings(teamId).doc();
      await ref.set({
        ...meeting.toEditableMap(),
        'status': MeetingStatus.scheduled.name,
        'rsvps': <String, Object>{},
        'createdBy': uid,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return ref.id;
    }
    await _meetings(teamId).doc(meeting.id).update({
      ...meeting.toEditableMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return meeting.id;
  });

  @override
  Future<Result<void>> deleteMeeting(String teamId, String meetingId) =>
      guard(() async {
        final messages = await _messages(teamId, meetingId).get();
        final requests = await _requests(teamId, meetingId).get();
        await deleteDocs(_db, [
          for (final d in messages.docs) d.reference,
          for (final d in requests.docs) d.reference,
          _playback(teamId, meetingId),
        ]);
        await _meetings(teamId).doc(meetingId).delete();
      });

  @override
  Future<Result<void>> setRsvp(
    String teamId,
    String meetingId,
    String uid,
    MeetingRsvp? answer,
  ) => guard(
    () => _meetings(teamId).doc(meetingId).update({
      FieldPath(['rsvps', uid]): answer?.name ?? FieldValue.delete(),
    }),
  );

  @override
  Future<Result<void>> startMeeting(
    String teamId,
    String meetingId,
    String uid,
  ) => guard(
    () => _meetings(teamId).doc(meetingId).update({
      'status': MeetingStatus.live.name,
      'startedAt': FieldValue.serverTimestamp(),
      'startedBy': uid,
    }),
  );

  @override
  Future<Result<void>> endMeeting(String teamId, String meetingId) =>
      guard(() async {
        await _meetings(teamId).doc(meetingId).update({
          'status': MeetingStatus.ended.name,
          'endedAt': FieldValue.serverTimestamp(),
        });
        // Nobody can watch an ended meeting; tidy up, but it's not fatal.
        await _playback(teamId, meetingId).delete().catchError((_) {});
      });

  DocumentReference<Map<String, dynamic>> _playback(
    String teamId,
    String meetingId,
  ) => _meetings(teamId).doc(meetingId).collection('playback').doc('current');

  @override
  Stream<MeetingPlayback?> watchPlayback(String teamId, String meetingId) =>
      _playback(teamId, meetingId).snapshots().map(
        (d) => d.exists ? MeetingPlayback.fromMap(plainData(d.data())) : null,
      );

  @override
  Future<Result<void>> setPlayback(
    String teamId,
    String meetingId,
    MeetingPlayback playback,
  ) => guard(
    () => _playback(
      teamId,
      meetingId,
    ).set({...playback.toMap(), 'updatedAt': FieldValue.serverTimestamp()}),
  );

  @override
  Future<Result<void>> stopPlayback(String teamId, String meetingId) =>
      guard(() => _playback(teamId, meetingId).delete());

  @override
  Stream<List<JoinRequest>> watchJoinRequests(
    String teamId,
    String meetingId,
  ) => _requests(teamId, meetingId).snapshots().map(
    (snap) =>
        [
          for (final d in snap.docs)
            JoinRequest.fromMap(d.id, plainData(d.data())),
        ]..sort(
          (a, b) => (a.requestedAt ?? DateTime(9999)).compareTo(
            b.requestedAt ?? DateTime(9999),
          ),
        ),
  );

  @override
  Stream<JoinRequest?> watchMyJoinRequest(
    String teamId,
    String meetingId,
    String uid,
  ) => _requests(teamId, meetingId)
      .doc(uid)
      .snapshots()
      .map(
        (d) => d.exists ? JoinRequest.fromMap(d.id, plainData(d.data())) : null,
      );

  @override
  Future<Result<void>> requestToJoin(
    String teamId,
    String meetingId,
    AppUser user,
  ) => guard(
    () => _requests(teamId, meetingId).doc(user.uid).set({
      'name': user.label,
      'status': JoinRequestStatus.pending.name,
      'requestedAt': FieldValue.serverTimestamp(),
    }),
  );

  @override
  Future<Result<void>> cancelJoinRequest(
    String teamId,
    String meetingId,
    String uid,
  ) => guard(() => _requests(teamId, meetingId).doc(uid).delete());

  @override
  Future<Result<void>> decideJoinRequest(
    String teamId,
    String meetingId,
    String uid, {
    required bool admit,
    required String adminUid,
  }) => guard(
    () => _requests(teamId, meetingId).doc(uid).update({
      'status':
          (admit ? JoinRequestStatus.admitted : JoinRequestStatus.denied).name,
      'decidedBy': adminUid,
      'decidedAt': FieldValue.serverTimestamp(),
    }),
  );

  @override
  Stream<List<ChatMessage>> watchMessages(
    String teamId,
    String meetingId, {
    required int limit,
  }) => _messages(teamId, meetingId)
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map(
        (snap) => [
          for (final d in snap.docs.reversed)
            ChatMessage.fromMap(d.id, plainData(d.data())),
        ],
      );

  @override
  Future<Result<void>> sendMessage(
    String teamId,
    String meetingId, {
    required AppUser author,
    required String text,
  }) => guard(
    () => _messages(teamId, meetingId).add({
      'authorId': author.uid,
      'authorName': author.label,
      'text': text.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    }),
  );

  @override
  Future<Result<void>> deleteMessage(
    String teamId,
    String meetingId,
    String messageId,
  ) => guard(() => _messages(teamId, meetingId).doc(messageId).delete());

  @override
  Future<Result<MeetingAccess>> joinToken(String teamId, String meetingId) =>
      guard(() => _tokens.joinToken(teamId, meetingId));
}
