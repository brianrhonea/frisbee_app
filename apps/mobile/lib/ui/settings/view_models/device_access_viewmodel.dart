import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../data/services/device_permissions.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// Settings > Privacy > Photos, camera & microphone: where each stands on
/// this phone, a way to ask, and a way to the system settings. Rechecks
/// when the user comes back from the system settings.
class DeviceAccessViewModel extends ChangeNotifier {
  DeviceAccessViewModel({required DevicePermissions permissions})
    : _permissions = permissions {
    ask = Command1<void, DeviceAccess>(_ask);
    openSettings = Command0<void>(() async {
      await _permissions.openSettings();
      return const Result.ok(null);
    });
    if (supported) {
      try {
        _lifecycle = AppLifecycleListener(onResume: refresh);
      } on Object {
        // No binding (a plain unit test).
      }
      refresh();
    }
  }

  final DevicePermissions _permissions;
  AppLifecycleListener? _lifecycle;
  final _status = <DeviceAccess, AccessStatus>{};
  bool _disposed = false;

  /// Only phones ask for these; elsewhere the section is hidden.
  bool get supported => _permissions.supported;

  /// Null until checked.
  AccessStatus? statusOf(DeviceAccess a) => _status[a];

  /// Asks for one that hasn't been asked yet.
  late final Command1<void, DeviceAccess> ask;

  /// Opens this app's page in the phone's settings.
  late final Command0<void> openSettings;

  Future<void> refresh() async {
    for (final a in DeviceAccess.values) {
      try {
        _status[a] = await _permissions.status(a);
      } on Exception {
        _status.remove(a);
      }
    }
    if (!_disposed) notifyListeners();
  }

  Future<Result<void>> _ask(DeviceAccess a) async {
    try {
      _status[a] = await _permissions.request(a);
    } on Exception catch (e) {
      return Result.error(e);
    }
    notifyListeners();
    return const Result.ok(null);
  }

  @override
  void dispose() {
    _disposed = true;
    _lifecycle?.dispose();
    ask.dispose();
    openSettings.dispose();
    super.dispose();
  }
}
