import 'dart:typed_data';

import '../../../data/repositories/meeting/meeting_repository.dart';
import '../../../domain/models/app_user.dart';
import '../../../domain/models/chat.dart';
import '../../../utils/result.dart';
import '../../chat/view_models/message_thread_viewmodel.dart';

/// The chat inside a meeting call: text only, for people in the call.
/// Counts messages from others that arrive while the chat is hidden.
class MeetingChatViewModel extends MessageThreadViewModel {
  MeetingChatViewModel({
    required this.teamId,
    required this.meetingId,
    required MeetingRepository meetingRepository,
    required this.canModerate,
    required super.authRepository,
    required super.filePicker,
  }) : _meetings = meetingRepository {
    startMessages();
  }

  final String teamId;
  final String meetingId;
  final MeetingRepository _meetings;

  /// Admins may delete anyone's message.
  @override
  final bool canModerate;

  @override
  bool get canWrite => true;

  @override
  bool get canAttach => false;

  bool _visible = false;
  final Set<String> _seen = {};
  int _unread = 0;

  /// Messages from others since the chat was last shown.
  int get unread => _unread;

  /// Whether the chat is on screen; showing it marks everything read.
  set visible(bool visible) {
    if (_visible == visible) return;
    _visible = visible;
    if (visible) _markSeen(messages);
    notifyListeners();
  }

  void _markSeen(List<ChatMessage> messages) {
    _seen.addAll(messages.map((m) => m.id));
    _unread = 0;
  }

  bool _first = true;

  @override
  void onMessages(List<ChatMessage> messages) {
    // What was there before the user joined isn't news.
    if (_first || _visible) {
      _first = false;
      _markSeen(messages);
      return;
    }
    for (final m in messages) {
      if (_seen.add(m.id) && !isMine(m)) _unread++;
    }
  }

  @override
  Stream<List<ChatMessage>> watchMessages(int limit) =>
      _meetings.watchMessages(teamId, meetingId, limit: limit);

  @override
  Future<Result<void>> postMessage(
    AppUser author,
    String text,
    List<NewAttachment> attachments,
  ) => _meetings.sendMessage(teamId, meetingId, author: author, text: text);

  @override
  Future<Result<void>> removeMessage(ChatMessage message) =>
      _meetings.deleteMessage(teamId, meetingId, message.id);

  @override
  Future<Result<Uint8List>> download(ChatAttachment attachment) async =>
      Result.error(Exception('Meeting chat has no attachments.'));
}
