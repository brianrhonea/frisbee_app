import 'model_utils.dart';

/// What a follow points at. Teams and community groups are both team docs,
/// so [team] covers both. [tournament] is a community group's pickup
/// tournament.
enum FollowType {
  user('Person'),
  team('Team'),
  tournament('Tournament');

  const FollowType(this.label);
  final String label;
}

/// Something that can be followed. [key] identifies it everywhere: it is
/// the follow doc's id under `users/{uid}/follows`, the `followCounts` doc
/// id, and what posts are matched on. firestore.rules and
/// functions/src/notifications/model.ts build the same keys; keep them in
/// step.
class FollowTarget {
  const FollowTarget({
    required this.type,
    required this.id,
    required this.name,
    this.groupId,
    this.photoUrl,
  });

  const FollowTarget.user(String uid, String name, {String? photoUrl})
    : this(type: FollowType.user, id: uid, name: name, photoUrl: photoUrl);

  const FollowTarget.team(String teamId, String name)
    : this(type: FollowType.team, id: teamId, name: name);

  /// A community group's tournament; [id] is the tournament id.
  const FollowTarget.tournament(
    String groupId,
    String tournamentId,
    String name,
  ) : this(
        type: FollowType.tournament,
        id: tournamentId,
        groupId: groupId,
        name: name,
      );

  final FollowType type;
  final String id;

  /// The group a [FollowType.tournament] belongs to.
  final String? groupId;
  final String name;
  final String? photoUrl;

  /// The id part of [key]: group tournaments include their group.
  String get targetId => switch (type) {
    FollowType.tournament => '${groupId}_$id',
    _ => id,
  };

  String get key => keyFor(type, targetId);

  static String keyFor(FollowType type, String targetId) =>
      '${type.name}_$targetId';

  static String userKey(String uid) => keyFor(FollowType.user, uid);
  static String teamKey(String teamId) => keyFor(FollowType.team, teamId);
  static String tournamentKey(String groupId, String tournamentId) =>
      keyFor(FollowType.tournament, '${groupId}_$tournamentId');
}

/// A user's follow, stored at `users/{uid}/follows/{key}`. [notify] turns
/// on push and in-app notifications for the target's new posts.
class Follow {
  const Follow({required this.target, this.notify = false, this.createdAt});

  static const maxNameLength = 100;

  final FollowTarget target;
  final bool notify;
  final DateTime? createdAt;

  String get key => target.key;
  FollowType get type => target.type;

  Follow copyWith({bool? notify}) => Follow(
    target: target,
    notify: notify ?? this.notify,
    createdAt: createdAt,
  );

  /// Whether [map] is a follow of a type the app still knows. Follows of
  /// USA Ultimate events (type `event`) are left over from before those
  /// were removed.
  static bool isKnown(Map<String, dynamic> map) =>
      FollowType.values.any((t) => t.name == map['type']);

  factory Follow.fromMap(Map<String, dynamic> map) {
    final type = enumByName(FollowType.values, map['type'], FollowType.user);
    final targetId = map['targetId'] as String? ?? '';
    final groupId = map['groupId'] as String?;
    // Group tournaments store `{groupId}_{tournamentId}` as the target id.
    final id = type == FollowType.tournament && groupId != null
        ? targetId.replaceFirst('${groupId}_', '')
        : targetId;
    return Follow(
      target: FollowTarget(
        type: type,
        id: id,
        groupId: groupId,
        name: map['name'] as String? ?? '',
        photoUrl: map['photoUrl'] as String?,
      ),
      notify: map['notify'] as bool? ?? false,
      createdAt: parseDate(map['createdAt']),
    );
  }

  /// Everything but `createdAt`, which the repository stamps.
  Map<String, dynamic> toMap() {
    final name = target.name.trim();
    return {
      'key': key,
      'type': type.name,
      'targetId': target.targetId,
      'groupId': ?target.groupId,
      'name': name.length > maxNameLength
          ? name.substring(0, maxNameLength)
          : name,
      if ((target.photoUrl ?? '').isNotEmpty) 'photoUrl': target.photoUrl,
      'notify': notify,
    };
  }
}

/// Someone asking to follow a private profile, at
/// `profiles/{owner}/followRequests/{uid}`. The owner accepts (which
/// creates the follow for them) or declines (deletes it).
class FollowRequest {
  const FollowRequest({
    required this.uid,
    required this.name,
    this.username,
    this.photoUrl,
    this.createdAt,
  });

  /// Who's asking.
  final String uid;
  final String name;
  final String? username;
  final String? photoUrl;
  final DateTime? createdAt;

  factory FollowRequest.fromMap(String uid, Map<String, dynamic> map) =>
      FollowRequest(
        uid: uid,
        name: map['name'] as String? ?? '',
        username: map['username'] as String?,
        photoUrl: map['photoUrl'] as String?,
        createdAt: parseDate(map['createdAt']),
      );

  /// Everything but `createdAt`, which the repository stamps.
  Map<String, dynamic> toMap() => {
    'name': name,
    'username': username,
    'photoUrl': photoUrl,
  };
}
