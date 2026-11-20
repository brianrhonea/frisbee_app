import 'model_utils.dart';

enum PlayerPosition {
  handler('Handler'),
  cutter('Cutter'),
  hybrid('Hybrid');

  const PlayerPosition(this.label);
  final String label;
}

/// Which line a player is on, set by the team's admins ("Edit lines").
/// Not a [PlayerPosition], and not a stats game's lines, which are per
/// game. `rosterLines` in packages/shared; stored as [name] on the spot
/// and written only through the API (`PUT /v1/teams/:id/roster-lines`).
enum RosterLine {
  o('O-line', 'O'),
  d('D-line', 'D'),
  both('Both lines', 'Both');

  const RosterLine(this.label, this.short);

  /// The roster's heading for the group.
  final String label;

  /// The picker's button.
  final String short;

  /// The heading for players without a line.
  static const unassignedLabel = 'Unassigned';

  static RosterLine? fromName(Object? raw) =>
      values.where((l) => l.name == raw).firstOrNull;
}

/// [players] grouped by line: O-line, D-line, Both lines, then unassigned
/// (null), each in [players]' order, empty groups left out. Empty while no
/// one has a line, so the roster shows as one list (`groupByLine` in
/// packages/shared).
List<({RosterLine? line, List<RosterPlayer> players})> groupByLine(
  List<RosterPlayer> players,
) {
  if (!players.any((p) => p.line != null)) return const [];
  return [
    for (final line in <RosterLine?>[...RosterLine.values, null])
      if (players.any((p) => p.line == line))
        (
          line: line,
          players: [
            for (final p in players)
              if (p.line == line) p,
          ],
        ),
  ];
}

class RosterPlayer {
  const RosterPlayer({
    required this.id,
    required this.name,
    this.number,
    this.position = PlayerPosition.hybrid,
    this.userId,
    this.paid = false,
    this.line,
  });

  /// Roster order: by number (no number last), then name. The website
  /// sorts the same way (sortPlayers in packages/shared/src/stats.ts).
  static int compareRoster(RosterPlayer a, RosterPlayer b) {
    final byNumber = (a.number ?? 1000).compareTo(b.number ?? 1000);
    return byNumber != 0 ? byNumber : a.name.compareTo(b.name);
  }

  final String id;
  final String name;
  final int? number;
  final PlayerPosition position;

  /// Linked app account, if this player has joined the team.
  final String? userId;

  /// Marked by an admin; only admins can read it (see [toStatusMap]).
  final bool paid;

  /// Their line, if the team assigned one. Only the API changes it;
  /// saving the spot writes it back as read, so editing keeps it.
  final RosterLine? line;

  RosterPlayer copyWith({int? number, PlayerPosition? position, bool? paid}) =>
      RosterPlayer(
        id: id,
        name: name,
        number: number ?? this.number,
        position: position ?? this.position,
        userId: userId,
        paid: paid ?? this.paid,
        line: line,
      );

  /// [map] is the roster entry every member can read; [status] is the
  /// admin-only status from [toStatusMap], if the reader may see it.
  factory RosterPlayer.fromMap(
    String id,
    Map<String, dynamic> map, {
    Map<String, dynamic>? status,
  }) => RosterPlayer(
    id: id,
    name: map['name'] as String? ?? '',
    number: (map['number'] as num?)?.toInt(),
    position: enumByName(
      PlayerPosition.values,
      map['position'],
      PlayerPosition.hybrid,
    ),
    userId: map['userId'] as String?,
    paid: status?['paid'] as bool? ?? false,
    line: RosterLine.fromName(map['line']),
  );

  /// Fields every team member may read.
  Map<String, dynamic> toMap() => {
    'name': name,
    'number': number,
    'position': position.name,
    'userId': userId,
    // Kept as read: the rules let a client keep or drop it, never set it.
    if (line != null) 'line': line!.name,
  };

  /// Fields only team admins may read, stored apart from [toMap].
  Map<String, dynamic> toStatusMap() => {'paid': paid};
}
