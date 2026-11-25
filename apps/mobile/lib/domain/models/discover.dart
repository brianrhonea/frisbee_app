// What Discover and the Learn guide show beyond the app's own documents:
// team spots left on tournament lists (F10), public team events (F29) and
// reading progress (F9). Mirrors packages/shared/src/discover.ts, checked
// by test/shared_fixtures/discover_fixtures_test.dart.

import 'team.dart' show Division;
import 'team_event.dart';

/// Team spots in an event open for registration: [left] of [cap] across
/// its divisions (each division's cap less its accepted teams). The API
/// works it out for `GET /v1/public/tournaments` (tournamentSpots).
class TournamentSpots {
  const TournamentSpots({
    required this.left,
    required this.cap,
    this.divisions = const [],
  });

  final int left;
  final int cap;

  /// Each open division's own spots (DivisionSpots in packages/shared).
  final List<DivisionSpots> divisions;

  /// What a card shows: one line per division when there are two or more
  /// ("Mixed: 3 left", "Open: full · waitlist"), else [label] (spotsLines).
  List<String> get lines => divisions.length < 2
      ? [label]
      : [
          for (final d in divisions)
            '${d.division.label}: '
                '${d.left <= 0 ? 'full · waitlist' : '${d.left} left'}',
        ];

  /// No spots left: teams can still apply to the waitlist.
  bool get isFull => left <= 0;

  /// "3 spots left", "1 spot left" or "Full · waitlist" (spotsLabel).
  String get label {
    if (isFull) return 'Full · waitlist';
    return '$left ${left == 1 ? 'spot' : 'spots'} left';
  }

  /// A list card's `spots`, or null when it has none.
  static TournamentSpots? fromJson(Object? json) {
    if (json is! Map) return null;
    final left = json['left'];
    final cap = json['cap'];
    if (left is! num || cap is! num) return null;
    final each = json['divisions'];
    return TournamentSpots(
      left: left.toInt(),
      cap: cap.toInt(),
      divisions: [
        if (each is List)
          for (final d in each) ?DivisionSpots.fromJson(d),
      ],
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TournamentSpots &&
      other.left == left &&
      other.cap == cap &&
      other.lines.join('|') == lines.join('|');

  @override
  int get hashCode => Object.hash(left, cap, lines.join('|'));
}

/// One division's spots: its cap less its accepted teams.
class DivisionSpots {
  const DivisionSpots({
    required this.division,
    required this.left,
    required this.cap,
  });

  final Division division;
  final int left;
  final int cap;

  static DivisionSpots? fromJson(Object? json) {
    if (json is! Map) return null;
    final division = Division.values.asNameMap()[json['division']];
    final left = json['left'];
    final cap = json['cap'];
    if (division == null || left is! num || cap is! num) return null;
    return DivisionSpots(
      division: division,
      left: left.toInt(),
      cap: cap.toInt(),
    );
  }
}

/// A public team event (a pickup game, a practice open to all) from
/// `GET /v1/public/events`, as Discover lists it.
class PublicTeamEvent {
  const PublicTeamEvent({
    required this.id,
    required this.teamId,
    required this.teamName,
    required this.title,
    required this.type,
    this.startsAt,
    this.endsAt,
    this.location = '',
  });

  final String id;
  final String teamId;
  final String teamName;
  final String title;

  /// Null for a type this build doesn't know.
  final EventType? type;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final String location;

  bool get isPickup => type == EventType.pickup;

  static PublicTeamEvent? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final teamId = json['teamId'];
    if (id is! String || teamId is! String || id.isEmpty || teamId.isEmpty) {
      return null;
    }
    DateTime? date(Object? v) =>
        v is String ? DateTime.tryParse(v)?.toLocal() : null;
    final type = json['type'];
    return PublicTeamEvent(
      id: id,
      teamId: teamId,
      teamName: json['teamName'] is String ? json['teamName'] as String : '',
      title: json['title'] is String ? json['title'] as String : '',
      type: EventType.values.where((t) => t.name == type).firstOrNull,
      startsAt: date(json['startsAt']),
      endsAt: date(json['endsAt']),
      location: json['location'] is String ? json['location'] as String : '',
    );
  }
}

/// How long the end of a lesson must stay on screen before it counts as
/// read (learnReadAfterMs), so scrolling past doesn't count.
const learnReadAfter = Duration(milliseconds: 2000);

/// "3 of 12 read" (learnProgressLabel).
String learnProgressLabel(int read, int total) => '$read of $total read';
