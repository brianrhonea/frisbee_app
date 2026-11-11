import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Whether the app may use the device's location.
enum LocationAccess { granted, denied, deniedForever, serviceOff }

/// One reading from the device's GPS.
class LocationFix {
  const LocationFix({
    required this.lat,
    required this.lng,
    required this.accuracy,
    required this.time,
    this.altitude,
  });

  final double lat;
  final double lng;

  /// Metres, 68% confidence.
  final double accuracy;
  final DateTime time;
  final double? altitude;
}

/// The device's GPS.
abstract class LocationService {
  /// Asks for permission if needed.
  Future<LocationAccess> requestAccess();

  /// Fixes as the device moves, until the subscription is cancelled. On
  /// Android this runs a foreground service (with a notification) and on
  /// iOS keeps going in the background, so recording survives a locked
  /// screen.
  Stream<LocationFix> track();

  /// Opens the app's settings (to grant a denied permission), or the
  /// device's location settings when location is off.
  Future<void> openSettings(LocationAccess access);
}

class GeolocatorLocationService implements LocationService {
  @override
  Future<LocationAccess> requestAccess() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationAccess.serviceOff;
    }
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    return switch (p) {
      LocationPermission.always ||
      LocationPermission.whileInUse => LocationAccess.granted,
      LocationPermission.deniedForever => LocationAccess.deniedForever,
      _ => LocationAccess.denied,
    };
  }

  @override
  Stream<LocationFix> track() =>
      Geolocator.getPositionStream(locationSettings: _settings()).map(
        (p) => LocationFix(
          lat: p.latitude,
          lng: p.longitude,
          accuracy: p.accuracy,
          time: p.timestamp,
          altitude: p.altitude,
        ),
      );

  LocationSettings _settings() => switch (defaultTargetPlatform) {
    TargetPlatform.android => AndroidSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 2,
      intervalDuration: const Duration(seconds: 1),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'Recording your workout',
        notificationText: 'Stall 10 is mapping your route.',
        notificationChannelName: 'Workout recording',
        enableWakeLock: true,
        setOngoing: true,
      ),
    ),
    TargetPlatform.iOS || TargetPlatform.macOS => AppleSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      activityType: ActivityType.fitness,
      distanceFilter: 2,
      pauseLocationUpdatesAutomatically: false,
      showBackgroundLocationIndicator: true,
      allowBackgroundLocationUpdates: true,
    ),
    _ => const LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 2,
    ),
  };

  @override
  Future<void> openSettings(LocationAccess access) async {
    if (access == LocationAccess.serviceOff) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
  }
}
