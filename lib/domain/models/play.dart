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

class Play {
  const Play({
    required this.id,
    required this.name,
    this.category = PlayCategory.offense,
    this.notes = '',
    this.elements = const [],
    this.arrows = const [],
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
  }) => Play(
    id: id ?? this.id,
    name: name ?? this.name,
    category: category ?? this.category,
    notes: notes ?? this.notes,
    elements: elements ?? this.elements,
    arrows: arrows ?? this.arrows,
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
    updatedAt: parseDate(map['updatedAt']),
    updatedBy: map['updatedBy'] as String?,
  );

  Map<String, dynamic> toMap() => {
    'name': name,
    'category': category.name,
    'notes': notes,
    'elements': [for (final e in elements) e.toMap()],
    'arrows': [for (final a in arrows) a.toMap()],
  };
}
