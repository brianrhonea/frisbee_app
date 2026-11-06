import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/direct_message/direct_message_repository.dart';
import '../../../domain/models/app_user.dart';
import '../../../domain/models/chat.dart';
import '../../../domain/models/direct_message.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';
import '../../chat/view_models/message_thread_viewmodel.dart';

/// A private conversation with one other person.
class DirectChatViewModel extends MessageThreadViewModel {
  DirectChatViewModel({
    required this.conversationId,
    required DirectMessageRepository directMessageRepository,
    required super.authRepository,
    required super.filePicker,
    super.peopleRepository,
    super.notificationRepository,
  }) : _dms = directMessageRepository {
    accept = Command0<void>(
      () => _dms.answerRequest(conversationId, uid, accept: true),
    );
    decline = Command0<void>(
      () => _dms.answerRequest(conversationId, uid, accept: false),
    );
    toggleArchived = Command0<void>(
      () => _dms.setArchived(conversationId, uid, archived: !isArchived),
    );
    clear = Command0<void>(() => _dms.clearConversation(conversationId, uid));
    _receiptsSub = _dms
        .watchReadReceipts(uid)
        .listen(
          (on) {
            _receipts = on;
            _receiptsLoaded = true;
            _markRead();
            notifyListeners();
          },
          onError: (Object _) {
            _receiptsLoaded = true;
            _markRead();
          },
        );
    _sub = _dms
        .watchConversation(conversationId, uid: uid)
        .listen(
          (c) {
            _conversation = c;
            _loaded = true;
            if (c != null) lookUpPeople([c.otherId(uid)]);
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
    startTyping();
  }

  final String conversationId;
  final DirectMessageRepository _dms;
  late final StreamSubscription<Conversation?> _sub;
  late final StreamSubscription<bool> _receiptsSub;

  /// Whether the user sends read receipts, and so sees the other
  /// person's.
  bool _receipts = true;
  bool _receiptsLoaded = false;
  Conversation? _conversation;
  bool _loaded = false;
  bool _marking = false;

  /// The last message already marked read. Until the server fills in the
  /// read time, snapshots still look unread; this keeps them from writing
  /// again.
  DateTime? _markedUpTo;
  Object? _error;

  bool get loaded => _loaded;
  Conversation? get conversation => _conversation;
  Object? get error => _error ?? messageError;

  String get otherName => _conversation?.otherName(uid) ?? '';

  /// A message request to the user: they read it without the sender
  /// knowing, then accept or delete it.
  bool get isRequest => _conversation?.isRequestFor(uid) ?? false;

  /// A request the user sent that hasn't been accepted yet.
  bool get isPending => _conversation?.isPendingFrom(uid) ?? false;

  bool get isArchived => _conversation?.isArchived ?? false;

  /// Moves a request to the inbox, with read receipts from then on.
  late final Command0<void> accept;

  /// Deletes a request; the sender isn't told.
  late final Command0<void> decline;

  /// Archives the conversation, or brings it back to the inbox.
  late final Command0<void> toggleArchived;

  /// Deletes the conversation for the user only.
  late final Command0<void> clear;

  @override
  DateTime? get hiddenBefore => _conversation?.hiddenBefore;

  /// The other person's username, once looked up.
  String? get otherUsername =>
      _conversation == null ? null : usernameOf(_conversation!.otherId(uid));

  @override
  bool get canWrite =>
      (_conversation?.participants.contains(uid) ?? false) && !isRequest;

  /// Opening the conversation reads it.
  void _markRead() {
    final c = _conversation;
    // Wait for the setting, so a read never leaks a receipt.
    if (!_receiptsLoaded) return;
    if (_marking || c == null) return;
    if (!c.isUnread(uid) && !c.isUnreadRequest(uid)) return;
    if (_markedUpTo != null && _markedUpTo == c.lastMessageAt) return;
    _markedUpTo = c.lastMessageAt;
    _marking = true;
    _dms
        // A request is read in private until it's accepted.
        .markRead(
          conversationId,
          uid,
          shareReceipt: _receipts && !c.isRequestFor(uid),
        )
        .whenComplete(() => _marking = false);
  }

  /// "Seen" under the user's newest message once the other person has
  /// read it; only for people who send read receipts themselves.
  @override
  String? receiptFor(ChatMessage message) {
    final c = _conversation;
    if (!_receipts || c == null || message.authorId != uid) return null;
    if (c.isPendingFrom(uid)) return null;
    if (messages.lastOrNull?.id != message.id) return null;
    return c.isSeen(uid) ? 'Seen' : null;
  }

  @override
  String get noticeKey => 'dm_$conversationId';

  @override
  bool get showsTyping => true;

  @override
  Stream<Map<String, DateTime?>> watchTyping() =>
      _dms.watchTyping(conversationId);

  @override
  Future<void> sendTyping({required bool typing}) =>
      _dms.setTyping(conversationId, uid, typing: typing);

  @override
  String typistName(String uid) =>
      _conversation?.names[uid] ?? super.typistName(uid);

  @override
  Stream<List<ChatMessage>> watchMessages(int limit) =>
      _dms.watchMessages(conversationId, limit: limit);

  @override
  Future<Result<List<ChatMessage>>> fetchOlder(ChatMessage before, int limit) =>
      _dms.fetchOlderMessages(conversationId, before: before, limit: limit);

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
    accept.dispose();
    decline.dispose();
    toggleArchived.dispose();
    clear.dispose();
    _sub.cancel();
    _receiptsSub.cancel();
    super.dispose();
  }
}
