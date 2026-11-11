import 'dart:math' as math;

/// Miles or kilometres, for showing distances, paces and splits.
enum DistanceUnit {
  mi('mi', 1609.344),
  km('km', 1000);

  const DistanceUnit(this.label, this.meters);
  final String label;

  /// Metres in one unit.
  final double meters;

  /// Miles where people measure roads in miles (US, UK, Liberia, Myanmar),
  /// kilometres elsewhere.
  static DistanceUnit forCountry(String? countryCode) =>
      switch (countryCode?.toUpperCase()) {
        'US' || 'GB' || 'LR' || 'MM' => mi,
        _ => km,
      };
}

/// A point on a route.
class RoutePoint {
  const RoutePoint(this.lat, this.lng);

  final double lat;
  final double lng;

  @override
  bool operator ==(Object other) =>
      other is RoutePoint && other.lat == lat && other.lng == lng;

  @override
  int get hashCode => Object.hash(lat, lng);

  @override
  String toString() => 'RoutePoint($lat, $lng)';
}

/// One GPS fix kept while recording: where, how far along, and how much
/// moving time had passed (pauses don't count).
class TrackPoint {
  const TrackPoint({
    required this.point,
    required this.elapsed,
    required this.distanceMeters,
    this.altitude,
  });

  final RoutePoint point;
  final Duration elapsed;

  /// Distance covered from the start to here.
  final double distanceMeters;

  /// Metres above sea level, when the device knows.
  final double? altitude;
}

/// Metres between two points on the Earth's surface (haversine).
double distanceBetween(RoutePoint a, RoutePoint b) {
  const earthRadius = 6371008.8;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(b.lat - a.lat);
  final dLng = rad(b.lng - a.lng);
  final h =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(a.lat)) *
          math.cos(rad(b.lat)) *
          math.pow(math.sin(dLng / 2), 2);
  return 2 * earthRadius * math.asin(math.min(1, math.sqrt(h)));
}

/// "8:05", "1:02:03".
String formatClock(Duration d) {
  final s = d.inSeconds;
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = (s % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$sec' : '$m:$sec';
}

/// "8:32 /mi" for [seconds] taken over [meters]; null when there's no
/// distance to speak of.
String? formatPace(double seconds, double meters, DistanceUnit unit) {
  if (meters < 10 || seconds <= 0) return null;
  final perUnit = (seconds * unit.meters / meters).round();
  if (perUnit >= 100 * 60) return null;
  return '${formatClock(Duration(seconds: perUnit))} /${unit.label}';
}

/// "14.2 mph" or "22.9 km/h".
String? formatSpeed(double seconds, double meters, DistanceUnit unit) {
  if (meters < 10 || seconds <= 0) return null;
  final perHour = meters / unit.meters / (seconds / 3600);
  return '${perHour.toStringAsFixed(1)} '
      '${unit == DistanceUnit.mi ? 'mph' : 'km/h'}';
}

/// "3.12 mi", "5.2 km", "10 km": two decimals, trailing zeros dropped.
String formatDistance(double meters, DistanceUnit unit) {
  final v = meters / unit.meters;
  var text = v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
  if (text.contains('.')) {
    text = text.replaceFirst(RegExp(r'\.?0+$'), '');
  }
  return '$text ${unit.label}';
}

/// The path of a recorded run or ride, and how long each mile and each
/// kilometre took. Stored on the workout; limits match `validRoute` in
/// firestore.rules.
class WorkoutRoute {
  const WorkoutRoute({
    required this.path,
    this.splitsMi = const [],
    this.splitsKm = const [],
    this.elevationGainMeters,
  });

  /// Paths are thinned to at most this many points before saving.
  static const maxPoints = 4000;

  /// Splits for up to the longest workout allowed (Workout.maxDistanceKm).
  static const maxSplits = 1000;

  /// How much of each end [withoutEnds] hides by default.
  static const privacyMeters = 200.0;

  final List<RoutePoint> path;

  /// Seconds for each whole mile, in order. The last part-mile isn't here;
  /// it's whatever is left of the workout's time and distance.
  final List<int> splitsMi;

  /// Seconds for each whole kilometre.
  final List<int> splitsKm;
  final double? elevationGainMeters;

  List<int> splits(DistanceUnit unit) =>
      unit == DistanceUnit.mi ? splitsMi : splitsKm;

  /// Length of [path], in metres.
  double get pathMeters {
    var total = 0.0;
    for (var i = 1; i < path.length; i++) {
      total += distanceBetween(path[i - 1], path[i]);
    }
    return total;
  }

  bool get isValid =>
      path.length >= 2 &&
      path.length <= maxPoints &&
      splitsMi.length <= maxSplits &&
      splitsKm.length <= maxSplits &&
      splitsMi.every((s) => s > 0) &&
      splitsKm.every((s) => s > 0);

  /// Builds the route from what was recorded: thins the path, works out
  /// the splits and the climb.
  factory WorkoutRoute.fromTrack(List<TrackPoint> track) => WorkoutRoute(
    path: simplifyPath([for (final t in track) t.point]),
    splitsMi: splitTimes(track, DistanceUnit.mi.meters),
    splitsKm: splitTimes(track, DistanceUnit.km.meters),
    elevationGainMeters: elevationGain([for (final t in track) ?t.altitude]),
  );

  /// The same route with the first and last [meters] of the path cut, so
  /// it doesn't show where someone lives. Splits are unchanged. A route
  /// too short to trim is returned as is, since there'd be nothing left to
  /// draw.
  WorkoutRoute withoutEnds([double meters = privacyMeters]) {
    if (path.length < 2 || pathMeters <= meters * 2 + 10) return this;
    final trimmed = _trimStart(
      _trimStart(path, meters).reversed.toList(),
      meters,
    ).reversed.toList();
    return WorkoutRoute(
      path: trimmed,
      splitsMi: splitsMi,
      splitsKm: splitsKm,
      elevationGainMeters: elevationGainMeters,
    );
  }

  static List<RoutePoint> _trimStart(List<RoutePoint> p, double meters) {
    var gone = 0.0;
    for (var i = 1; i < p.length; i++) {
      final step = distanceBetween(p[i - 1], p[i]);
      if (gone + step >= meters) {
        final f = step == 0 ? 0.0 : (meters - gone) / step;
        final cut = RoutePoint(
          p[i - 1].lat + (p[i].lat - p[i - 1].lat) * f,
          p[i - 1].lng + (p[i].lng - p[i - 1].lng) * f,
        );
        return [cut, ...p.sublist(i)];
      }
      gone += step;
    }
    return [p.last];
  }

  factory WorkoutRoute.fromMap(Map<String, dynamic> map) => WorkoutRoute(
    path: decodePolyline(map['path'] as String? ?? ''),
    splitsMi: _ints(map['splitsMi']),
    splitsKm: _ints(map['splitsKm']),
    elevationGainMeters: (map['elevationGainM'] as num?)?.toDouble(),
  );

  static List<int> _ints(Object? v) => [
    for (final x in (v as List?) ?? const [])
      if (x is num) x.toInt(),
  ];

  Map<String, dynamic> toMap() => {
    'path': encodePolyline(path),
    'splitsMi': splitsMi,
    'splitsKm': splitsKm,
    if (elevationGainMeters != null)
      'elevationGainM': elevationGainMeters!.roundToDouble(),
  };
}

/// Seconds taken over each whole [unitMeters] of [track], interpolating
/// between fixes to find when each boundary was crossed.
List<int> splitTimes(List<TrackPoint> track, double unitMeters) {
  final splits = <int>[];
  var lastBoundary = 0.0;
  var next = unitMeters;
  for (var i = 1; i < track.length; i++) {
    final a = track[i - 1];
    final b = track[i];
    while (b.distanceMeters >= next && splits.length < WorkoutRoute.maxSplits) {
      final span = b.distanceMeters - a.distanceMeters;
      final f = span <= 0 ? 1.0 : (next - a.distanceMeters) / span;
      final at =
          a.elapsed.inMilliseconds +
          (b.elapsed.inMilliseconds - a.elapsed.inMilliseconds) * f;
      final secs = ((at - lastBoundary) / 1000).round();
      splits.add(math.max(1, secs));
      lastBoundary = at;
      next += unitMeters;
    }
  }
  return splits;
}

/// Metres climbed, ignoring wobbles smaller than [threshold] (GPS
/// altitude is noisy). Null when there are no altitudes, or they're all
/// zero (devices that don't measure it).
double? elevationGain(List<double> altitudes, {double threshold = 5}) {
  if (altitudes.length < 2 || altitudes.every((a) => a == 0)) return null;
  var gain = 0.0;
  var low = altitudes.first;
  var high = altitudes.first;
  var climbing = true;
  for (final a in altitudes.skip(1)) {
    if (climbing) {
      if (a > high) high = a;
      if (high - a >= threshold) {
        if (high - low >= threshold) gain += high - low;
        climbing = false;
        low = a;
      }
    } else {
      if (a < low) low = a;
      if (a - low >= threshold) {
        climbing = true;
        high = a;
      }
    }
  }
  if (climbing && high - low >= threshold) gain += high - low;
  return gain;
}

/// Thins [path] with Douglas–Peucker, dropping points within [tolerance]
/// metres of the line, loosening until at most [maxPoints] are left.
List<RoutePoint> simplifyPath(
  List<RoutePoint> path, {
  double tolerance = 2,
  int maxPoints = WorkoutRoute.maxPoints,
}) {
  if (path.length <= 2) return List.of(path);
  var t = tolerance;
  while (true) {
    final kept = _douglasPeucker(path, t);
    if (kept.length <= maxPoints) return kept;
    t *= 1.5;
  }
}

List<RoutePoint> _douglasPeucker(List<RoutePoint> path, double tolerance) {
  // Project to local metres around the first point; fine at run scale.
  final lat0 = path.first.lat * math.pi / 180;
  const mPerDeg = 111320.0;
  final xs = [for (final p in path) p.lng * mPerDeg * math.cos(lat0)];
  final ys = [for (final p in path) p.lat * mPerDeg];
  final keep = List.filled(path.length, false);
  keep[0] = keep[path.length - 1] = true;
  final stack = <(int, int)>[(0, path.length - 1)];
  while (stack.isNotEmpty) {
    final (s, e) = stack.removeLast();
    var maxD = 0.0;
    var at = -1;
    final dx = xs[e] - xs[s];
    final dy = ys[e] - ys[s];
    final len2 = dx * dx + dy * dy;
    for (var i = s + 1; i < e; i++) {
      double d;
      if (len2 == 0) {
        d = math.sqrt(math.pow(xs[i] - xs[s], 2) + math.pow(ys[i] - ys[s], 2));
      } else {
        final u = (((xs[i] - xs[s]) * dx + (ys[i] - ys[s]) * dy) / len2).clamp(
          0.0,
          1.0,
        );
        final px = xs[s] + u * dx - xs[i];
        final py = ys[s] + u * dy - ys[i];
        d = math.sqrt(px * px + py * py);
      }
      if (d > maxD) {
        maxD = d;
        at = i;
      }
    }
    if (at != -1 && maxD > tolerance) {
      keep[at] = true;
      stack
        ..add((s, at))
        ..add((at, e));
    }
  }
  return [
    for (var i = 0; i < path.length; i++)
      if (keep[i]) path[i],
  ];
}

/// Google's encoded polyline format, 5 decimal places (about a metre).
String encodePolyline(List<RoutePoint> path) {
  final out = StringBuffer();
  var lastLat = 0;
  var lastLng = 0;
  void write(int v) {
    var x = v < 0 ? ~(v << 1) : v << 1;
    while (x >= 0x20) {
      out.writeCharCode((0x20 | (x & 0x1f)) + 63);
      x >>= 5;
    }
    out.writeCharCode(x + 63);
  }

  for (final p in path) {
    final lat = (p.lat * 1e5).round();
    final lng = (p.lng * 1e5).round();
    write(lat - lastLat);
    write(lng - lastLng);
    lastLat = lat;
    lastLng = lng;
  }
  return out.toString();
}

List<RoutePoint> decodePolyline(String encoded) {
  final path = <RoutePoint>[];
  var i = 0;
  var lat = 0;
  var lng = 0;
  int? read() {
    var shift = 0;
    var result = 0;
    while (true) {
      if (i >= encoded.length) return null;
      final b = encoded.codeUnitAt(i++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
      if (b < 0x20) break;
    }
    return (result & 1) != 0 ? ~(result >> 1) : result >> 1;
  }

  while (i < encoded.length) {
    final dLat = read();
    final dLng = read();
    if (dLat == null || dLng == null) break;
    lat += dLat;
    lng += dLng;
    path.add(RoutePoint(lat / 1e5, lng / 1e5));
  }
  return path;
}
