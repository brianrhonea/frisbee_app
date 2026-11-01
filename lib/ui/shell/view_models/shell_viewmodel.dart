import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/direct_message/direct_message_repository.dart';
import '../../../data/repositories/notification/notification_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../domain/models/app_user.dart';
import '../../../domain/models/team.dart';

/// What the app's frame shows around every page: the signed-in user, their
/// teams (the sidebar's "Your club"), and unread message and notification
/// counts.
class ShellViewModel extends ChangeNotifier {
  ShellViewModel({
    required AuthRepository authRepository,
    required TeamRepository teamRepository,
    required DirectMessageRepository directMessageRepository,
    required NotificationRepository notificationRepository,
  }) : _auth = authRepository {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    _subs
      ..add(
        teamRepository.watchMyTeams(uid).listen((t) {
          _teams = [...t]..sort((a, b) => a.name.compareTo(b.name));
          notifyListeners();
        }, onError: (Object _) {}),
      )
      ..add(
        directMessageRepository.watchConversations(uid).listen((c) {
          final unread = c.where((c) => c.isUnread(uid)).length;
          if (unread == _unreadMessages) return;
          _unreadMessages = unread;
          notifyListeners();
        }, onError: (Object _) {}),
      )
      ..add(
        notificationRepository.watchFeed(uid).listen((n) {
          final unread = n.where((n) => !n.read).length;
          if (unread == _unreadNotifications) return;
          _unreadNotifications = unread;
          notifyListeners();
        }, onError: (Object _) {}),
      );
  }

  final AuthRepository _auth;
  final List<StreamSubscription<Object?>> _subs = [];

  AppUser? get user => _auth.currentUser;

  /// The user's name, or the part of their email before "@".
  String get userName => user?.label ?? '';

  List<Team> _teams = const [];

  /// The user's teams and groups, by name.
  List<Team> get teams => _teams;

  /// Name of one of the user's teams, for breadcrumbs.
  String? teamName(String id) =>
      _teams.where((t) => t.id == id).firstOrNull?.name;

  int _unreadMessages = 0;

  /// Direct-message conversations with a message the user hasn't opened.
  int get unreadMessages => _unreadMessages;

  int _unreadNotifications = 0;

  int get unreadNotifications => _unreadNotifications;

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}
