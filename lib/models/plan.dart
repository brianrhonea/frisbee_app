class PlanItem {
  final String drillId;
  final int minutes;

  const PlanItem({required this.drillId, required this.minutes});

  Map<String, dynamic> toMap() => {'drillId': drillId, 'minutes': minutes};
  static PlanItem fromMap(Map map) =>
      PlanItem(drillId: map['drillId'], minutes: map['minutes']);
}

class PracticePlan {
  final String id;
  final String title;
  final List<PlanItem> items;

  const PracticePlan({
    required this.id,
    required this.title,
    required this.items,
  });

  int get totalMinutes => items.fold(0, (sum, i) => sum + i.minutes);

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'items': items.map((e) => e.toMap()).toList(),
      };

  static PracticePlan fromMap(Map map) => PracticePlan(
        id: map['id'],
        title: map['title'],
        items: (map['items'] as List? ?? const [])
            .map((e) => PlanItem.fromMap(Map<String, dynamic>.from(e)))
            .toList(),
      );
}
