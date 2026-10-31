import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/direct_message/direct_message_repository.dart';
import '../../../domain/models/app_user.dart';
import '../../../domain/models/chat.dart';
import '../../../domain/models/direct_message.dart';
import '../../../utils/result.dart';
import '../../chat/view_models/message_thread_viewmodel.dart';

/// A private conversation with one other person.
class DirectChatViewModel extends MessageThreadViewModel {
  DirectChatViewModel({
    required this.conversationId,
    required DirectMessageRepository directMessageRepository,
    required super.authRepository,
    required super.filePicker,
  }) : _dms = directMessageRepository {
    _sub = _dms
        .watchConversation(conversationId)
        .listen(
          (c) {
            _conversation = c;
            _loaded = true;
            _markRead();
            notifyListeners();
          },
          onError: (Object e) {
            _error = e;
            _loaded = true;
            notifyListeners();
          },
        );
    startMessages();
  }

  final String conversationId;
  final DirectMessageRepository _dms;
  late final StreamSubscription<Conversation?> _sub;
  Conversation? _conversation;
  bool _loaded = false;
  bool _marking = false;
  Object? _error;

  bool get loaded => _loaded;
  Conversation? get conversation => _conversation;
  Object? get error => _error ?? messageError;

  String get otherName => _conversation?.otherName(uid) ?? '';

  @override
  bool get canWrite => _conversation?.participants.contains(uid) ?? false;

  /// Opening the conversation reads it.
  void _markRead() {
    final c = _conversation;
    if (_marking || c == null || !c.isUnread(uid)) return;
    _marking = true;
    _dms.markRead(conversationId, uid).whenComplete(() => _marking = false);
  }

  @override
  Stream<List<ChatMessage>> watchMessages(int limit) =>
      _dms.watchMessages(conversationId, limit: limit);

  @override
  Future<Result<void>> postMessage(
    AppUser author,
    String text,
    List<NewAttachment> attachments,
  ) => _dms.sendMessage(
    conversationId,
    author: author,
    text: text,
    attachments: attachments,
  );

  @override
  Future<Result<void>> removeMessage(ChatMessage message) =>
      _dms.deleteMessage(conversationId, message);

  @override
  Future<Result<Uint8List>> download(ChatAttachment attachment) =>
      _dms.downloadAttachment(attachment);

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
