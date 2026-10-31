import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../domain/models/app_user.dart';
import '../../../domain/models/chat.dart';
import '../../../domain/models/direct_message.dart';
import '../../../domain/models/model_utils.dart';
import '../../../utils/result.dart';
import '../../services/attachment_storage.dart';
import '../../services/firestore_utils.dart';
import 'direct_message_repository.dart';

/// The directory is `profiles/{uid}` (name and photo, written by
/// AuthRepositoryFirebase). Conversations are `conversations/{a_b}` with
/// messages beneath; attachments are in Cloud Storage at
/// `conversations/{id}/{uid}/{messageId}/{fileName}`. firestore.rules and
/// storage.rules limit both to the two participants.
class DirectMessageRepositoryFirebase implements DirectMessageRepository {
  DirectMessageRepositoryFirebase({
    required AttachmentStorage attachments,
    FirebaseFirestore? firestore,
  }) : _files = attachments,
       _db = firestore ?? FirebaseFirestore.instance;

  final AttachmentStorage _files;
  final FirebaseFirestore _db;

  static const _searchLimit = 20;

  CollectionReference<Map<String, dynamic>> get _profiles =>
      _db.collection('profiles');

  CollectionReference<Map<String, dynamic>> get _conversations =>
      _db.collection('conversations');

  CollectionReference<Map<String, dynamic>> _messages(String id) =>
      _conversations.doc(id).collection('messages');

  @override
  Future<Result<List<UserProfile>>> searchPeople(
    String query, {
    required String excludeUid,
  }) => guard(() async {
    final words = searchWords(query);
    if (words.isEmpty) return const [];
    // Match the longest word in Firestore, then the rest here.
    final key = (words.toList()..sort((a, b) => b.length - a.length)).first;
    final snap = await _profiles
        .where(
          'keywords',
          arrayContains: key.length > 20 ? key.substring(0, 20) : key,
        )
        .limit(_searchLimit * 2)
        .get();
    return [
      for (final d in snap.docs)
        if (d.id != excludeUid) UserProfile.fromMap(d.id, plainData(d.data())),
    ].where((p) => p.matches(query)).take(_searchLimit).toList()..sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
  });

  @override
  Stream<List<Conversation>> watchConversations(String uid) => _conversations
      .where('participants', arrayContains: uid)
      .snapshots()
      .map(
        (snap) =>
            [
                for (final d in snap.docs)
                  Conversation.fromMap(d.id, plainData(d.data())),
              ].where((c) => c.hasMessages).toList()
              ..sort((a, b) => b.lastMessageAt!.compareTo(a.lastMessageAt!)),
      );

  @override
  Stream<Conversation?> watchConversation(String id) => _conversations
      .doc(id)
      .snapshots()
      .map(
        (d) =>
            d.exists ? Conversation.fromMap(d.id, plainData(d.data())) : null,
      );

  @override
  Future<Result<String>> openConversation(AppUser me, UserProfile other) =>
      guard(() async {
        final id = Conversation.idFor(me.uid, other.uid);
        final ref = _conversations.doc(id);
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
          });
        });
        return id;
      });

  @override
  Stream<List<ChatMessage>> watchMessages(String id, {required int limit}) =>
      _messages(id)
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
    String id, {
    required AppUser author,
    required String text,
    List<NewAttachment> attachments = const [],
  }) => guard(() async {
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
                image: uploaded.isNotEmpty && uploaded.every((a) => a.isImage),
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
  });

  @override
  Future<Result<void>> deleteMessage(String id, ChatMessage message) =>
      guard(() async {
        await _files.delete(message.attachments.map((a) => a.path));
        await _messages(id).doc(message.id).delete();
      });

  @override
  Future<Result<void>> markRead(String id, String uid) => guard(
    () => _conversations.doc(id).update({
      'readAt.$uid': FieldValue.serverTimestamp(),
    }),
  );

  @override
  Future<Result<Uint8List>> downloadAttachment(ChatAttachment attachment) =>
      guard(() => _files.download(attachment));
}
