import 'model_utils.dart';

/// One of the ranking lists published by USA Ultimate,
/// e.g. "Club Mixed" or "College Women".
class RankingDivision {
  const RankingDivision({
    required this.key,
    required this.label,
    required this.entries,
    this.sourceUrl = '',
    this.updatedAt,
  });

  final String key;
  final String label;
  final List<RankingEntry> entries;
  final String sourceUrl;
  final DateTime? updatedAt;

  factory RankingDivision.fromMap(String key, Map<String, dynamic> map) =>
      RankingDivision(
        key: key,
        label: map['label'] as String? ?? key,
        sourceUrl: map['sourceUrl'] as String? ?? '',
        updatedAt: parseDate(map['updatedAt']),
        entries: [
          for (final e in (map['entries'] as List? ?? const []))
            RankingEntry.fromMap(Map<String, dynamic>.from(e)),
        ],
      );
}

class RankingEntry {
  const RankingEntry({
    required this.rank,
    required this.teamName,
    this.rating,
    this.wins,
    this.losses,
    this.region = '',
    this.teamUrl = '',
  });

  final int rank;
  final String teamName;
  final double? rating;
  final int? wins;
  final int? losses;
  final String region;
  final String teamUrl;

  String get record => (wins == null || losses == null) ? '—' : '$wins-$losses';

  factory RankingEntry.fromMap(Map<String, dynamic> map) => RankingEntry(
    rank: (map['rank'] as num?)?.toInt() ?? 0,
    teamName: map['teamName'] as String? ?? '',
    rating: (map['rating'] as num?)?.toDouble(),
    wins: (map['wins'] as num?)?.toInt(),
    losses: (map['losses'] as num?)?.toInt(),
    region: map['region'] as String? ?? '',
    teamUrl: map['teamUrl'] as String? ?? '',
  );
}
