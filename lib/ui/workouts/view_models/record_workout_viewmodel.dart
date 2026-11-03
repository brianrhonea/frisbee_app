import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/workout_recorder/workout_recorder.dart';
import '../../../data/services/location_service.dart';
import '../../../domain/models/workout.dart';
import '../../../domain/models/workout_route.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// Records a run, ride, walk or hike with GPS. The recording itself lives
/// in [WorkoutRecorder], so it carries on if the user leaves this page.
class RecordWorkoutViewModel extends ChangeNotifier {
  RecordWorkoutViewModel({
    required WorkoutRecorder recorder,
    required LocationService location,
    this.unit = DistanceUnit.mi,
  }) : _recorder = recorder,
       _location = location {
    _recorder.addListener(notifyListeners);
    prepare = Command0(_prepare)..execute();
    // The clock moves even when the GPS doesn't.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_recorder.state == RecorderState.recording) notifyListeners();
    });
  }

  final WorkoutRecorder _recorder;
  final LocationService _location;
  final DistanceUnit unit;
  late final Timer _ticker;

  /// Turns on the GPS; the result says whether the app may use it.
  late final Command0<LocationAccess> prepare;

  Future<Result<LocationAccess>> _prepare() async {
    try {
      return Result.ok(await _recorder.prepare());
    } on Exception catch (e) {
      return Result.error(e);
    }
  }

  /// Why the GPS can't be used; null while asking or when it can.
  LocationAccess? get blocked => switch (prepare.result) {
    Ok(:final value) when value != LocationAccess.granted => value,
    _ => null,
  };

  RecorderState get state => _recorder.state;
  WorkoutActivity get activity => _recorder.activity;
  bool get weakSignal => _recorder.weakSignal;
  Object? get gpsError => _recorder.gpsError;

  /// Activities can only be changed before starting.
  bool get canChangeActivity => _recorder.state == RecorderState.ready;

  Duration get elapsed => _recorder.elapsed;
  double get meters => _recorder.meters;

  List<RoutePoint> get path => [for (final t in _recorder.track) t.point];

  /// Where the user is now, if known.
  RoutePoint? get here => switch (_recorder.lastFix) {
    null => null,
    final f => RoutePoint(f.lat, f.lng),
  };

  String get timeLabel => formatClock(elapsed);
  String get distanceLabel => formatDistance(meters, unit);

  /// Average pace (speed for rides) so far.
  String get averageLabel {
    final s = elapsed.inMilliseconds / 1000;
    return (activity.showsSpeed
            ? formatSpeed(s, meters, unit)
            : formatPace(s, meters, unit)) ??
        '–';
  }

  /// Pace (or speed) over the last 30 seconds.
  String get currentLabel {
    final secsPerMeter = _recorder.currentPace();
    if (secsPerMeter == null || state != RecorderState.recording) return '–';
    return (activity.showsSpeed
            ? formatSpeed(secsPerMeter * 100, 100, unit)
            : formatPace(secsPerMeter * 100, 100, unit)) ??
        '–';
  }

  void selectActivity(WorkoutActivity a) => _recorder.selectActivity(a);
  void start() => _recorder.start();
  void pause() => _recorder.pause();
  void resume() => _recorder.resume();

  /// Stops and returns the workout to share; null when nothing was
  /// recorded.
  Workout? finish() => _recorder.finish();

  /// The finished workout, if it hasn't been posted or thrown away.
  Workout? get result => _recorder.result;

  /// Throws the recording away and gets ready for another.
  void discard() {
    _recorder.discard();
    prepare.execute();
  }

  /// The workout was posted; clear it for next time.
  void posted() => _recorder.discard();

  Future<void> openSettings() async {
    final why = blocked;
    if (why != null) await _location.openSettings(why);
  }

  @override
  void dispose() {
    _ticker.cancel();
    _recorder.removeListener(notifyListeners);
    // Leaving before starting turns the GPS off; a recording carries on.
    _recorder.release();
    prepare.dispose();
    super.dispose();
  }
}
