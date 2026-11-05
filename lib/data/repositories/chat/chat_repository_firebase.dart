import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../domain/models/app_user.dart';
import '../../../domain/models/chat.dart';
import '../../../domain/models/team.dart';
import '../../../utils/result.dart';
import '../../services/attachment_storage.dart';
import '../../services/firestore_utils.dart';
import '../../services/shared_streams.dart';
import 'chat_repository.dart';

/// Rooms live at `teams/{teamId}/chats/{roomId}` with messages beneath, and
/// folders at `teams/{teamId}/chatFolders/{folderId}`.
/// Attachments live in Cloud Storage at
/// `teams/{teamId}/chats/{roomId}/{uid}/{messageId}/{fileName}`; storage.rules
/// checks the room's access in Firestore before serving them.
class ChatRepositoryFirebase implements ChatRepository {
  ChatRepositoryFirebase({
    required AttachmentStorage attachments,
    FirebaseFirestore? firestore,
    SharedStreams? sharedStreams,
  }) : _files = attachments,
       _db = firestore ?? FirebaseFirestore.instance,
       _shared = sharedStreams ?? SharedStreams.instance;

  final AttachmentStorage _files;
  final FirebaseFirestore _db;

  /// One listener per query, shared by every screen (see [SharedStreams]).
  final SharedStreams _shared;

  CollectionReference<Map<String, dynamic>> _rooms(String teamId) =>
      chatRooms(_db, teamId);

  CollectionReference<Map<String, dynamic>> _folders(String teamId) =>
      chatFolders(_db, teamId);

  CollectionReference<Map<String, dynamic>> _messages(
    String teamId,
    String roomId,
  ) => _rooms(teamId).doc(roomId).collection('messages');

  @override
  Stream<List<ChatRoom>> watchRooms(Team team, String uid) {
    if (team.roleOf(uid) == null) return Stream.value(const []);
    final manager = team.has(uid, TeamPermission.manageChats);
    final ids = manager ? const <String>[] : _audienceIds(team, uid);
    return _shared.get(
      'rooms/${team.id}/$uid/${manager ? '*' : ids.join(',')}',
      () => _openRooms(team.id, uid, manager ? null : ids),
    );
  }

  /// The audience ids to query rooms by: everyone, the member's tier and
  /// up to 10 custom roles, as many as firestore.rules checks.
  static List<String> _audienceIds(Team team, String uid) {
    final role = team.roleOf(uid)!;
    final custom = [
      for (final r in team.sortedRoles)
        if (team.memberRoles[uid]?.contains(r.id) ?? false) r.id,
    ].take(10);
    return [ChatAudience.everyone, role.name, ...custom];
  }

  /// Every room when [ids] is null; otherwise the rooms one of [ids] or
  /// [uid] can read.
  Stream<List<ChatRoom>> _openRooms(
    String teamId,
    String uid,
    List<String>? ids,
  ) {
    List<ChatRoom> parse(QuerySnapshot<Map<String, dynamic>> snap) => [
      for (final d in snap.docs) ChatRoom.fromMap(d.id, plainData(d.data())),
    ];
    if (ids == null) {
      return countedSnapshots(
        _rooms(teamId),
        'chatRooms',
      ).map((s) => sortRooms(parse(s)));
    }
    // Rules only allow queries that are limited to rooms the member can
    // read, so ask once per audience id and by uid, and merge them.
    return mergeLatest<ChatRoom>([
      for (final id in ids)
        countedSnapshots(
          _rooms(teamId).where('readRoles', arrayContains: id),
          'chatRooms',
        ).map(parse),
      countedSnapshots(
        _rooms(teamId).where('readUsers', arrayContains: uid),
        'chatRooms',
      ).map(parse),
    ], key: (r) => r.id).map(sortRooms);
  }

  @override
  Stream<List<ChatFolder>> watchFolders(String teamId) => _shared.get(
    'chatFolders/$teamId',
    () => countedSnapshots(_folders(teamId), 'chatFolders').map(
      (s) => sortFolders([
        for (final d in s.docs) ChatFolder.fromMap(d.id, plainData(d.data())),
      ]),
    ),
  );

  @override
  Future<Result<String>> saveFolder(
    String teamId,
    ChatFolder folder,
    String uid,
  ) => guard(() async {
    if (folder.isNew) {
      final ref = _folders(teamId).doc();
      await ref.set(newFolderData(folder, uid));
      return ref.id;
    }
    await _folders(teamId).doc(folder.id).update(folder.toMap());
    return folder.id;
  });

  @override
  Future<Result<void>> deleteFolder(
    String teamId,
    String folderId,
    List<ChatRoom> rooms,
  ) => guard(() async {
    final batch = _db.batch();
    for (final r in rooms) {
      if (r.folderId == folderId) {
        batch.update(_rooms(teamId).doc(r.id), {'folderId': null});
      }
    }
    batch.delete(_folders(teamId).doc(folderId));
    await batch.commit();
  });

  @override
  Future<Result<void>> arrange(
    String teamId, {
    List<ChatFolder> folders = const [],
    List<ChatRoom> rooms = const [],
  }) => guard(() async {
    final batch = _db.batch();
    for (final f in folders) {
      batch.update(_folders(teamId).doc(f.id), {'position': f.position});
    }
    for (final r in rooms) {
      batch.update(_rooms(teamId).doc(r.id), {
        'position': r.position,
        'folderId': r.folderId,
      });
    }
    await batch.commit();
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
  Future<Result<void>> ensureVoiceRooms(String teamId, String uid) =>
      guard(() async {
        final folder = _folders(teamId).doc(ChatRoom.voiceFolderId);
        final rooms = [
          for (final r in ChatRoom.defaultVoiceRooms())
            (r, _rooms(teamId).doc(r.id)),
        ];
        await _db.runTransaction((tx) async {
          if ((await tx.get(folder)).exists) return;
          for (final (_, ref) in rooms) {
            if ((await tx.get(ref)).exists) return;
          }
          tx.set(folder, newFolderData(ChatRoom.defaultVoiceFolder(), uid));
          for (final (room, ref) in rooms) {
            tx.set(ref, newRoomData(room, uid));
          }
        });
      });

  @override
  Stream<List<ChatMessage>> watchMessages(
    String teamId,
    String roomId, {
    required int limit,
  }) => _shared.get(
    'messages/$teamId/$roomId/$limit',
    () =>
        countedSnapshots(
          _messages(
            teamId,
            roomId,
          ).orderBy('createdAt', descending: true).limit(limit),
          'chatMessages',
        ).map(
          (snap) => [
            for (final d in snap.docs.reversed)
              // createdAt is null until the server stamps a pending message.
              ChatMessage.fromMap(d.id, plainData(d.data())),
          ],
        ),
  );

  @override
  Future<Result<void>> sendMessage(
    String teamId,
    String roomId, {
    required AppUser author,
    required String text,
    List<NewAttachment> attachments = const [],
  }) => guard(
    () => muteAware(_db, author.uid, () async {
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
    }),
  );

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

CollectionReference<Map<String, dynamic>> chatFolders(
  FirebaseFirestore db,
  String teamId,
) => db.collection('teams').doc(teamId).collection('chatFolders');

/// Fields for a room being created by [uid].
Map<String, dynamic> newRoomData(ChatRoom room, String uid) => {
  ...room.toMap(),
  'kind': room.kind.name,
  'createdBy': uid,
  'createdAt': FieldValue.serverTimestamp(),
};

/// Fields for a folder being created by [uid].
Map<String, dynamic> newFolderData(ChatFolder folder, String uid) => {
  ...folder.toMap(),
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
