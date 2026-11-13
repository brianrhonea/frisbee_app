import 'dart:typed_data';

import '../../../domain/models/app_user.dart';
import '../../../domain/models/chat.dart';
import '../../../domain/models/team.dart';
import '../../../utils/result.dart';

abstract class ChatRepository {
  /// Rooms [uid] can see on [team], in order ([sortRooms]). Members who
  /// can manage chats see every room so they can manage access.
  Stream<List<ChatRoom>> watchRooms(Team team, String uid);

  /// The team's chat folders, in order ([sortFolders]).
  Stream<List<ChatFolder>> watchFolders(String teamId);

  /// Creates the folder when [ChatFolder.isNew], otherwise updates its name,
  /// position and default access. Returns the folder id.
  Future<Result<String>> saveFolder(
    String teamId,
    ChatFolder folder,
    String uid,
  );

  /// Deletes the folder, moving its rooms (from [rooms]) out of it.
  Future<Result<void>> deleteFolder(
    String teamId,
    String folderId,
    List<ChatRoom> rooms,
  );

  /// Saves the positions of [folders], and the positions and folders of
  /// [rooms], in one write.
  Future<Result<void>> arrange(
    String teamId, {
    List<ChatFolder> folders,
    List<ChatRoom> rooms,
  });

  Stream<ChatRoom?> watchRoom(String teamId, String roomId);

  /// Creates the room when [ChatRoom.isNew], otherwise updates its name and
  /// access. Returns the room id.
  Future<Result<String>> saveRoom(String teamId, ChatRoom room, String uid);

  /// Deletes the room, its messages and their attachments.
  Future<Result<void>> deleteRoom(String teamId, String roomId);

  /// Creates the General room if the team doesn't have one yet.
  Future<Result<void>> ensureGeneralRoom(String teamId, String uid);

  /// Adds the default voice channels and their folder to a team made
  /// before voice channels, unless it has its Voice Channels folder or
  /// any of them already.
  Future<Result<void>> ensureVoiceRooms(String teamId, String uid);

  /// The newest [limit] messages, oldest first.
  Stream<List<ChatMessage>> watchMessages(
    String teamId,
    String roomId, {
    required int limit,
  });

  /// Up to [limit] messages older than [before], oldest first: the page
  /// above what's loaded.
  Future<Result<List<ChatMessage>>> fetchOlderMessages(
    String teamId,
    String roomId, {
    required ChatMessage before,
    required int limit,
  });

  /// Uploads [attachments], then posts the message.
  Future<Result<void>> sendMessage(
    String teamId,
    String roomId, {
    required AppUser author,
    required String text,
    List<NewAttachment> attachments = const [],
    MessageReply? replyTo,
  });

  /// Sets [uid]'s reaction to message [messageId]; null takes it away.
  Future<Result<void>> setReaction(
    String teamId,
    String roomId,
    String messageId,
    String uid,
    String? emoji,
  );

  /// Deletes the message and its attachments.
  Future<Result<void>> deleteMessage(
    String teamId,
    String roomId,
    ChatMessage message,
  );

  Future<Result<Uint8List>> downloadAttachment(ChatAttachment attachment);

  /// A URL to stream a video attachment from.
  Future<Result<String>> attachmentUrl(ChatAttachment attachment);
}
