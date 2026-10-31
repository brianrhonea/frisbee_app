import 'dart:typed_data';

import '../../../domain/models/app_user.dart';
import '../../../domain/models/chat.dart';
import '../../../domain/models/team.dart';
import '../../../utils/result.dart';

abstract class ChatRepository {
  /// Rooms [uid] can see on [team], General first, then by name. Owners,
  /// coaches and captains see every room so they can manage access.
  Stream<List<ChatRoom>> watchRooms(Team team, String uid);

  Stream<ChatRoom?> watchRoom(String teamId, String roomId);

  /// Creates the room when [ChatRoom.isNew], otherwise updates its name and
  /// access. Returns the room id.
  Future<Result<String>> saveRoom(String teamId, ChatRoom room, String uid);

  /// Deletes the room, its messages and their attachments.
  Future<Result<void>> deleteRoom(String teamId, String roomId);

  /// Creates the General room if the team doesn't have one yet.
  Future<Result<void>> ensureGeneralRoom(String teamId, String uid);

  /// The newest [limit] messages, oldest first.
  Stream<List<ChatMessage>> watchMessages(
    String teamId,
    String roomId, {
    required int limit,
  });

  /// Uploads [attachments], then posts the message.
  Future<Result<void>> sendMessage(
    String teamId,
    String roomId, {
    required AppUser author,
    required String text,
    List<NewAttachment> attachments = const [],
  });

  /// Deletes the message and its attachments.
  Future<Result<void>> deleteMessage(
    String teamId,
    String roomId,
    ChatMessage message,
  );

  Future<Result<Uint8List>> downloadAttachment(ChatAttachment attachment);
}
