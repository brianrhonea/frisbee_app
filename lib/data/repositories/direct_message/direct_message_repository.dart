import 'dart:typed_data';

import '../../../domain/models/app_user.dart';
import '../../../domain/models/chat.dart';
import '../../../domain/models/direct_message.dart';
import '../../../utils/result.dart';

/// Private one-to-one messages between any two users, found through the
/// people directory.
abstract class DirectMessageRepository {
  /// People whose name matches [query], excluding [excludeUid].
  Future<Result<List<UserProfile>>> searchPeople(
    String query, {
    required String excludeUid,
  });

  /// [uid]'s conversations that have messages, newest first.
  Stream<List<Conversation>> watchConversations(String uid);

  Stream<Conversation?> watchConversation(String id, {required String uid});

  /// Finds or starts the conversation between [me] and [other]; returns
  /// its id.
  Future<Result<String>> openConversation(AppUser me, UserProfile other);

  /// The newest [limit] messages, oldest first.
  Stream<List<ChatMessage>> watchMessages(String id, {required int limit});

  /// Up to [limit] messages older than [before], oldest first: the page
  /// above what's loaded.
  Future<Result<List<ChatMessage>>> fetchOlderMessages(
    String id, {
    required ChatMessage before,
    required int limit,
  });

  Future<Result<void>> sendMessage(
    String id, {
    required AppUser author,
    required String text,
    List<NewAttachment> attachments = const [],
  });

  /// Deletes one of the author's own messages and its attachments.
  Future<Result<void>> deleteMessage(String id, ChatMessage message);

  /// Marks the conversation read by [uid] now.
  Future<Result<void>> markRead(
    String id,
    String uid, {
    required bool shareReceipt,
  });

  /// Whether [uid] sends read receipts (and so sees others'); on unless
  /// they turned it off.
  Stream<bool> watchReadReceipts(String uid);

  Future<Result<void>> setReadReceipts(String uid, {required bool on});

  Future<Result<Uint8List>> downloadAttachment(ChatAttachment attachment);

  /// Who's typing in conversation [id]: uid → when they last typed, by
  /// the server's clock (null until it's stamped). The app decides when
  /// a typist has gone quiet.
  Stream<Map<String, DateTime?>> watchTyping(String id);

  /// Says [uid] is typing in [id] (or has stopped).
  Future<void> setTyping(String id, String uid, {required bool typing});
}
