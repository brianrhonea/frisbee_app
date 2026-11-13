import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/workout_recorder/workout_recorder.dart';
import 'package:frisbee_app/data/services/location_service.dart';
import 'package:frisbee_app/domain/models/workout.dart';

class FakeLocationService implements LocationService {
  LocationAccess access = LocationAccess.granted;
  StreamController<LocationFix>? fixes;
  var listening = false;

  @override
  Future<LocationAccess> requestAccess() async => access;

  @override
  Stream<LocationFix> track() {
    fixes = StreamController<LocationFix>(
      onListen: () => listening = true,
      onCancel: () => listening = false,
    );
    return fixes!.stream;
  }

  @override
  Future<void> openSettings(LocationAccess access) async {}
}

/// About 1.11 m of latitude per 0.00001°.
const _deg100m = 100 / 111195;

void main() {
  late FakeLocationService location;
  late DateTime now;
  late WorkoutRecorder recorder;

  setUp(() {
    location = FakeLocationService();
    now = DateTime(2026, 11, 2, 7);
    recorder = WorkoutRecorder(location: location, clock: () => now);
  });

  tearDown(() => recorder.dispose());

  Future<void> fix(double north, {double accuracy = 5}) async {
    location.fixes!.add(
      LocationFix(
        lat: 40 + north * _deg100m,
        lng: -105,
        accuracy: accuracy,
        time: now,
        altitude: 1600,
      ),
    );
    await Future<void>.delayed(Duration.zero);
  }

  test('does nothing without permission', () async {
    location.access = LocationAccess.denied;
    expect(await recorder.prepare(), LocationAccess.denied);
    expect(recorder.state, RecorderState.idle);
    expect(location.fixes, isNull);
  });

  test('records distance and moving time, then builds the workout', () async {
    await recorder.prepare();
    expect(recorder.state, RecorderState.ready);
    await fix(0);
    recorder.selectActivity(WorkoutActivity.ride);
    recorder.start();
    for (var i = 1; i <= 20; i++) {
      now = now.add(const Duration(seconds: 30));
      await fix(i.toDouble());
    }
    expect(recorder.meters, closeTo(2000, 2));
    expect(recorder.elapsed, const Duration(minutes: 10));
    expect(recorder.currentPace(), closeTo(0.3, 0.01));

    final w = recorder.finish()!;
    expect(recorder.state, RecorderState.finished);
    expect(location.listening, isFalse);
    expect(w.activity, WorkoutActivity.ride);
    expect(w.durationSeconds, 600);
    expect(w.distanceKm, closeTo(2, 0.01));
    expect(w.route!.splitsKm, [300, 300]);
    expect(w.isValid, isTrue);
  });

  test('pausing stops the clock and skips ground covered meanwhile', () async {
    await recorder.prepare();
    await fix(0);
    recorder.start();
    now = now.add(const Duration(minutes: 1));
    await fix(1);
    recorder.pause();
    now = now.add(const Duration(minutes: 5));
    await fix(5);
    expect(recorder.elapsed, const Duration(minutes: 1));
    recorder.resume();
    await fix(6);
    now = now.add(const Duration(minutes: 1));
    await fix(7);
    expect(recorder.elapsed, const Duration(minutes: 2));
    expect(recorder.meters, closeTo(200, 1));
  });

  test('ignores vague fixes, jitter and jumps', () async {
    await recorder.prepare();
    await fix(0);
    recorder.start();
    now = now.add(const Duration(seconds: 30));
    await fix(1, accuracy: 80);
    await fix(0.01);
    expect(recorder.meters, 0);
    expect(recorder.weakSignal, isFalse);
    now = now.add(const Duration(seconds: 1));
    await fix(50); // 5 km in a second
    expect(recorder.meters, 0);
    await fix(1, accuracy: 80);
    expect(recorder.weakSignal, isTrue);
  });

  test('finishing without moving discards it', () async {
    await recorder.prepare();
    await fix(0);
    recorder.start();
    now = now.add(const Duration(minutes: 1));
    expect(recorder.finish(), isNull);
    expect(recorder.state, RecorderState.idle);
  });

  test(
    'leaving before starting turns the GPS off; a recording stays on',
    () async {
      await recorder.prepare();
      expect(location.listening, isTrue);
      recorder.release();
      expect(location.listening, isFalse);
      expect(recorder.state, RecorderState.idle);

      await recorder.prepare();
      recorder.start();
      recorder.release();
      expect(location.listening, isTrue);
      expect(recorder.state, RecorderState.recording);
    },
  );
}
