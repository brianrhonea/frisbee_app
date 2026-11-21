import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../domain/models/app_user.dart';
import '../../../domain/models/chat.dart';
import '../../../domain/models/model_utils.dart';
import '../../../domain/models/outbox.dart';
import '../../../domain/models/team.dart';
import '../../../utils/result.dart';
import '../../services/api_client.dart';
import '../../services/attachment_storage.dart';
import '../../services/firestore_utils.dart';
import '../../services/shared_streams.dart';
import '../outbox/outbox_repository.dart';
import 'chat_repository.dart';
import '../../../domain/models/word_filter.dart';

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
    OutboxRepository? outbox,
    ApiClient? api,
  }) : _api = api,
       _files = attachments,
       _db = firestore ?? FirebaseFirestore.instance,
       _shared = sharedStreams ?? SharedStreams.instance,
       _outbox = outbox {
    outbox?.register(
      OutboxKind.teamChat,
      OutboxHandler(
        send: (job, files, author) => _send(
          job.payload['teamId'] as String? ?? '',
          job.payload['roomId'] as String? ?? '',
          job.id,
          author: author,
          text: job.payload['text'] as String? ?? '',
          attachments: files,
          replyTo: MessageReply.fromMap(job.payload['replyTo']),
        ),
        sent: (job) => existsOnServer(
          _messages(
            job.payload['teamId'] as String? ?? '',
            job.payload['roomId'] as String? ?? '',
          ).doc(job.id),
        ),
      ),
    );
  }

  /// Holds messages sent offline until they can go out.
  final OutboxRepository? _outbox;

  /// Pins and event cards; null in builds without `API_BASE_URL`.
  final ApiClient? _api;

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

  /// users/{uid}/chatReads/{teamId}: rooms.{roomId} → when [uid] last
  /// read it.
  CollectionReference<Map<String, dynamic>> _reads(String uid) =>
      _db.collection('users').doc(uid).collection('chatReads');

  @override
  Stream<Map<String, Map<String, DateTime>>> watchReads(
    String uid,
  ) => _shared.get(
    'chatReads/$uid',
    () => _reads(uid).snapshots().map(
      (snap) => {
        for (final d in snap.docs)
          d.id: {
            for (final e
                in ((plainData(d.data())['rooms'] as Map?) ?? const {}).entries)
              '${e.key}': ?parseDate(e.value),
          },
      },
    ),
  );

  @override
  Future<Result<void>> markRead(String teamId, String roomId, String uid) =>
      guard(
        () => _reads(uid).doc(teamId).set({
          'rooms': {roomId: FieldValue.serverTimestamp()},
        }, SetOptions(merge: true)),
      );

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
    folder = folder.copyWith(name: cleanText(folder.name));
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
        room = room.withName(cleanText(room.name));
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
  Future<Result<List<ChatMessage>>> fetchOlderMessages(
    String teamId,
    String roomId, {
    required ChatMessage before,
    required int limit,
  }) => guard(() async {
    final docs = await pageAfter(
      _messages(teamId, roomId),
      field: 'createdAt',
      afterValue: before.createdAt,
      afterId: before.id,
      limit: limit,
      label: 'chatMessages',
    );
    return [
      for (final d in docs.reversed)
        ChatMessage.fromMap(d.id, plainData(d.data())),
    ];
  });

  @override
  Future<Result<void>> sendMessage(
    String teamId,
    String roomId, {
    required AppUser author,
    required String text,
    List<NewAttachment> attachments = const [],
    MessageReply? replyTo,
  }) {
    if (refuseBlockedWords<void>([text]) case final r?) return r;
    text = maskSwearing(text);
    // The id is picked now and kept, so a retry can't post it twice.
    final messageId = _messages(teamId, roomId).doc().id;
    Future<Result<void>> now() => _send(
      teamId,
      roomId,
      messageId,
      author: author,
      text: text,
      attachments: attachments,
      replyTo: replyTo,
    );
    final outbox = _outbox;
    if (outbox == null || attachments.any((a) => a.tooLarge)) return now();
    return outbox.submit(
      kind: OutboxKind.teamChat,
      id: messageId,
      target: teamChatTarget(teamId, roomId),
      label: 'Team chat message',
      payload: {
        'teamId': teamId,
        'roomId': roomId,
        'text': text,
        'replyTo': replyTo?.toMap(),
      },
      files: attachments,
      sendNow: now,
    );
  }

  Future<Result<void>> _send(
    String teamId,
    String roomId,
    String messageId, {
    required AppUser author,
    required String text,
    List<NewAttachment> attachments = const [],
    MessageReply? replyTo,
  }) => guard(
    () => muteAware(_db, author.uid, () async {
      for (final a in attachments) {
        if (a.tooLarge) {
          throw AttachmentTooLargeException(
            a.name,
            limit: maxBytesFor(a.contentType),
          );
        }
      }
      final ref = _messages(teamId, roomId).doc(messageId);
      final uploaded = await _files.upload(
        'teams/$teamId/chats/$roomId/${author.uid}/${ref.id}',
        attachments,
      );
      try {
        // One batch: the message, the room's lastAt (a time, never the
        // text) for everyone's unread dots, and the author's own read.
        await (_db.batch()
              ..set(ref, {
                'authorId': author.uid,
                'authorName': author.label,
                'text': text.trim(),
                'attachments': [for (final a in uploaded) a.toMap()],
                'createdAt': FieldValue.serverTimestamp(),
                'replyTo': ?replyTo?.toMap(),
              })
              ..update(_rooms(teamId).doc(roomId), {
                'lastAt': FieldValue.serverTimestamp(),
              })
              ..set(_reads(author.uid).doc(teamId), {
                'rooms': {roomId: FieldValue.serverTimestamp()},
              }, SetOptions(merge: true)))
            .commit();
      } catch (_) {
        // Don't leave files behind for a message that was never posted.
        await _files.delete(uploaded.map((a) => a.path));
        rethrow;
      }
    }),
  );

  @override
  Future<Result<void>> setReaction(
    String teamId,
    String roomId,
    String messageId,
    String uid,
    String? emoji,
  ) => guard(
    () => _messages(
      teamId,
      roomId,
    ).doc(messageId).update({'reactions.$uid': emoji ?? FieldValue.delete()}),
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

  static const _noApi =
      "Pins, event cards and polls aren't available in this version of "
      'the app. Update the app, or use stall10.app.';

  ApiClient get _client =>
      _api ?? (throw const ApiException('unavailable', _noApi));

  static String _roomPath(String teamId, String roomId) =>
      '/v1/teams/${Uri.encodeComponent(teamId)}/chats/'
      '${Uri.encodeComponent(roomId)}';

  static String _pinPath(String teamId, String roomId, String messageId) =>
      '${_roomPath(teamId, roomId)}/messages/'
      '${Uri.encodeComponent(messageId)}/pin';

  @override
  bool get canUseChatExtras => _api != null;

  @override
  Stream<List<ChatMessage>> watchPins(String teamId, String roomId) =>
      _shared.get(
        'pins/$teamId/$roomId',
        () =>
            countedSnapshots(
              _messages(
                teamId,
                roomId,
              ).orderBy('pinnedAt', descending: true).limit(chatPinsMax),
              'chatPins',
            ).map(
              (snap) => [
                // Firestore leaves out messages without pinnedAt; checked
                // here too.
                for (final d in snap.docs)
                  if (ChatMessage.fromMap(d.id, plainData(d.data()))
                      case final m when m.isPinned)
                    m,
              ],
            ),
      );

  @override
  Future<Result<void>> pinMessage(
    String teamId,
    String roomId,
    String messageId, {
    String? unpin,
  }) => guard(
    () => _client.put(_pinPath(teamId, roomId, messageId), {'unpin': ?unpin}),
  );

  @override
  Future<Result<void>> unpinMessage(
    String teamId,
    String roomId,
    String messageId,
  ) => guard(() => _client.delete(_pinPath(teamId, roomId, messageId)));

  @override
  Future<Result<void>> shareEvent(
    String teamId,
    String roomId,
    String eventId,
  ) => guard(
    () => _client.post('${_roomPath(teamId, roomId)}/event-shares', {
      'eventId': eventId,
    }),
  );

  static String _messagePath(String teamId, String roomId, String id) =>
      '${_roomPath(teamId, roomId)}/messages/${Uri.encodeComponent(id)}';

  @override
  Future<Result<void>> createPoll(
    String teamId,
    String roomId,
    NewChatPoll poll,
  ) => guard(
    () => _client.post('${_roomPath(teamId, roomId)}/polls', {
      'question': poll.question,
      'options': poll.options,
      'multiple': poll.multiple,
      if (poll.closesAt case final at?)
        'closesAt': at.toUtc().toIso8601String(),
    }),
  );

  @override
  Future<Result<void>> votePoll(
    String teamId,
    String roomId,
    String messageId,
    List<int> options,
  ) => guard(
    () => _client.put('${_messagePath(teamId, roomId, messageId)}/vote', {
      'options': options,
    }),
  );

  @override
  Future<Result<void>> closePoll(
    String teamId,
    String roomId,
    String messageId,
  ) => guard(
    () => _client.post(
      '${_messagePath(teamId, roomId, messageId)}/close-poll',
      const {},
    ),
  );

  @override
  Stream<ChatMessage?> watchMessage(
    String teamId,
    String roomId,
    String messageId,
  ) => _shared.get(
    'message/$teamId/$roomId/$messageId',
    () =>
        countedDocSnapshots(
          _messages(teamId, roomId).doc(messageId),
          'chatPoll',
        ).map(
          (d) =>
              d.exists ? ChatMessage.fromMap(d.id, plainData(d.data())) : null,
        ),
  );

  @override
  Future<Result<Uint8List>> downloadAttachment(ChatAttachment attachment) =>
      guard(() => _files.download(attachment));

  @override
  Future<Result<String>> attachmentUrl(ChatAttachment attachment) =>
      guard(() => _files.url(attachment));
}

CollectionReference<Map<String, dynamic>> chatRooms(
  FirebaseFirestore db,
  String teamId,
) => db.collection('teams').doc(teamId).collection('chats');

CollectionReference<Map<String, dynamic>> chatFolders(
  FirebaseFirestore db,
  String teamId,
) => db.collection('teams').doc(teamId).collection('chatFolders');

/// Fields for a room being created by [uid]. [createdAt] defaults to the
/// server's time.
Map<String, dynamic> newRoomData(
  ChatRoom room,
  String uid, {
  Object? createdAt,
}) => {
  ...room.toMap(),
  'kind': room.kind.name,
  'createdBy': uid,
  'createdAt': createdAt ?? FieldValue.serverTimestamp(),
};

/// Fields for a folder being created by [uid]. [createdAt] defaults to the
/// server's time.
Map<String, dynamic> newFolderData(
  ChatFolder folder,
  String uid, {
  Object? createdAt,
}) => {
  ...folder.toMap(),
  'createdBy': uid,
  'createdAt': createdAt ?? FieldValue.serverTimestamp(),
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
