import 'model_utils.dart';

enum PlayerPosition {
  handler('Handler'),
  cutter('Cutter'),
  hybrid('Hybrid');

  const PlayerPosition(this.label);
  final String label;
}

class RosterPlayer {
  const RosterPlayer({
    required this.id,
    required this.name,
    this.number,
    this.position = PlayerPosition.hybrid,
    this.userId,
  });

  final String id;
  final String name;
  final int? number;
  final PlayerPosition position;

  /// Linked app account, if this player has joined the team.
  final String? userId;

  factory RosterPlayer.fromMap(String id, Map<String, dynamic> map) =>
      RosterPlayer(
        id: id,
        name: map['name'] as String? ?? '',
        number: (map['number'] as num?)?.toInt(),
        position: enumByName(
          PlayerPosition.values,
          map['position'],
          PlayerPosition.hybrid,
        ),
        userId: map['userId'] as String?,
      );

  Map<String, dynamic> toMap() => {
    'name': name,
    'number': number,
    'position': position.name,
    'userId': userId,
  };
}
