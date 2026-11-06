import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../domain/models/app_user.dart';
import '../../../domain/models/chat.dart';
import '../../../domain/models/direct_message.dart';
import '../../../domain/models/model_utils.dart';
import '../../../utils/result.dart';
import '../../services/api_search.dart';
import '../../services/attachment_storage.dart';
import '../../services/firestore_utils.dart';
import '../../services/shared_streams.dart';
import 'direct_message_repository.dart';
import '../../../domain/models/username.dart';

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
  }) : _files = attachments,
       _db = firestore ?? FirebaseFirestore.instance,
       _shared = sharedStreams ?? SharedStreams.instance,
       _search = search;

  /// Searches through the rate-limited Cloud Function when it's turned on.
  final ApiSearch? _search;

  final AttachmentStorage _files;
  final FirebaseFirestore _db;

  /// One listener per query, shared by every screen (see [SharedStreams]).
  final SharedStreams _shared;

  static const _searchLimit = 20;

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
      final snap = await _profiles
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
                ].where((c) => c.hasMessages).toList()
                ..sort((a, b) => b.lastMessageAt!.compareTo(a.lastMessageAt!)),
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

  @override
  Future<Result<String>> openConversation(AppUser me, UserProfile other) =>
      guard(() async {
        final id = Conversation.idFor(me.uid, other.uid);
        final ref = _conversations.doc(id);
        // Who follows whom is private, so let the rules decide: straight
        // to their inbox if they follow me, else a request if their
        // settings allow one, else not at all.
        for (final request in [false, true]) {
          try {
            await _db.runTransaction((tx) async {
              if ((await tx.get(ref)).exists) return;
              tx.set(ref, {
                'participants': id.split('_'),
                'names': {me.uid: me.label, other.uid: other.name},
                'lastMessage': '',
                'lastMessageAt': null,
                'lastSenderId': '',
                'readAt': <String, Object>{},
                'createdAt': FieldValue.serverTimestamp(),
                'status': request ? 'request' : 'accepted',
                if (request) 'requestedOf': other.uid,
              });
            });
            return id;
          } on FirebaseException catch (e) {
            if (e.code != 'permission-denied') rethrow;
          }
        }
        throw MessagingNotAllowedException(other.name);
      });

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

  @override
  Future<Result<void>> answerRequest(
    String id,
    String uid, {
    required bool accept,
  }) => guard(() async {
    final batch = _db.batch()
      ..update(_conversations.doc(id), {
        'status': accept ? 'accepted' : 'declined',
      });
    // Declining also clears it for them, so nothing lingers.
    if (!accept) {
      batch.set(_reads(uid).doc(id), {
        'clearedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await batch.commit();
  });

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
  }) => guard(
    () => muteAware(_db, author.uid, () async {
      for (final a in attachments) {
        if (a.tooLarge) throw AttachmentTooLargeException(a.name);
      }
      final ref = _messages(id).doc();
      final uploaded = await _files.upload(
        'conversations/$id/${author.uid}/${ref.id}',
        attachments,
      );
      try {
        await (_db.batch()
              ..set(ref, {
                'authorId': author.uid,
                'authorName': author.label,
                'text': text.trim(),
                'attachments': [for (final a in uploaded) a.toMap()],
                'createdAt': FieldValue.serverTimestamp(),
              })
              ..update(_conversations.doc(id), {
                'lastMessage': messagePreview(
                  text,
                  uploaded.length,
                  image:
                      uploaded.isNotEmpty && uploaded.every((a) => a.isImage),
                ),
                'lastMessageAt': FieldValue.serverTimestamp(),
                'lastSenderId': author.uid,
                'readAt.${author.uid}': FieldValue.serverTimestamp(),
                'names.${author.uid}': author.label,
              }))
            .commit();
      } catch (_) {
        await _files.delete(uploaded.map((a) => a.path));
        rethrow;
      }
    }),
  );

  @override
  Future<Result<void>> deleteMessage(String id, ChatMessage message) =>
      guard(() async {
        await _files.delete(message.attachments.map((a) => a.path));
        await _messages(id).doc(message.id).delete();
      });

  @override
  Future<Result<void>> markRead(
    String id,
    String uid, {
    required bool shareReceipt,
  }) => guard(() async {
    final batch = _db.batch()
      ..set(_reads(uid).doc(id), {
        'readAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    if (shareReceipt) {
      batch.update(_conversations.doc(id), {
        'readAt.$uid': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
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
}
