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
      switch (result) {
        case Ok(:final value):
          _pushStatus = value;
          _deviceError = null;
          _deviceRegistered = value == PushStatus.enabled;
        case Error(:final error):
          // Allowed, but this device couldn't be registered.
          _pushStatus = await _repo.pushStatus();
          _deviceError = error;
      }
      if (!_disposed) notifyListeners();
      return result;
    });
    registerDevice = Command0<void>(_registerDevice);
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

  /// This phone could get push but doesn't (never allowed, "Not now", or
  /// turned off in the system settings). The choices below then don't
  /// apply, so they're shown off until push is turned on.
  bool get pushOff =>
      _pushStatus == PushStatus.notDetermined ||
      _pushStatus == PushStatus.denied;

  late final Command0<PushStatus> enablePush;

  /// Registers this device again, e.g. after fixing what [deviceError]
  /// said.
  late final Command0<void> registerDevice;

  bool _deviceRegistered = false;
  Object? _deviceError;

  /// Push is allowed and this device is registered to receive it.
  bool get deviceRegistered => _deviceRegistered;

  /// Push is allowed but this device couldn't be registered, and why.
  /// Without registering, nothing reaches it while the app is closed.
  Object? get deviceError => _deviceError;

  Future<Result<void>> _registerDevice() async {
    final result = await _repo.registerDevice(uid);
    if (_disposed) return result;
    switch (result) {
      case Ok():
        _deviceRegistered = true;
        _deviceError = null;
      case Error(:final error):
        _deviceRegistered = false;
        _deviceError = error;
    }
    notifyListeners();
    return result;
  }

  late final Command1<void, (NotificationCategory, bool)> setCategory;
  late final Command1<void, (String, NotificationCategory, bool)>
  setTeamCategory;
  late final Command1<void, String> resetTeam;

  Future<void> _loadPushStatus() async {
    final status = await _repo.pushStatus();
    if (_disposed) return;
    _pushStatus = status;
    notifyListeners();
    // Check this device is really registered, so a failure shows here
    // instead of push silently never arriving.
    if (status == PushStatus.enabled) await registerDevice.execute();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final s in _subs) {
      s.cancel();
    }
    enablePush.dispose();
    registerDevice.dispose();
    setCategory.dispose();
    setTeamCategory.dispose();
    resetTeam.dispose();
    super.dispose();
  }
}
