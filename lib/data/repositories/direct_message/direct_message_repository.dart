import 'dart:typed_data';

import '../../../domain/models/app_user.dart';
import '../../../domain/models/chat.dart';
import '../../../domain/models/direct_message.dart';
import '../../../utils/result.dart';

/// Private one-to-one messages between any two users, found through the
/// people directory.
///
/// Who may start one is up to the recipient's [MessagePolicy]: people
/// they follow reach their inbox; others, if allowed at all, land in their
/// Message requests.
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
  /// its id. A new one is a message request unless [other] follows [me];
  /// fails with [MessagingNotAllowedException] if [other]'s
  /// [MessagePolicy] doesn't let [me] message them at all.
  Future<Result<String>> openConversation(AppUser me, UserProfile other);

  /// Starts a group named [name] with [me] and [members]; returns its id
  /// and anyone who couldn't be added (only people who follow [me], and
  /// haven't turned messages off, can be).
  Future<Result<GroupAdded>> createGroup(
    AppUser me,
    String name,
    List<UserProfile> members,
  );

  /// Adds [members] to group [id], one at a time; returns its id and
  /// anyone who couldn't be added.
  Future<Result<GroupAdded>> addToGroup(
    String id,
    AppUser me,
    List<UserProfile> members,
  );

  /// Takes [uid] out of group [id]: leaving it, or (its creator) removing
  /// them.
  Future<Result<void>> removeFromGroup(String id, String uid);

  Future<Result<void>> renameGroup(String id, String name);

  /// Archives conversation [id] for [uid] (out of their inbox until a new
  /// message), or brings it back.
  Future<Result<void>> setArchived(
    String id,
    String uid, {
    required bool archived,
  });

  /// Deletes conversation [id] for [uid] only: its messages so far are
  /// hidden from them, and it leaves their inbox until a new one arrives.
  Future<Result<void>> clearConversation(String id, String uid);

  /// Accepts or deletes a message request to [uid]. Deleting it tells the
  /// sender nothing.
  Future<Result<void>> answerRequest(
    String id,
    String uid, {
    required bool accept,
  });

  /// Who may start a conversation with [uid].
  Stream<MessagePolicy> watchMessagePolicy(String uid);

  Future<Result<void>> setMessagePolicy(String uid, MessagePolicy policy);

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

/// The other person's message settings don't let the user message them.
class MessagingNotAllowedException implements Exception {
  const MessagingNotAllowedException(this.name);

  final String name;

  @override
  String toString() => "$name isn't accepting messages from you.";
}

/// A group, and the names of anyone who couldn't be added to it.
typedef GroupAdded = ({String id, List<String> notAdded});

/// A group already has [Conversation.maxGroupSize] members.
class GroupFullException implements Exception {
  const GroupFullException();

  @override
  String toString() => 'Groups have up to ${Conversation.maxGroupSize} people.';
}
