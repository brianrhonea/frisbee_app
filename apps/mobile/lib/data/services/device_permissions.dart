import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// The device permissions Stall 10 asks for, as shown in Settings >
/// Privacy.
enum DeviceAccess {
  photos('Photos', 'Choose photos and videos to post and send.'),
  camera('Camera', 'Take photos and videos, and show yourself in meetings.'),
  microphone('Microphone', 'Record sound with videos, and talk in meetings.');

  const DeviceAccess(this.label, this.purpose);

  final String label;
  final String purpose;
}

/// Where a permission stands on this device.
enum AccessStatus {
  /// Not asked yet: the app asks the first time it's needed.
  notAsked('Not asked yet'),
  allowed('Allowed'),

  /// iOS "Selected photos": only the photos the user picked.
  limited('Selected photos only'),
  denied('Not allowed'),

  /// Android's photo picker hands over only the photos picked, so the app
  /// never asks for the library (and doesn't declare it).
  notNeeded('Not needed: you pick each photo');

  const AccessStatus(this.label);

  final String label;
}

/// Asks for and reports device permissions on phones (iOS and Android);
/// elsewhere the system file dialogs need none, and [supported] is false.
/// iOS reads these only for the permissions enabled in ios/Podfile.
class DevicePermissions {
  const DevicePermissions();

  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  static Permission _permission(DeviceAccess a) => switch (a) {
    DeviceAccess.photos => Permission.photos,
    DeviceAccess.camera => Permission.camera,
    DeviceAccess.microphone => Permission.microphone,
  };

  static AccessStatus _status(PermissionStatus s) => switch (s) {
    PermissionStatus.granted ||
    PermissionStatus.provisional => AccessStatus.allowed,
    PermissionStatus.limited => AccessStatus.limited,
    PermissionStatus.denied => AccessStatus.notAsked,
    PermissionStatus.permanentlyDenied ||
    PermissionStatus.restricted => AccessStatus.denied,
  };

  bool _pickerOnly(DeviceAccess a) =>
      a == DeviceAccess.photos &&
      defaultTargetPlatform == TargetPlatform.android;

  Future<AccessStatus> status(DeviceAccess a) async {
    if (!supported) return AccessStatus.allowed;
    if (_pickerOnly(a)) return AccessStatus.notNeeded;
    final s = await _permission(a).status;
    // Android reports "denied" both before asking and after one refusal.
    if (s == PermissionStatus.denied &&
        defaultTargetPlatform == TargetPlatform.android &&
        await _permission(a).shouldShowRequestRationale) {
      return AccessStatus.denied;
    }
    return _status(s);
  }

  /// Asks for [a] if it hasn't been decided; returns where it stands.
  Future<AccessStatus> request(DeviceAccess a) async {
    if (!supported) return AccessStatus.allowed;
    if (_pickerOnly(a)) return AccessStatus.notNeeded;
    return _status(await _permission(a).request());
  }

  /// Opens this app's page in the system settings, to change them.
  Future<bool> openSettings() => openAppSettings();
}

/// The user said no to [access]; it's changed in the system settings.
class AccessDeniedException implements Exception {
  const AccessDeniedException(this.access);

  final DeviceAccess access;

  @override
  String toString() =>
      'Stall 10 needs ${access.label.toLowerCase()} access for that. Turn it '
      'on in Settings > Privacy, or in your phone\'s settings.';
}
