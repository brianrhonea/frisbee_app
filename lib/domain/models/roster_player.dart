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
    this.onUsau,
    this.paid = false,
  });

  final String id;
  final String name;
  final int? number;
  final PlayerPosition position;

  /// Linked app account, if this player has joined the team.
  final String? userId;

  /// Whether the player is on the linked USA Ultimate roster as of the last
  /// sync; null if never synced.
  final bool? onUsau;

  /// Marked by an admin; USA Ultimate doesn't publish payment status.
  final bool paid;

  /// On the USA Ultimate roster and paid.
  bool get confirmed => (onUsau ?? false) && paid;

  RosterPlayer copyWith({
    int? number,
    PlayerPosition? position,
    bool? onUsau,
    bool? paid,
  }) => RosterPlayer(
    id: id,
    name: name,
    number: number ?? this.number,
    position: position ?? this.position,
    userId: userId,
    onUsau: onUsau ?? this.onUsau,
    paid: paid ?? this.paid,
  );

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
        onUsau: map['onUsau'] as bool?,
        paid: map['paid'] as bool? ?? false,
      );

  Map<String, dynamic> toMap() => {
    'name': name,
    'number': number,
    'position': position.name,
    'userId': userId,
    'onUsau': onUsau,
    'paid': paid,
  };
}
