import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/direct_message/direct_message_repository.dart';
import '../../../data/repositories/notification/notification_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../domain/models/app_user.dart';
import '../../../domain/models/notification.dart';
import '../../../domain/models/team.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// What the app's frame shows around every page: the signed-in user, their
/// teams (the sidebar's "Your club"), and unread message and notification
/// counts. It also offers push notifications: once after sign-in, and for
/// each team or group the user joins.
class ShellViewModel extends ChangeNotifier {
  ShellViewModel({
    required AuthRepository authRepository,
    required TeamRepository teamRepository,
    required DirectMessageRepository directMessageRepository,
    required NotificationRepository notificationRepository,
  }) : _auth = authRepository,
       _notifications = notificationRepository {
    answerPushOffer = Command1<PushStatus?, bool>(_answerPushOffer);
    answerTeamOffer = Command1<PushStatus?, bool?>(_answerTeamOffer);
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    unawaited(_checkPushOffer());
    _subs
      ..add(
        teamRepository.watchMyTeams(uid).listen((t) {
          _teams = [...t]..sort((a, b) => a.name.compareTo(b.name));
          _noticeJoins(uid, t);
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
  final NotificationRepository _notifications;
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

  bool _offerPush = false;

  /// Whether to offer push notifications now (after sign-in, once).
  bool get offerPush => _offerPush;

  /// Ids of the teams seen so far; null until the first list arrives, so
  /// teams the user was already on aren't taken for new ones.
  Set<String>? _knownTeams;
  final _joined = <Team>[];

  /// A team or group the user just joined, to ask about its
  /// notifications; null when there's nothing to ask.
  Team? get joinedTeam => _joined.firstOrNull;

  /// The answer to [offerPush]: true asks the system for permission;
  /// false remembers "Not now" on this device.
  late final Command1<PushStatus?, bool> answerPushOffer;

  /// The answer to [joinedTeam]: true turns on push and the team's
  /// notifications, false turns the team's notifications off, null (the
  /// sheet was dismissed) leaves them as they are.
  late final Command1<PushStatus?, bool?> answerTeamOffer;

  Future<void> _checkPushOffer() async {
    if (!await _notifications.shouldOfferPush()) return;
    _offerPush = true;
    notifyListeners();
  }

  void _noticeJoins(String uid, List<Team> teams) {
    final known = _knownTeams;
    _knownTeams = {for (final t in teams) t.id};
    if (known == null) return;
    for (final t in teams) {
      // Owners just made it; they don't need asking.
      if (known.contains(t.id) || t.roleOf(uid) == TeamRole.owner) continue;
      _joined.add(t);
    }
  }

  Future<Result<PushStatus?>> _enablePush() async {
    final uid = user?.uid;
    if (uid == null) return Result.error(Exception('Not signed in'));
    _offerPush = false;
    return switch (await _notifications.enablePush(uid)) {
      Ok(:final value) => Result.ok(value),
      Error(:final error) => Result.error(error),
    };
  }

  Future<Result<PushStatus?>> _answerPushOffer(bool yes) async {
    _offerPush = false;
    notifyListeners();
    if (yes) return _enablePush();
    await _notifications.dismissPushOffer();
    return const Result.ok(null);
  }

  Future<Result<PushStatus?>> _answerTeamOffer(bool? yes) async {
    final uid = user?.uid;
    if (_joined.isEmpty || uid == null) return const Result.ok(null);
    final team = _joined.removeAt(0);
    notifyListeners();
    switch (yes) {
      case null:
        return const Result.ok(null);
      case true:
        final reset = await _notifications.resetTeam(uid, team.id);
        if (reset case Error(:final error)) return Result.error(error);
        return _enablePush();
      case false:
        for (final c in NotificationCategory.values) {
          if (!c.perTeam) continue;
          final saved = await _notifications.setTeamCategory(
            uid,
            team.id,
            c,
            on: false,
          );
          if (saved case Error(:final error)) return Result.error(error);
        }
        return const Result.ok(null);
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    answerPushOffer.dispose();
    answerTeamOffer.dispose();
    super.dispose();
  }
}
