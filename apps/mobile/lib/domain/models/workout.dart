import 'model_utils.dart';
import 'workout_route.dart';

/// The kind of session a shared workout was.
enum WorkoutActivity {
  run('Run'),
  ride('Ride'),
  walk('Walk'),
  hike('Hike'),
  sprints('Sprints'),
  throwing('Throwing'),
  gym('Gym'),
  agility('Agility'),
  mobility('Mobility'),
  other('Other');

  const WorkoutActivity(this.label);
  final String label;

  /// Activities that can be recorded with GPS.
  static const tracked = [run, ride, walk, hike];

  /// Rides show speed; everything else on foot shows pace.
  bool get showsSpeed => this == ride;
}

/// One line of a workout: "Squat 3 × 5 @ 100".
class WorkoutExercise {
  const WorkoutExercise({
    required this.name,
    this.sets,
    this.reps,
    this.weight = '',
  });

  static const maxNameLength = 60;
  static const maxWeightLength = 20;

  final String name;
  final int? sets;
  final int? reps;

  /// Free text so people can write "20 kg", "BW" or "135 lb".
  final String weight;

  bool get isValid =>
      name.trim().isNotEmpty &&
      name.length <= maxNameLength &&
      weight.length <= maxWeightLength &&
      (sets == null || (sets! >= 1 && sets! <= 100)) &&
      (reps == null || (reps! >= 1 && reps! <= 1000));

  /// "3 × 5 @ 100 kg", or empty when only the name is known.
  String get detail {
    final volume = switch ((sets, reps)) {
      (final s?, final r?) => '$s × $r',
      (final s?, null) => '$s sets',
      (null, final r?) => '$r reps',
      _ => '',
    };
    final w = weight.trim();
    return [if (volume.isNotEmpty) volume, if (w.isNotEmpty) '@ $w'].join(' ');
  }

  factory WorkoutExercise.fromMap(Map<String, dynamic> map) => WorkoutExercise(
    name: map['name'] as String? ?? '',
    sets: (map['sets'] as num?)?.toInt(),
    reps: (map['reps'] as num?)?.toInt(),
    weight: map['weight'] as String? ?? '',
  );

  Map<String, dynamic> toMap() => {
    'name': name.trim(),
    if (sets != null) 'sets': sets,
    if (reps != null) 'reps': reps,
    if (weight.trim().isNotEmpty) 'weight': weight.trim(),
  };

  @override
  bool operator ==(Object other) =>
      other is WorkoutExercise &&
      other.name == name &&
      other.sets == sets &&
      other.reps == reps &&
      other.weight == weight;

  @override
  int get hashCode => Object.hash(name, sets, reps, weight);
}

/// A workout shared as a post. Limits match `validWorkout` in
/// firestore.rules; keep them in step.
class Workout {
  const Workout({
    this.activity = WorkoutActivity.run,
    this.durationMinutes = 0,
    this.durationSeconds,
    this.distanceKm,
    this.effort,
    this.exercises = const [],
    this.route,
  });

  /// A workout recorded with GPS: exact time, distance and the route.
  factory Workout.recorded({
    required WorkoutActivity activity,
    required Duration moving,
    required double meters,
    required WorkoutRoute route,
  }) {
    final secs = moving.inSeconds.clamp(1, maxMinutes * 60);
    return Workout(
      activity: activity,
      durationMinutes: (secs / 60).ceil(),
      durationSeconds: secs,
      distanceKm: meters < 10 ? null : meters / 1000,
      route: route,
    );
  }

  static const maxExercises = 20;
  static const maxMinutes = 24 * 60;
  static const maxDistanceKm = 1000.0;

  final WorkoutActivity activity;
  final int durationMinutes;

  /// Exact moving time, for recorded workouts; [durationMinutes] is this
  /// rounded up.
  final int? durationSeconds;
  final double? distanceKm;

  /// How hard it felt, 1 (easy) to 10 (max).
  final int? effort;
  final List<WorkoutExercise> exercises;

  /// The GPS route, for recorded workouts.
  final WorkoutRoute? route;

  Duration get duration =>
      Duration(seconds: durationSeconds ?? durationMinutes * 60);

  double? get meters => distanceKm == null ? null : distanceKm! * 1000;

  /// Null when valid, else why not.
  String? get problem {
    if (durationMinutes < 1 || durationMinutes > maxMinutes) {
      return 'Enter how long it took, in minutes';
    }
    if (distanceKm case final d? when d <= 0 || d > maxDistanceKm) {
      return 'Distance must be between 0 and ${maxDistanceKm.toInt()} km';
    }
    if (effort case final e? when e < 1 || e > 10) {
      return 'Effort is 1 to 10';
    }
    if (exercises.length > maxExercises) {
      return 'Up to $maxExercises exercises';
    }
    if (exercises.any((e) => !e.isValid)) {
      return 'Every exercise needs a name';
    }
    if (durationSeconds case final s? when s < 1 || s > maxMinutes * 60) {
      return 'Too long to share';
    }
    if (route case final r? when !r.isValid) {
      return 'The route is too short to share';
    }
    return null;
  }

  bool get isValid => problem == null;

  /// "1 h 15 min", "45 min"; "42:17" or "1:02:03" when recorded.
  String get durationLabel {
    if (durationSeconds != null) return formatClock(duration);
    final h = durationMinutes ~/ 60;
    final m = durationMinutes % 60;
    if (h == 0) return '$m min';
    return m == 0 ? '$h h' : '$h h $m min';
  }

  /// "3.12 mi", or null without a distance.
  String? distanceLabel([DistanceUnit unit = DistanceUnit.km]) =>
      meters == null ? null : formatDistance(meters!, unit);

  /// Average pace, "8:32 /mi", or null without a distance.
  String? paceLabel([DistanceUnit unit = DistanceUnit.km]) => meters == null
      ? null
      : formatPace(duration.inSeconds.toDouble(), meters!, unit);

  /// Average speed, "14.2 mph", or null without a distance.
  String? speedLabel([DistanceUnit unit = DistanceUnit.km]) => meters == null
      ? null
      : formatSpeed(duration.inSeconds.toDouble(), meters!, unit);

  Workout copyWith({
    WorkoutActivity? activity,
    int? durationMinutes,
    double? Function()? distanceKm,
    int? Function()? effort,
    List<WorkoutExercise>? exercises,
    WorkoutRoute? Function()? route,
  }) => Workout(
    activity: activity ?? this.activity,
    durationMinutes: durationMinutes ?? this.durationMinutes,
    durationSeconds: durationSeconds,
    distanceKm: distanceKm == null ? this.distanceKm : distanceKm(),
    effort: effort == null ? this.effort : effort(),
    exercises: exercises ?? this.exercises,
    route: route == null ? this.route : route(),
  );

  factory Workout.fromMap(Map<String, dynamic> map) => Workout(
    activity: enumByName(
      WorkoutActivity.values,
      map['activity'],
      WorkoutActivity.other,
    ),
    durationMinutes: (map['durationMinutes'] as num?)?.toInt() ?? 0,
    durationSeconds: (map['durationSeconds'] as num?)?.toInt(),
    distanceKm: (map['distanceKm'] as num?)?.toDouble(),
    effort: (map['effort'] as num?)?.toInt(),
    exercises: [
      for (final e in (map['exercises'] as List?) ?? const [])
        if (e is Map) WorkoutExercise.fromMap(Map<String, dynamic>.from(e)),
    ],
    route: switch (map['route']) {
      final Map<dynamic, dynamic> r => WorkoutRoute.fromMap(
        Map<String, dynamic>.from(r),
      ),
      _ => null,
    },
  );

  Map<String, dynamic> toMap() => {
    'activity': activity.name,
    'durationMinutes': durationMinutes,
    if (durationSeconds != null) 'durationSeconds': durationSeconds,
    if (distanceKm != null) 'distanceKm': distanceKm,
    if (effort != null) 'effort': effort,
    'exercises': [for (final e in exercises) e.toMap()],
    if (route != null) 'route': route!.toMap(),
  };
}
