import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../domain/models/app_user.dart';
import '../../../domain/models/chat.dart';
import '../../../domain/models/team.dart';
import '../../../utils/result.dart';
import '../../services/attachment_storage.dart';
import '../../services/firestore_utils.dart';
import 'chat_repository.dart';

/// Rooms live at `teams/{teamId}/chats/{roomId}` with messages beneath.
/// Attachments live in Cloud Storage at
/// `teams/{teamId}/chats/{roomId}/{uid}/{messageId}/{fileName}`; storage.rules
/// checks the room's access in Firestore before serving them.
class ChatRepositoryFirebase implements ChatRepository {
  ChatRepositoryFirebase({
    required AttachmentStorage attachments,
    FirebaseFirestore? firestore,
  }) : _files = attachments,
       _db = firestore ?? FirebaseFirestore.instance;

  final AttachmentStorage _files;
  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _rooms(String teamId) =>
      chatRooms(_db, teamId);

  CollectionReference<Map<String, dynamic>> _messages(
    String teamId,
    String roomId,
  ) => _rooms(teamId).doc(roomId).collection('messages');

  @override
  Stream<List<ChatRoom>> watchRooms(Team team, String uid) {
    final role = team.roleOf(uid);
    if (role == null) return Stream.value(const []);
    List<ChatRoom> parse(QuerySnapshot<Map<String, dynamic>> snap) => [
      for (final d in snap.docs) ChatRoom.fromMap(d.id, plainData(d.data())),
    ];
    if (role.canEdit) {
      return _rooms(team.id).snapshots().map((s) => _sorted(parse(s)));
    }
    // Rules only allow queries that are limited to rooms the member can
    // read, so ask by role and by uid and merge the two.
    return _merge(
      _rooms(
        team.id,
      ).where('readRoles', arrayContains: role.name).snapshots().map(parse),
      _rooms(
        team.id,
      ).where('readUsers', arrayContains: uid).snapshots().map(parse),
    );
  }

  Stream<List<ChatRoom>> _merge(
    Stream<List<ChatRoom>> a,
    Stream<List<ChatRoom>> b,
  ) {
    List<ChatRoom>? lastA, lastB;
    late StreamController<List<ChatRoom>> controller;
    final subs = <StreamSubscription<List<ChatRoom>>>[];
    void emit() {
      if (lastA == null || lastB == null) return;
      controller.add(
        _sorted(
          {
            for (final r in [...lastA!, ...lastB!]) r.id: r,
          }.values,
        ),
      );
    }

    controller = StreamController(
      onListen: () {
        subs
          ..add(
            a.listen((r) {
              lastA = r;
              emit();
            }, onError: controller.addError),
          )
          ..add(
            b.listen((r) {
              lastB = r;
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

  static List<ChatRoom> _sorted(Iterable<ChatRoom> rooms) =>
      rooms.toList()..sort((a, b) {
        if (a.isGeneral != b.isGeneral) return a.isGeneral ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

  @override
  Stream<ChatRoom?> watchRoom(String teamId, String roomId) => _rooms(teamId)
      .doc(roomId)
      .snapshots()
      .map(
        (d) => d.exists ? ChatRoom.fromMap(d.id, plainData(d.data())) : null,
      );

  @override
  Future<Result<String>> saveRoom(String teamId, ChatRoom room, String uid) =>
      guard(() async {
        if (room.isNew) {
          final ref = _rooms(teamId).doc();
          await ref.set(newRoomData(room, uid));
          return ref.id;
        }
        await _rooms(teamId).doc(room.id).update(room.toMap());
        return room.id;
      });

  @override
  Future<Result<void>> deleteRoom(String teamId, String roomId) =>
      guard(() => deleteChatRoom(_db, _files, _rooms(teamId).doc(roomId)));

  @override
  Future<Result<void>> ensureGeneralRoom(String teamId, String uid) =>
      guard(() async {
        final ref = _rooms(teamId).doc(ChatRoom.generalId);
        await _db.runTransaction((tx) async {
          if ((await tx.get(ref)).exists) return;
          tx.set(ref, newRoomData(ChatRoom.general(), uid));
        });
      });

  @override
  Stream<List<ChatMessage>> watchMessages(
    String teamId,
    String roomId, {
    required int limit,
  }) => _messages(teamId, roomId)
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map(
        (snap) => [
          for (final d in snap.docs.reversed)
            // createdAt is null until the server stamps a pending message.
            ChatMessage.fromMap(d.id, plainData(d.data())),
        ],
      );

  @override
  Future<Result<void>> sendMessage(
    String teamId,
    String roomId, {
    required AppUser author,
    required String text,
    List<NewAttachment> attachments = const [],
  }) => guard(() async {
    for (final a in attachments) {
      if (a.tooLarge) throw AttachmentTooLargeException(a.name);
    }
    final ref = _messages(teamId, roomId).doc();
    final uploaded = await _files.upload(
      'teams/$teamId/chats/$roomId/${author.uid}/${ref.id}',
      attachments,
    );
    try {
      await ref.set({
        'authorId': author.uid,
        'authorName': author.label,
        'text': text.trim(),
        'attachments': [for (final a in uploaded) a.toMap()],
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Don't leave files behind for a message that was never posted.
      await _files.delete(uploaded.map((a) => a.path));
      rethrow;
    }
  });

  @override
  Future<Result<void>> deleteMessage(
    String teamId,
    String roomId,
    ChatMessage message,
  ) => guard(() async {
    await _files.delete(message.attachments.map((a) => a.path));
    await _messages(teamId, roomId).doc(message.id).delete();
  });

  @override
  Future<Result<Uint8List>> downloadAttachment(ChatAttachment attachment) =>
      guard(() => _files.download(attachment));
}

CollectionReference<Map<String, dynamic>> chatRooms(
  FirebaseFirestore db,
  String teamId,
) => db.collection('teams').doc(teamId).collection('chats');

/// Fields for a room being created by [uid].
Map<String, dynamic> newRoomData(ChatRoom room, String uid) => {
  ...room.toMap(),
  'createdBy': uid,
  'createdAt': FieldValue.serverTimestamp(),
};

/// Deletes a room's attachments, then its messages, then the room.
/// Storage rules read the room, so it goes last.
Future<void> deleteChatRoom(
  FirebaseFirestore db,
  AttachmentStorage files,
  DocumentReference<Map<String, dynamic>> room,
) async {
  final messages = await room.collection('messages').get();
  await files.delete([
    for (final d in messages.docs) ...attachmentPaths(d.data()),
  ]);
  await deleteDocs(db, messages.docs.map((d) => d.reference));
  await room.delete();
}
