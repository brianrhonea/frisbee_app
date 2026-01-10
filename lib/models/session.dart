class PracticeSession {
  final String id;
  final String planId;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int completedMinutes;

  const PracticeSession({
    required this.id,
    required this.planId,
    required this.startedAt,
    required this.endedAt,
    required this.completedMinutes,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'planId': planId,
        'startedAt': startedAt.toIso8601String(),
        'endedAt': endedAt?.toIso8601String(),
        'completedMinutes': completedMinutes,
      };

  static PracticeSession fromMap(Map map) => PracticeSession(
        id: map['id'],
        planId: map['planId'],
        startedAt: DateTime.parse(map['startedAt']),
        endedAt: map['endedAt'] == null ? null : DateTime.parse(map['endedAt']),
        completedMinutes: map['completedMinutes'] ?? 0,
      );
}
