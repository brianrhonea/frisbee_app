import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../domain/models/app_user.dart';
import '../../../domain/models/chat.dart';
import '../../../domain/models/direct_message.dart';
import '../../../domain/models/model_utils.dart';
import '../../../domain/models/outbox.dart';
import '../../../utils/result.dart';
import '../../services/api_search.dart';
import '../../services/attachment_storage.dart';
import '../../services/firestore_utils.dart';
import '../../services/api_client.dart';
import '../../services/shared_streams.dart';
import '../../services/upload_client.dart';
import '../outbox/outbox_payloads.dart';
import '../outbox/outbox_repository.dart';
import 'direct_message_repository.dart';
import '../../../domain/models/username.dart';
import '../../../domain/models/word_filter.dart';

/// The directory is `profiles/{uid}` (name and photo, written by
/// AuthRepositoryFirebase). Conversations are `conversations/{a_b}` with
/// messages beneath; attachments are in Cloud Storage at
/// `conversations/{id}/{uid}/{messageId}/{fileName}`. firestore.rules and
/// storage.rules limit both to the two participants. Each user's own read
/// times are private, in `users/{uid}/dmReads/{id}`; the conversation's
/// `readAt` is the read receipt the other person sees, and the setting
/// that turns it off is `readReceipts` on `users/{uid}`. Typing shows
/// through `conversations/{id}/typing/{uid}`, rewritten at most every few
/// seconds while someone types and deleted when they send or clear it.
class DirectMessageRepositoryFirebase implements DirectMessageRepository {
  DirectMessageRepositoryFirebase({
    required AttachmentStorage attachments,
    FirebaseFirestore? firestore,
    SharedStreams? sharedStreams,
    ApiSearch? search,
    OutboxRepository? outbox,
    ApiClient? api,
    UploadClient? uploads,
  }) : _files = attachments,
       _db = firestore ?? FirebaseFirestore.instance,
       _shared = sharedStreams ?? SharedStreams.instance,
       _search = search,
       _api = api,
       _uploads = uploads ?? UploadClient(api: api),
       _outbox = outbox {
    outbox?.register(
      OutboxKind.directMessage,
      OutboxHandler(
        send: (job, files, author) => _send(
          job.target,
          job.id,
          message: OutboxPayloads.message(job),
          attachments: files,
          ledger: outbox,
        ),
        sent: (job) => existsOnServer(_messages(job.target).doc(job.id)),
      ),
    );
  }

  /// The Stall 10 API: conversations and their messages are written through
  /// it (`/v1/conversations`); there's no direct fallback.
  final ApiClient? _api;

  final UploadClient _uploads;

  static String _enc(String s) => Uri.encodeComponent(s);

  static String _conv(String id) => '/v1/conversations/${_enc(id)}';

  /// Holds messages sent offline until they can go out.
  final OutboxRepository? _outbox;

  /// Searches through the rate-limited Cloud Function when it's turned on.
  final ApiSearch? _search;

  final AttachmentStorage _files;
  final FirebaseFirestore _db;

  /// One listener per query, shared by every screen (see [SharedStreams]).
  final SharedStreams _shared;

  static const _searchLimit = 20;

  /// Sorts groups without messages yet last.
  static final _never = DateTime.fromMillisecondsSinceEpoch(0);

  CollectionReference<Map<String, dynamic>> get _profiles =>
      _db.collection('profiles');

  CollectionReference<Map<String, dynamic>> get _conversations =>
      _db.collection('conversations');

  CollectionReference<Map<String, dynamic>> _reads(String uid) =>
      _db.collection('users').doc(uid).collection('dmReads');

  /// [uid]'s private records (read, archived, deleted), by conversation
  /// id.
  Stream<Map<String, ConversationPrivate>> _watchReads(String uid) =>
      _shared.get(
        'dmReads/$uid',
        () => countedSnapshots(_reads(uid), 'dmReads').map(
          (snap) => {
            for (final d in snap.docs)
              d.id: ConversationPrivate.fromMap(plainData(d.data())),
          },
        ),
      );

  CollectionReference<Map<String, dynamic>> _typing(String id) =>
      _conversations.doc(id).collection('typing');

  @override
  Stream<Map<String, DateTime?>> watchTyping(String id) =>
      _typing(id).snapshots().map(
        (snap) => {for (final d in snap.docs) d.id: parseDate(d.data()['at'])},
      );

  @override
  Future<void> setTyping(String id, String uid, {required bool typing}) async {
    try {
      final ref = _typing(id).doc(uid);
      if (typing) {
        await ref.set({'at': FieldValue.serverTimestamp()});
      } else {
        await ref.delete();
      }
    } on Exception {
      // Typing is a nicety: never bother the user about it.
    }
  }

  CollectionReference<Map<String, dynamic>> _messages(String id) =>
      _conversations.doc(id).collection('messages');

  @override
  Future<Result<List<UserProfile>>> searchPeople(
    String query, {
    required String excludeUid,
  }) => guard(() async {
    final words = searchWords(Username.normalize(query));
    if (words.isEmpty) return const [];
    // Match the longest word in Firestore, then the rest here.
    final key = (words.toList()..sort((a, b) => b.length - a.length)).first;
    final k = key.length > 20 ? key.substring(0, 20) : key;
    final List<SearchHit> hits;
    if (_search case final s? when s.enabled) {
      hits = await s.search(SearchKind.people, k);
    } else {
      // The rules refuse a profiles query that doesn't ask for adults only
      // (H1: a profile is listed once it carries the adult marker).
      final snap = await _profiles
          .where('adult', isEqualTo: true)
          .where('keywords', arrayContains: k)
          .limit(_searchLimit * 2)
          .get();
      hits = [for (final d in snap.docs) (id: d.id, data: plainData(d.data()))];
    }
    return [
        for (final h in hits)
          if (h.id != excludeUid) UserProfile.fromMap(h.id, h.data),
      ].where((p) => p.matches(query)).take(_searchLimit).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  });

  @override
  Stream<List<Conversation>> watchConversations(String uid) => combineLatest(
    _watchConversations(uid),
    _watchReads(uid),
    (conversations, reads) => [
      for (final c in conversations) c.withMine(reads[c.id]),
    ],
  );

  Stream<List<Conversation>> _watchConversations(String uid) => _shared.get(
    'conversations/$uid',
    () =>
        countedSnapshots(
          _conversations.where('participants', arrayContains: uid),
          'conversations',
        ).map(
          (snap) =>
              [
                for (final d in snap.docs)
                  Conversation.fromMap(d.id, plainData(d.data())),
              ].where((c) => c.listed).toList()..sort(
                (a, b) => (b.lastMessageAt ?? _never).compareTo(
                  a.lastMessageAt ?? _never,
                ),
              ),
        ),
  );

  @override
  Stream<Conversation?> watchConversation(String id, {required String uid}) =>
      combineLatest(
        _conversations
            .doc(id)
            .snapshots()
            .map(
              (d) => d.exists
                  ? Conversation.fromMap(d.id, plainData(d.data()))
                  : null,
            ),
        _watchReads(uid),
        (c, reads) => c?.withMine(reads[id]),
      );

  /// `POST /v1/conversations`: the server decides between their inbox, a
  /// request, or not at all (then its own message, "Sam doesn't take
  /// messages from you.", comes back as the error).
  @override
  Future<Result<String>> openConversation(AppUser me, UserProfile other) =>
      guard(() async {
        final r = await _api.required.post('/v1/conversations', {
          'with': other.uid,
        });
        return r['id'] as String? ?? Conversation.idFor(me.uid, other.uid);
      });

  /// `POST /v1/conversations/groups` with the group's id (`g-` and letters),
  /// so a replay is a 409 rather than a second group.
  @override
  Future<Result<GroupAdded>> createGroup(
    AppUser me,
    String name,
    List<UserProfile> members,
  ) => guard(() async {
    final id = 'g-${_conversations.doc().id}';
    final r = await _api.required.post('/v1/conversations/groups', {
      'id': id,
      'name': cleanText(name).trim(),
      'members': [for (final m in members) m.uid],
    });
    return (id: r['id'] as String? ?? id, notAdded: _names(r['notAdded']));
  });

  /// `POST /v1/conversations/:id/members`; the server adds each person who
  /// follows the adder and takes messages, and names the rest.
  @override
  Future<Result<GroupAdded>> addToGroup(
    String id,
    AppUser me,
    List<UserProfile> members,
  ) => guard(() async {
    if (members.isEmpty) return (id: id, notAdded: const <String>[]);
    final r = await _api.required.post('${_conv(id)}/members', {
      'members': [for (final m in members) m.uid],
    });
    return (id: id, notAdded: _names(r['notAdded']));
  });

  static List<String> _names(Object? v) => [
    for (final n in (v as List?) ?? const []) '$n',
  ];

  @override
  Future<Result<void>> removeFromGroup(String id, String uid) =>
      guard(() => _api.required.delete('${_conv(id)}/members/${_enc(uid)}'));

  @override
  Future<Result<void>> renameGroup(String id, String name) => guard(
    () => _api.required.patch(_conv(id), {'name': cleanText(name).trim()}),
  );

  @override
  Future<Result<void>> setArchived(
    String id,
    String uid, {
    required bool archived,
  }) => guard(
    () => _reads(uid).doc(id).set({
      'archivedAt': archived
          ? FieldValue.serverTimestamp()
          : FieldValue.delete(),
    }, SetOptions(merge: true)),
  );

  @override
  Future<Result<void>> clearConversation(String id, String uid) => guard(
    () => _reads(uid).doc(id).set({
      'clearedAt': FieldValue.serverTimestamp(),
      'archivedAt': FieldValue.delete(),
    }, SetOptions(merge: true)),
  );

  /// `PUT /v1/conversations/:id/request`; declining also clears it for the
  /// caller (the server does it).
  @override
  Future<Result<void>> answerRequest(
    String id,
    String uid, {
    required bool accept,
  }) => guard(
    () => _api.required.put('${_conv(id)}/request', {'accept': accept}),
  );

  @override
  Stream<MessagePolicy> watchMessagePolicy(String uid) => _db
      .collection('users')
      .doc(uid)
      .snapshots()
      .map((d) => MessagePolicy.parse(d.data()?['messagePolicy']));

  @override
  Future<Result<void>> setMessagePolicy(String uid, MessagePolicy policy) =>
      guard(
        () => _db.collection('users').doc(uid).set({
          'messagePolicy': policy.name,
        }, SetOptions(merge: true)),
      );

  @override
  Stream<List<ChatMessage>> watchMessages(String id, {required int limit}) =>
      _shared.get(
        'dmMessages/$id/$limit',
        () =>
            countedSnapshots(
              _messages(id).orderBy('createdAt', descending: true).limit(limit),
              'directMessages',
            ).map(
              (snap) => [
                for (final d in snap.docs.reversed)
                  ChatMessage.fromMap(d.id, plainData(d.data())),
              ],
            ),
      );

  @override
  Future<Result<List<ChatMessage>>> fetchOlderMessages(
    String id, {
    required ChatMessage before,
    required int limit,
  }) => guard(() async {
    final docs = await pageAfter(
      _messages(id),
      field: 'createdAt',
      afterValue: before.createdAt,
      afterId: before.id,
      limit: limit,
      label: 'directMessages',
    );
    return [
      for (final d in docs.reversed)
        ChatMessage.fromMap(d.id, plainData(d.data())),
    ];
  });

  @override
  Future<Result<void>> sendMessage(
    String id, {
    required AppUser author,
    required String text,
    List<NewAttachment> attachments = const [],
    MessageReply? replyTo,
  }) {
    if (refuseBlockedWords<void>([text]) case final r?) return r;
    text = maskSwearing(text);
    // The id is picked now and kept, so a retry can't post it twice.
    final messageId = _messages(id).doc().id;
    final outbox = _outbox;
    final message = {'text': text.trim(), 'replyTo': ?replyTo?.id};
    Future<Result<void>> now() => _send(
      id,
      messageId,
      message: message,
      attachments: attachments,
      ledger: outbox,
    );
    if (outbox == null || attachments.any((a) => a.tooLarge)) return now();
    return outbox.submit(
      kind: OutboxKind.directMessage,
      id: messageId,
      target: id,
      label: 'Message',
      payload: {'text': text, 'replyTo': replyTo?.toMap()},
      files: attachments,
      sendNow: now,
    );
  }

  /// Uploads [attachments] (`/v1/uploads`, `chat` files for this
  /// conversation and message), then `POST /v1/conversations/:id/messages`
  /// with the message's id and the ready upload ids. The server writes the
  /// author, time, quote and the inbox preview.
  Future<Result<void>> _send(
    String id,
    String messageId, {
    required Map<String, Object?> message,
    List<NewAttachment> attachments = const [],
    UploadLedger? ledger,
  }) => guard(() async {
    final api = _api.required;
    for (final a in attachments) {
      if (a.tooLarge) {
        throw AttachmentTooLargeException(
          a.name,
          limit: maxBytesFor(a.contentType),
        );
      }
    }
    final ready = attachments.isEmpty
        ? const <ReadyUpload>[]
        : await _uploads.uploadAll(
            purpose: UploadPurpose.chat,
            itemId: messageId,
            targetId: 'conversations/$id',
            files: attachments,
            ledger: ledger,
            ledgerKey: messageId,
          );
    await api.post('${_conv(id)}/messages', {
      ...message,
      'id': messageId,
      'uploadIds': [for (final u in ready) u.id],
    });
  });

  @override
  Future<Result<void>> deleteMessage(String id, ChatMessage message) => guard(
    () => _api.required.delete('${_conv(id)}/messages/${_enc(message.id)}'),
  );

  @override
  Future<Result<void>> setReaction(
    String id,
    String messageId,
    String uid,
    String? emoji,
  ) => guard(
    () => _api.required.put(
      '${_conv(id)}/messages/${_enc(messageId)}/reaction',
      {'emoji': emoji},
    ),
  );

  /// Your own read time (`dmReads`) stays a direct write (D6). Sharing the
  /// read receipt writes the conversation, so that goes through
  /// `POST /v1/conversations/:id/read`, which sets both.
  @override
  Future<Result<void>> markRead(
    String id,
    String uid, {
    required bool shareReceipt,
  }) => guard(() async {
    if (shareReceipt) {
      await _api.required.send('POST', '${_conv(id)}/read');
      return;
    }
    await _reads(uid).doc(id).set({
      'readAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  });

  @override
  Stream<bool> watchReadReceipts(String uid) => _db
      .collection('users')
      .doc(uid)
      .snapshots()
      .map((d) => d.data()?['readReceipts'] as bool? ?? true);

  @override
  Future<Result<void>> setReadReceipts(String uid, {required bool on}) => guard(
    () => _db.collection('users').doc(uid).set({
      'readReceipts': on,
    }, SetOptions(merge: true)),
  );

  @override
  Future<Result<Uint8List>> downloadAttachment(ChatAttachment attachment) =>
      guard(() => _files.download(attachment));

  @override
  Future<Result<String>> attachmentUrl(ChatAttachment attachment) =>
      guard(() => _files.url(attachment));
}
