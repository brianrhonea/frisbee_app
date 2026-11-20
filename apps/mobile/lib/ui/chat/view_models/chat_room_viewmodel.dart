import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../domain/models/outbox.dart';
import '../../../data/repositories/chat/chat_repository.dart';
import '../../../data/repositories/notification/notification_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../domain/models/app_user.dart';
import '../../../domain/models/chat.dart';
import '../../../domain/models/notification.dart';
import '../../../domain/models/team.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';
import 'message_thread_viewmodel.dart';

/// Backs a team chat room: its messages, the composer and attachments.
class ChatRoomViewModel extends MessageThreadViewModel {
  ChatRoomViewModel({
    required this.teamId,
    required this.roomId,
    required TeamRepository teamRepository,
    required ChatRepository chatRepository,
    required NotificationRepository notificationRepository,
    required super.authRepository,
    required super.filePicker,
    super.peopleRepository,
    super.draftRepository,
    super.outbox,
  }) : _chats = chatRepository,
       super(notificationRepository: notificationRepository) {
    toggleMuted = Command0<void>(
      () => notificationRepository.setRoomMuted(
        uid,
        teamId,
        roomId,
        muted: !muted,
      ),
    );
    _subs = [
      notificationRepository.watchPreferences(uid).listen((p) {
        _prefs = p;
        notifyListeners();
      }, onError: (_) {}),
      teamRepository.watchTeam(teamId).listen((t) {
        _team = t;
        _teamLoaded = true;
        _markRead();
        notifyListeners();
      }, onError: _onError),
      _chats.watchRoom(teamId, roomId).listen((r) {
        _room = r;
        _roomLoaded = true;
        _markRead();
        notifyListeners();
      }, onError: _onError),
    ];
    startMessages();
  }

  final String teamId;
  final String roomId;
  final ChatRepository _chats;
  late final List<StreamSubscription<Object?>> _subs;

  Team? _team;
  bool _teamLoaded = false;
  ChatRoom? _room;
  bool _roomLoaded = false;
  Object? _error;
  NotificationPreferences? _prefs;

  Team? get team => _team;

  /// The room's lastAt when it was last marked read from here.
  DateTime? _markedAt;

  /// While the room is open, each new message counts as read (the inbox's
  /// and the room list's unread dots).
  void _markRead() {
    final last = _room?.lastAt;
    if (last == null || !access.canRead) return;
    if (_markedAt case final m? when !last.isAfter(m)) return;
    _markedAt = last;
    unawaited(_chats.markRead(teamId, roomId, uid));
  }

  /// Whether this room's notifications are silenced for the user.
  bool get muted => _prefs?.isRoomMuted(teamId, roomId) ?? false;

  late final Command0<void> toggleMuted;
  ChatRoom? get room => _room;
  bool get loaded => _teamLoaded && _roomLoaded;
  Object? get error => _error ?? messageError;

  ChatAccess get access => switch ((_team, _room)) {
    (final t?, final r?) => r.accessFor(t, uid),
    _ => ChatAccess.none,
  };

  @override
  bool get canWrite => access.canWrite;

  /// The owner and moderators delete anyone's messages.
  @override
  bool get canModerate =>
      _team?.roleOf(uid) == TeamRole.owner ||
      (_team?.has(uid, TeamPermission.moderate) ?? false);

  /// Like Discord, a member's name takes the color of their highest role
  /// that has one.
  @override
  int? nameColorOf(String uid) {
    for (final r in _team?.rolesOf(uid) ?? const <CustomRole>[]) {
      if (r.color != 0) return r.color;
    }
    return null;
  }

  /// Members who can manage chats change the room's name and access.
  bool get canManage => _team?.has(uid, TeamPermission.manageChats) ?? false;

  @override
  OutboxKind get outboxKind => OutboxKind.teamChat;

  @override
  String get outboxTarget => teamChatTarget(teamId, roomId);

  @override
  String get noticeKey => 'chat_${teamId}_$roomId';

  @override
  Stream<List<ChatMessage>> watchMessages(int limit) =>
      _chats.watchMessages(teamId, roomId, limit: limit);

  @override
  Future<Result<List<ChatMessage>>> fetchOlder(ChatMessage before, int limit) =>
      _chats.fetchOlderMessages(teamId, roomId, before: before, limit: limit);

  @override
  Future<Result<void>> postMessage(
    AppUser author,
    String text,
    List<NewAttachment> attachments, {
    MessageReply? replyTo,
  }) => _chats.sendMessage(
    teamId,
    roomId,
    author: author,
    text: text,
    attachments: attachments,
    replyTo: replyTo,
  );

  @override
  Future<Result<void>> setReaction(ChatMessage message, String? emoji) =>
      _chats.setReaction(teamId, roomId, message.id, uid, emoji);

  /// Anyone who can read the room reacts.
  @override
  bool get canReact => access.canRead;

  @override
  Future<Result<void>> removeMessage(ChatMessage message) =>
      _chats.deleteMessage(teamId, roomId, message);

  @override
  Future<Result<Uint8List>> download(ChatAttachment attachment) =>
      _chats.downloadAttachment(attachment);

  @override
  Future<Result<String>> streamUrl(ChatAttachment attachment) =>
      _chats.attachmentUrl(attachment);

  void _onError(Object e) {
    _error = e;
    _teamLoaded = true;
    _roomLoaded = true;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    toggleMuted.dispose();
    super.dispose();
  }
}
