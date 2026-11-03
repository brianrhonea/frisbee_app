import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/user_post.dart';
import 'package:frisbee_app/domain/models/workout.dart';
import 'package:frisbee_app/domain/models/workout_route.dart';

/// Points [meters] apart heading north from (40, -105), one every [secs].
List<TrackPoint> straightTrack(
  int count, {
  double meters = 100,
  int secs = 30,
}) {
  // One degree of latitude is about 111,195 m on the haversine sphere.
  const mPerDeg = 6371008.8 * 3.141592653589793 / 180;
  return [
    for (var i = 0; i < count; i++)
      TrackPoint(
        point: RoutePoint(40 + i * meters / mPerDeg, -105),
        elapsed: Duration(seconds: i * secs),
        distanceMeters: i * meters,
      ),
  ];
}

void main() {
  group('polyline', () {
    // Google's documented example.
    const encoded = '_p~iF~ps|U_ulLnnqC_mqNvxq`@';
    const points = [
      RoutePoint(38.5, -120.2),
      RoutePoint(40.7, -120.95),
      RoutePoint(43.252, -126.453),
    ];

    test('encodes and decodes the reference example', () {
      expect(encodePolyline(points), encoded);
      expect(decodePolyline(encoded), points);
    });

    test('ignores a truncated string', () {
      expect(decodePolyline('_p~iF~ps|U_ul'), [points.first]);
      expect(decodePolyline(''), isEmpty);
    });
  });

  test('distanceBetween is about 111 km per degree of latitude', () {
    final d = distanceBetween(const RoutePoint(0, 0), const RoutePoint(1, 0));
    expect(d, closeTo(111195, 5));
  });

  group('splitTimes', () {
    test('times each whole unit, interpolating crossings', () {
      // 100 m every 30 s: 300 s per km; the 2.5 km has two whole km.
      final track = straightTrack(26);
      expect(splitTimes(track, 1000), [300, 300]);
    });

    test('follows changes of pace', () {
      final track = [
        const TrackPoint(
          point: RoutePoint(0, 0),
          elapsed: Duration.zero,
          distanceMeters: 0,
        ),
        const TrackPoint(
          point: RoutePoint(0, 0),
          elapsed: Duration(seconds: 200),
          distanceMeters: 1000,
        ),
        const TrackPoint(
          point: RoutePoint(0, 0),
          elapsed: Duration(seconds: 700),
          distanceMeters: 2000,
        ),
      ];
      expect(splitTimes(track, 1000), [200, 500]);
      expect(splitTimes(track, 1609.344), [
        (200 + 609.344 / 1000 * 500).round(),
      ]);
    });
  });

  group('elevationGain', () {
    test('adds climbs and ignores small wobbles', () {
      expect(elevationGain([100, 102, 99, 101, 100]), 0);
      expect(elevationGain([100, 120, 110, 130]), closeTo(40, 0.01));
    });

    test('is null without altitudes', () {
      expect(elevationGain([]), isNull);
      expect(elevationGain([0, 0, 0]), isNull);
    });
  });

  test('simplifyPath drops points on a straight line', () {
    final path = [for (final t in straightTrack(50)) t.point];
    final thin = simplifyPath(path);
    expect(thin, [path.first, path.last]);
    expect(simplifyPath(path, maxPoints: 2), hasLength(2));
  });

  test('simplifyPath keeps corners', () {
    const path = [
      RoutePoint(40, -105),
      RoutePoint(40.001, -105),
      RoutePoint(40.002, -105),
      RoutePoint(40.002, -104.999),
      RoutePoint(40.002, -104.998),
    ];
    expect(simplifyPath(path), [path[0], path[2], path[4]]);
  });

  group('WorkoutRoute', () {
    test('withoutEnds trims the path, not the splits', () {
      final route = WorkoutRoute(
        path: [for (final t in straightTrack(21)) t.point],
        splitsKm: const [300, 300],
      );
      expect(route.pathMeters, closeTo(2000, 1));
      final trimmed = route.withoutEnds(200);
      expect(trimmed.pathMeters, closeTo(1600, 1));
      expect(trimmed.splitsKm, route.splitsKm);
    });

    test('withoutEnds leaves short routes alone', () {
      final route = WorkoutRoute(
        path: [for (final t in straightTrack(4)) t.point],
      );
      expect(route.withoutEnds(200).path, route.path);
    });

    test('fromTrack thins the path and splits it both ways', () {
      final route = WorkoutRoute.fromTrack(straightTrack(41));
      expect(route.path, hasLength(2));
      expect(route.splitsKm, [300, 300, 300, 300]);
      expect(route.splitsMi, hasLength(2));
      expect(route.isValid, isTrue);
    });

    test('round-trips through a workout post', () {
      final route = WorkoutRoute(
        path: const [RoutePoint(40, -105), RoutePoint(40.01, -105.01)],
        splitsMi: const [480],
        splitsKm: const [300],
        elevationGainMeters: 12.4,
      );
      final w = Workout.recorded(
        activity: WorkoutActivity.ride,
        moving: const Duration(minutes: 10, seconds: 5),
        meters: 1700,
        route: route,
      );
      expect(w.durationMinutes, 11);
      expect(w.durationSeconds, 605);
      expect(w.isValid, isTrue);
      final map = UserPost(id: '', workout: w).toEditableMap();
      expect(map['workout']['route']['path'], isA<String>());
      expect(map['workout']['route']['elevationGainM'], 12);
      final back = UserPost.fromMap('p', map).workout!;
      expect(back.activity, WorkoutActivity.ride);
      expect(back.durationSeconds, 605);
      expect(back.route!.path, route.path);
      expect(back.route!.splitsMi, [480]);
      expect(back.durationLabel, '10:05');
    });

    test('a route needs two points', () {
      const w = Workout(
        durationMinutes: 5,
        route: WorkoutRoute(path: [RoutePoint(1, 1)]),
      );
      expect(w.isValid, isFalse);
    });
  });

  group('formatting', () {
    test('clock, pace, speed and distance', () {
      expect(formatClock(const Duration(seconds: 485)), '8:05');
      expect(formatClock(const Duration(seconds: 3723)), '1:02:03');
      expect(formatPace(480, 1609.344, DistanceUnit.mi), '8:00 /mi');
      expect(formatPace(10, 5, DistanceUnit.mi), isNull);
      expect(formatSpeed(3600, 16093.44, DistanceUnit.mi), '10.0 mph');
      expect(formatDistance(5000, DistanceUnit.km), '5 km');
      expect(formatDistance(5021, DistanceUnit.mi), '3.12 mi');
    });

    test('miles in the US and UK, km elsewhere', () {
      expect(DistanceUnit.forCountry('US'), DistanceUnit.mi);
      expect(DistanceUnit.forCountry('gb'), DistanceUnit.mi);
      expect(DistanceUnit.forCountry('CA'), DistanceUnit.km);
      expect(DistanceUnit.forCountry(null), DistanceUnit.km);
    });
  });
}
