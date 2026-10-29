import 'dart:math' as math;

import 'model_utils.dart';

enum PlayCategory {
  offense('Offense'),
  defense('Defense'),
  pull('Pull'),
  endzone('Endzone');

  const PlayCategory(this.label);
  final String label;
}

enum ElementKind { offense, defense, disc, cone }

enum ArrowKind { cut, throw_ }

/// A point on the field, normalized to 0–1 in both axes so diagrams scale to
/// any canvas size. x runs along the field width, y along its length.
class FieldPoint {
  const FieldPoint(this.x, this.y);

  final double x;
  final double y;

  factory FieldPoint.fromMap(Map<String, dynamic> map) => FieldPoint(
    (map['x'] as num?)?.toDouble() ?? 0,
    (map['y'] as num?)?.toDouble() ?? 0,
  );

  Map<String, dynamic> toMap() => {'x': x, 'y': y};

  @override
  bool operator ==(Object other) =>
      other is FieldPoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);
}

class PlayElement {
  const PlayElement({
    required this.id,
    required this.kind,
    required this.position,
    this.label = '',
  });

  final String id;
  final ElementKind kind;
  final FieldPoint position;
  final String label;

  PlayElement copyWith({FieldPoint? position, String? label}) => PlayElement(
    id: id,
    kind: kind,
    position: position ?? this.position,
    label: label ?? this.label,
  );

  factory PlayElement.fromMap(Map<String, dynamic> map) => PlayElement(
    id: map['id'] as String,
    kind: enumByName(ElementKind.values, map['kind'], ElementKind.offense),
    position: FieldPoint.fromMap(Map<String, dynamic>.from(map['position'])),
    label: map['label'] as String? ?? '',
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'kind': kind.name,
    'position': position.toMap(),
    'label': label,
  };
}

class PlayArrow {
  const PlayArrow({required this.id, required this.kind, required this.points});

  final String id;
  final ArrowKind kind;
  final List<FieldPoint> points;

  factory PlayArrow.fromMap(Map<String, dynamic> map) => PlayArrow(
    id: map['id'] as String,
    kind: enumByName(ArrowKind.values, map['kind'], ArrowKind.cut),
    points: [
      for (final p in (map['points'] as List? ?? const []))
        FieldPoint.fromMap(Map<String, dynamic>.from(p)),
    ],
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'kind': kind.name,
    'points': [for (final p in points) p.toMap()],
  };
}

/// One beat of an animated play. Elements listed in [paths] move during the
/// step; everyone else holds position.
class PlayStep {
  const PlayStep({required this.id, this.note = '', this.paths = const {}});

  final String id;

  /// Caption shown while the step plays, e.g. "Break-side swing".
  final String note;

  /// Element id → waypoints after its starting position. The last point is
  /// where the element ends the step; the start is wherever the previous
  /// step left it, so editing the setup never leaves a path dangling.
  final Map<String, List<FieldPoint>> paths;

  PlayStep copyWith({String? note, Map<String, List<FieldPoint>>? paths}) =>
      PlayStep(id: id, note: note ?? this.note, paths: paths ?? this.paths);

  factory PlayStep.fromMap(Map<String, dynamic> map) => PlayStep(
    id: map['id'] as String? ?? '',
    note: map['note'] as String? ?? '',
    paths: {
      for (final e in ((map['paths'] as Map?) ?? const {}).entries)
        '${e.key}': [
          for (final p in (e.value as List? ?? const []))
            FieldPoint.fromMap(Map<String, dynamic>.from(p)),
        ],
    },
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'note': note,
    'paths': {
      for (final e in paths.entries)
        e.key: [for (final p in e.value) p.toMap()],
    },
  };
}

class Play {
  const Play({
    required this.id,
    required this.name,
    this.category = PlayCategory.offense,
    this.notes = '',
    this.elements = const [],
    this.arrows = const [],
    this.steps = const [],
    this.updatedAt,
    this.updatedBy,
  });

  /// Empty id means the play has not been saved yet.
  final String id;
  final String name;
  final PlayCategory category;
  final String notes;
  final List<PlayElement> elements;
  final List<PlayArrow> arrows;

  /// Animation beats after the setup ([elements] positions). Empty for a
  /// static diagram.
  final List<PlayStep> steps;
  final DateTime? updatedAt;
  final String? updatedBy;

  bool get isNew => id.isEmpty;

  Play copyWith({
    String? id,
    String? name,
    PlayCategory? category,
    String? notes,
    List<PlayElement>? elements,
    List<PlayArrow>? arrows,
    List<PlayStep>? steps,
  }) => Play(
    id: id ?? this.id,
    name: name ?? this.name,
    category: category ?? this.category,
    notes: notes ?? this.notes,
    elements: elements ?? this.elements,
    arrows: arrows ?? this.arrows,
    steps: steps ?? this.steps,
    updatedAt: updatedAt,
    updatedBy: updatedBy,
  );

  factory Play.fromMap(String id, Map<String, dynamic> map) => Play(
    id: id,
    name: map['name'] as String? ?? '',
    category: enumByName(
      PlayCategory.values,
      map['category'],
      PlayCategory.offense,
    ),
    notes: map['notes'] as String? ?? '',
    elements: [
      for (final e in (map['elements'] as List? ?? const []))
        PlayElement.fromMap(Map<String, dynamic>.from(e)),
    ],
    arrows: [
      for (final a in (map['arrows'] as List? ?? const []))
        PlayArrow.fromMap(Map<String, dynamic>.from(a)),
    ],
    steps: [
      for (final st in (map['steps'] as List? ?? const []))
        PlayStep.fromMap(Map<String, dynamic>.from(st)),
    ],
    updatedAt: parseDate(map['updatedAt']),
    updatedBy: map['updatedBy'] as String?,
  );

  Map<String, dynamic> toMap() => {
    'name': name,
    'category': category.name,
    'notes': notes,
    'elements': [for (final e in elements) e.toMap()],
    'arrows': [for (final a in arrows) a.toMap()],
    'steps': [for (final st in steps) st.toMap()],
  };

  // ---- Animation timeline ----------------------------------------------
  //
  // Time t runs from 0 (setup) to steps.length; t in [k, k + 1] plays
  // steps[k].

  /// Element id → position once [step] steps have played (0 = setup).
  Map<String, FieldPoint> positionsAfter(int step) {
    final pos = {for (final e in elements) e.id: e.position};
    for (final st in steps.take(step)) {
      for (final e in st.paths.entries) {
        if (pos.containsKey(e.key) && e.value.isNotEmpty) {
          pos[e.key] = e.value.last;
        }
      }
    }
    return pos;
  }

  /// Full path (start included) [elementId] travels during steps[step].
  List<FieldPoint> pathIn(int step, String elementId) {
    final waypoints = steps[step].paths[elementId];
    final start = positionsAfter(step)[elementId];
    if (waypoints == null || start == null) return const [];
    return [start, ...waypoints];
  }

  /// Element id → position at time [t], easing each step in and out.
  Map<String, FieldPoint> positionsAt(double t) {
    if (steps.isEmpty || t <= 0) return positionsAfter(0);
    if (t >= steps.length) return positionsAfter(steps.length);
    final k = t.floor();
    final f = _easeInOut(t - k);
    final pos = positionsAfter(k);
    for (final id in steps[k].paths.keys) {
      final path = pathIn(k, id);
      if (path.length > 1) pos[id] = pointAlong(path, f);
    }
    return pos;
  }

  /// [elements] moved to their positions at time [t].
  List<PlayElement> elementsAt(double t) {
    final pos = positionsAt(t);
    return [for (final e in elements) e.copyWith(position: pos[e.id])];
  }

  static double _easeInOut(double x) =>
      x < 0.5 ? 4 * x * x * x : 1 - math.pow(-2 * x + 2, 3) / 2;

  /// Point at fraction [f] (0–1) of the arc length of [path].
  static FieldPoint pointAlong(List<FieldPoint> path, double f) {
    if (path.length == 1 || f <= 0) return path.first;
    if (f >= 1) return path.last;
    double dist(FieldPoint a, FieldPoint b) =>
        math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));
    var total = 0.0;
    for (var i = 1; i < path.length; i++) {
      total += dist(path[i - 1], path[i]);
    }
    if (total == 0) return path.last;
    var remaining = total * f;
    for (var i = 1; i < path.length; i++) {
      final d = dist(path[i - 1], path[i]);
      if (remaining <= d) {
        final r = d == 0 ? 0.0 : remaining / d;
        final a = path[i - 1], b = path[i];
        return FieldPoint(a.x + (b.x - a.x) * r, a.y + (b.y - a.y) * r);
      }
      remaining -= d;
    }
    return path.last;
  }
}
