import 'dart:async';

import 'package:flutter/foundation.dart';

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
  }) : _chats = chatRepository {
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
        notifyListeners();
      }, onError: _onError),
      _chats.watchRoom(teamId, roomId).listen((r) {
        _room = r;
        _roomLoaded = true;
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
  Stream<List<ChatMessage>> watchMessages(int limit) =>
      _chats.watchMessages(teamId, roomId, limit: limit);

  @override
  Future<Result<List<ChatMessage>>> fetchOlder(ChatMessage before, int limit) =>
      _chats.fetchOlderMessages(teamId, roomId, before: before, limit: limit);

  @override
  Future<Result<void>> postMessage(
    AppUser author,
    String text,
    List<NewAttachment> attachments,
  ) => _chats.sendMessage(
    teamId,
    roomId,
    author: author,
    text: text,
    attachments: attachments,
  );

  @override
  Future<Result<void>> removeMessage(ChatMessage message) =>
      _chats.deleteMessage(teamId, roomId, message);

  @override
  Future<Result<Uint8List>> download(ChatAttachment attachment) =>
      _chats.downloadAttachment(attachment);

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
