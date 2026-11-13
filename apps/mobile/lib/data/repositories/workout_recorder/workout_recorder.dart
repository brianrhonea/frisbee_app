import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../domain/models/workout.dart';
import '../../../domain/models/workout_route.dart';
import '../../services/location_service.dart';

enum RecorderState {
  /// Not using the GPS.
  idle,

  /// Showing where the user is, waiting to start.
  ready,
  recording,
  paused,

  /// Stopped; [WorkoutRecorder.result] is the workout to post.
  finished,
}

/// The run or ride being recorded. One for the whole app, so recording
/// carries on while the user looks at other pages.
class WorkoutRecorder extends ChangeNotifier {
  WorkoutRecorder({
    required LocationService location,
    @visibleForTesting DateTime Function()? clock,
  }) : _location = location,
       _clock = clock ?? DateTime.now;

  /// Fixes less accurate than this are ignored.
  static const maxAccuracy = 35.0;

  /// Moves faster than this (m/s) are GPS jumps, not the user.
  static const maxSpeed = 40.0;

  /// Moves shorter than this are GPS jitter while standing still.
  static const minStep = 3.0;

  final LocationService _location;
  final DateTime Function() _clock;

  StreamSubscription<LocationFix>? _sub;
  RecorderState _state = RecorderState.idle;
  WorkoutActivity _activity = WorkoutActivity.run;
  final List<TrackPoint> _track = [];
  double _meters = 0;
  LocationFix? _lastFix;
  Object? _gpsError;
  Workout? _result;

  /// Moving time before the current stretch of recording.
  Duration _banked = Duration.zero;
  DateTime? _since;

  /// The next fix starts a new stretch after a pause: it isn't joined to
  /// the last one, so the distance walked while paused doesn't count.
  bool _newStretch = true;

  RecorderState get state => _state;
  WorkoutActivity get activity => _activity;
  List<TrackPoint> get track => List.unmodifiable(_track);
  double get meters => _meters;
  LocationFix? get lastFix => _lastFix;
  Object? get gpsError => _gpsError;
  Workout? get result => _result;

  bool get isActive =>
      _state == RecorderState.recording || _state == RecorderState.paused;

  /// Weak or no signal: no fix yet, or the last one was too vague to use.
  bool get weakSignal => _lastFix == null || _lastFix!.accuracy > maxAccuracy;

  /// Moving time so far.
  Duration get elapsed => switch (_since) {
    null => _banked,
    final s => _banked + _clock().difference(s),
  };

  /// Seconds per metre over the last [window] of moving time; null when
  /// standing still or just started.
  double? currentPace({Duration window = const Duration(seconds: 30)}) {
    if (_track.length < 2) return null;
    final last = _track.last;
    final from = last.elapsed - window;
    var i = _track.length - 1;
    while (i > 0 && _track[i - 1].elapsed >= from) {
      i--;
    }
    final first = _track[i];
    final m = last.distanceMeters - first.distanceMeters;
    final s = (last.elapsed - first.elapsed).inMilliseconds / 1000;
    if (m < 10 || s <= 0) return null;
    return s / m;
  }

  void selectActivity(WorkoutActivity a) {
    if (_activity == a) return;
    _activity = a;
    notifyListeners();
  }

  /// Turns on the GPS to show where the user is. Returns why not, if it
  /// can't.
  Future<LocationAccess> prepare() async {
    if (_state != RecorderState.idle) return LocationAccess.granted;
    final access = await _location.requestAccess();
    if (access != LocationAccess.granted) return access;
    if (_state != RecorderState.idle) return access;
    _state = RecorderState.ready;
    _listen();
    notifyListeners();
    return access;
  }

  void _listen() {
    _gpsError = null;
    _sub ??= _location.track().listen(
      _onFix,
      onError: (Object e) {
        _gpsError = e;
        notifyListeners();
      },
    );
  }

  /// Stops the GPS when the user leaves without starting.
  void release() {
    if (_state != RecorderState.ready) return;
    _stopListening();
    _state = RecorderState.idle;
    notifyListeners();
  }

  void start() {
    if (_state != RecorderState.ready) return;
    _track.clear();
    _meters = 0;
    _banked = Duration.zero;
    _since = _clock();
    _newStretch = true;
    _state = RecorderState.recording;
    // Begin at the user's current spot if we already know it.
    if (_lastFix case final f? when f.accuracy <= maxAccuracy) _add(f);
    notifyListeners();
  }

  void pause() {
    if (_state != RecorderState.recording) return;
    _banked = elapsed;
    _since = null;
    _state = RecorderState.paused;
    notifyListeners();
  }

  void resume() {
    if (_state != RecorderState.paused) return;
    _since = _clock();
    _newStretch = true;
    _state = RecorderState.recording;
    notifyListeners();
  }

  /// Stops recording and builds the workout. Null if nothing was
  /// recorded (no movement); recording is then discarded.
  Workout? finish() {
    if (!isActive) return _result;
    final moving = elapsed;
    _banked = moving;
    _since = null;
    _stopListening();
    if (_track.length < 2 || _meters < 10) {
      _reset();
      return null;
    }
    _result = Workout.recorded(
      activity: _activity,
      moving: moving,
      meters: _meters,
      route: WorkoutRoute.fromTrack(_track),
    );
    _state = RecorderState.finished;
    notifyListeners();
    return _result;
  }

  /// Throws away the recording.
  void discard() {
    _stopListening();
    _reset();
  }

  void _reset() {
    _track.clear();
    _meters = 0;
    _banked = Duration.zero;
    _since = null;
    _result = null;
    _lastFix = null;
    _state = RecorderState.idle;
    notifyListeners();
  }

  void _stopListening() {
    _sub?.cancel();
    _sub = null;
  }

  void _onFix(LocationFix f) {
    _lastFix = f;
    _gpsError = null;
    if (_state == RecorderState.recording && f.accuracy <= maxAccuracy) {
      _add(f);
    }
    notifyListeners();
  }

  void _add(LocationFix f) {
    final point = RoutePoint(f.lat, f.lng);
    final now = elapsed;
    if (_track.isEmpty || _newStretch) {
      _newStretch = false;
      _track.add(
        TrackPoint(
          point: point,
          elapsed: now,
          distanceMeters: _meters,
          altitude: f.altitude,
        ),
      );
      return;
    }
    final last = _track.last;
    final step = distanceBetween(last.point, point);
    if (step < math.max(minStep, f.accuracy / 4)) return;
    final secs = (now - last.elapsed).inMilliseconds / 1000;
    if (secs > 0 && step / secs > maxSpeed) return;
    _meters += step;
    _track.add(
      TrackPoint(
        point: point,
        elapsed: now,
        distanceMeters: _meters,
        altitude: f.altitude,
      ),
    );
  }

  @override
  void dispose() {
    _stopListening();
    super.dispose();
  }
}
