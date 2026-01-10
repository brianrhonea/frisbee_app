class Drill {
  final String id;
  final String title;
  final String category;
  final int minPlayers;
  final int maxPlayers;
  final int suggestedMinutes;
  final int intensity; // 1–5
  final List<String> skills;
  final String setup;
  final String steps;
  final String coachingPoints;
  final String variations;

  const Drill({
    required this.id,
    required this.title,
    required this.category,
    required this.minPlayers,
    required this.maxPlayers,
    required this.suggestedMinutes,
    required this.intensity,
    required this.skills,
    required this.setup,
    required this.steps,
    required this.coachingPoints,
    required this.variations,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'category': category,
        'minPlayers': minPlayers,
        'maxPlayers': maxPlayers,
        'suggestedMinutes': suggestedMinutes,
        'intensity': intensity,
        'skills': skills,
        'setup': setup,
        'steps': steps,
        'coachingPoints': coachingPoints,
        'variations': variations,
      };

  static Drill fromMap(Map map) => Drill(
        id: map['id'],
        title: map['title'],
        category: map['category'],
        minPlayers: map['minPlayers'],
        maxPlayers: map['maxPlayers'],
        suggestedMinutes: map['suggestedMinutes'],
        intensity: map['intensity'],
        skills: List<String>.from(map['skills'] ?? const []),
        setup: map['setup'] ?? '',
        steps: map['steps'] ?? '',
        coachingPoints: map['coachingPoints'] ?? '',
        variations: map['variations'] ?? '',
      );
}
