import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/notification/notification_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../domain/models/notification.dart';
import '../../../domain/models/team.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// Push on this device, category defaults, and per-team overrides.
class NotificationSettingsViewModel extends ChangeNotifier {
  NotificationSettingsViewModel({
    required NotificationRepository notificationRepository,
    required TeamRepository teamRepository,
    required AuthRepository authRepository,
  }) : _repo = notificationRepository,
       uid = authRepository.currentUser?.uid ?? '' {
    enablePush = Command0<PushStatus>(() async {
      final result = await _repo.enablePush(uid);
      if (result case Ok(:final value)) {
        _pushStatus = value;
        notifyListeners();
      }
      return result;
    });
    setCategory = Command1<void, (NotificationCategory, bool)>(
      (a) => _repo.setCategory(uid, a.$1, on: a.$2),
    );
    setTeamCategory = Command1<void, (String, NotificationCategory, bool)>(
      (a) => _repo.setTeamCategory(uid, a.$1, a.$2, on: a.$3),
    );
    resetTeam = Command1<void, String>((id) => _repo.resetTeam(uid, id));
    _subs = [
      _repo
          .watchPreferences(uid)
          .listen(
            (p) {
              _prefs = p;
              notifyListeners();
            },
            onError: (Object e) {
              _error = e;
              _prefs ??= const NotificationPreferences();
              notifyListeners();
            },
          ),
      teamRepository
          .watchMyTeams(uid)
          .listen(
            (t) {
              _teams = [...t]
                ..sort(
                  (a, b) =>
                      a.name.toLowerCase().compareTo(b.name.toLowerCase()),
                );
              notifyListeners();
            },
            onError: (_) {
              _teams = const [];
              notifyListeners();
            },
          ),
    ];
    unawaited(_loadPushStatus());
  }

  final NotificationRepository _repo;
  final String uid;
  late final List<StreamSubscription<Object?>> _subs;
  NotificationPreferences? _prefs;
  List<Team> _teams = const [];
  PushStatus? _pushStatus;
  Object? _error;
  bool _disposed = false;

  bool get loaded => _prefs != null;
  NotificationPreferences get prefs =>
      _prefs ?? const NotificationPreferences();
  List<Team> get teams => _teams;
  Object? get error => _error;

  /// Null until the platform has answered.
  PushStatus? get pushStatus => _pushStatus;

  late final Command0<PushStatus> enablePush;
  late final Command1<void, (NotificationCategory, bool)> setCategory;
  late final Command1<void, (String, NotificationCategory, bool)>
  setTeamCategory;
  late final Command1<void, String> resetTeam;

  Future<void> _loadPushStatus() async {
    final status = await _repo.pushStatus();
    if (_disposed) return;
    _pushStatus = status;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final s in _subs) {
      s.cancel();
    }
    enablePush.dispose();
    setCategory.dispose();
    setTeamCategory.dispose();
    resetTeam.dispose();
    super.dispose();
  }
}
