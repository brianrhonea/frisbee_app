import 'chat.dart';
import 'model_utils.dart';
import 'team_post.dart';
import 'workout.dart';

enum UserPostKind { text, workout }

/// A post a user writes on their own profile, stored at `posts/{id}`. Any
/// signed-in user can read it; it shows in the feeds of the author's
/// followers and, when tagged, of the tournament's followers.
class UserPost {
  const UserPost({
    required this.id,
    this.authorId = '',
    this.authorName = '',
    this.authorPhotoUrl,
    this.body = '',
    this.links = const [],
    this.images = const [],
    this.workout,
    this.tournamentKey,
    this.tournamentName,
    this.createdAt,
    this.updatedAt,
  });

  static const maxBody = 5000;

  /// Empty for a post that hasn't been saved yet.
  final String id;
  final String authorId;
  final String authorName;
  final String? authorPhotoUrl;
  final String body;
  final List<String> links;
  final List<ChatAttachment> images;

  /// Set for a shared workout.
  final Workout? workout;

  /// A tournament the post is about (a FollowTarget key), so that
  /// tournament's followers see it too.
  final String? tournamentKey;
  final String? tournamentName;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isNew => id.isEmpty;
  UserPostKind get kind =>
      workout == null ? UserPostKind.text : UserPostKind.workout;

  /// Text, a photo or a workout.
  bool get hasContent =>
      body.trim().isNotEmpty || images.isNotEmpty || workout != null;

  bool get edited =>
      createdAt != null &&
      updatedAt != null &&
      updatedAt!.difference(createdAt!).inMinutes >= 1;

  UserPost copyWith({
    String? body,
    List<String>? links,
    List<ChatAttachment>? images,
    Workout? Function()? workout,
    String? Function()? tournamentKey,
    String? Function()? tournamentName,
  }) => UserPost(
    id: id,
    authorId: authorId,
    authorName: authorName,
    authorPhotoUrl: authorPhotoUrl,
    body: body ?? this.body,
    links: links ?? this.links,
    images: images ?? this.images,
    workout: workout == null ? this.workout : workout(),
    tournamentKey: tournamentKey == null ? this.tournamentKey : tournamentKey(),
    tournamentName: tournamentName == null
        ? this.tournamentName
        : tournamentName(),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );

  factory UserPost.fromMap(String id, Map<String, dynamic> map) => UserPost(
    id: id,
    authorId: map['authorId'] as String? ?? '',
    authorName: map['authorName'] as String? ?? '',
    authorPhotoUrl: map['authorPhotoUrl'] as String?,
    body: map['body'] as String? ?? '',
    links: [for (final l in (map['links'] as List?) ?? const []) '$l'],
    images: [
      for (final a in (map['images'] as List?) ?? const [])
        if (a is Map) ChatAttachment.fromMap(Map<String, dynamic>.from(a)),
    ],
    workout: switch (map['workout']) {
      final Map<dynamic, dynamic> w when map['kind'] == 'workout' =>
        Workout.fromMap(Map<String, dynamic>.from(w)),
      _ => null,
    },
    tournamentKey: map['tournamentKey'] as String?,
    tournamentName: map['tournamentName'] as String?,
    createdAt: parseDate(map['createdAt']),
    updatedAt: parseDate(map['updatedAt']),
  );

  /// Fields the author may change. Absent optional fields are written as
  /// null so an edit can clear them.
  Map<String, dynamic> toEditableMap() => {
    'kind': kind.name,
    'body': body.trim(),
    'links': links,
    'images': [for (final i in images) i.toMap()],
    'workout': workout?.toMap(),
    'tournamentKey': tournamentKey,
    'tournamentName': tournamentName,
  };

  static int newestFirst(UserPost a, UserPost b) =>
      (b.createdAt ?? DateTime(9999)).compareTo(a.createdAt ?? DateTime(9999));

  static const maxLinks = TeamPost.maxLinks;
  static const maxImages = TeamPost.maxImages;
}

/// A post as written in the composer, plus photos not yet uploaded.
class UserPostDraft {
  const UserPostDraft({required this.post, this.newImages = const []});

  final UserPost post;
  final List<NewAttachment> newImages;
}
