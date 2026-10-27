import 'model_utils.dart';

/// A tournament listed on USA Ultimate, scraped by Cloud Functions.
class Tournament {
  const Tournament({
    required this.id,
    required this.name,
    required this.url,
    this.startDate,
    this.endDate,
    this.city = '',
    this.state = '',
    this.competitionLevel = '',
    this.divisions = const [],
  });

  final String id;
  final String name;

  /// Link to the event page on USA Ultimate.
  final String url;
  final DateTime? startDate;
  final DateTime? endDate;
  final String city;
  final String state;

  /// e.g. "Club", "College", "Youth" as listed by USA Ultimate.
  final String competitionLevel;

  /// e.g. ["Mixed", "Open", "Women"].
  final List<String> divisions;

  String get location => [city, state].where((s) => s.isNotEmpty).join(', ');

  bool isUpcoming(DateTime now) {
    final end = endDate ?? startDate;
    return end == null || !end.isBefore(DateTime(now.year, now.month, now.day));
  }

  factory Tournament.fromMap(String id, Map<String, dynamic> map) => Tournament(
    id: id,
    name: map['name'] as String? ?? '',
    url: map['url'] as String? ?? '',
    startDate: parseDate(map['startDate']),
    endDate: parseDate(map['endDate']),
    city: map['city'] as String? ?? '',
    state: map['state'] as String? ?? '',
    competitionLevel: map['competitionLevel'] as String? ?? '',
    divisions: [for (final d in (map['divisions'] as List? ?? const [])) '$d'],
  );
}
