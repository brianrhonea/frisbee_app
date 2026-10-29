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
  /// sync; null if never synced. Admin-only, like [paid] (see [toStatusMap]).
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
    onUsau: status?['onUsau'] as bool?,
    paid: status?['paid'] as bool? ?? false,
  );

  /// Fields every team member may read.
  Map<String, dynamic> toMap() => {
    'name': name,
    'number': number,
    'position': position.name,
    'userId': userId,
  };

  /// Fields only team admins may read, stored apart from [toMap].
  Map<String, dynamic> toStatusMap() => {'onUsau': onUsau, 'paid': paid};
}
