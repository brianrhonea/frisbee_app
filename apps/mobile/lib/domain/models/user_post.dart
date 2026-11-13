import 'chat.dart';
import 'model_utils.dart';
import 'team_event.dart';
import 'team_post.dart';
import 'workout.dart';

enum UserPostKind { text, workout, event, repost }

/// An event shared in a post. A copy of its details, since the author's
/// followers usually can't open the event itself (a personal event, or a
/// team they aren't on).
class SharedEvent {
  const SharedEvent({
    required this.eventId,
    required this.title,
    required this.startsAt,
    this.type = EventType.other,
    this.endsAt,
    this.location = '',
    this.teamId,
    this.teamName,
  });

  /// [event] on [teamId]'s schedule (named [teamName]), or the author's own.
  factory SharedEvent.of(TeamEvent event, {String? teamId, String? teamName}) =>
      SharedEvent(
        eventId: event.id,
        title: event.title,
        type: event.type,
        startsAt: event.startsAt,
        endsAt: event.endsAt,
        location: event.location,
        teamId: teamId,
        teamName: teamName,
      );

  final String eventId;
  final String title;
  final EventType type;
  final DateTime startsAt;
  final DateTime? endsAt;
  final String location;

  /// The team whose schedule it's on; null for the author's own schedule.
  final String? teamId;
  final String? teamName;

  /// As an event, for the schedule's date and time helpers.
  TeamEvent get asEvent => TeamEvent(
    id: eventId,
    title: title,
    type: type,
    startsAt: startsAt,
    endsAt: endsAt,
    location: location,
  );

  static SharedEvent? fromMap(Map<String, dynamic> map) {
    final startsAt = parseDate(map['startsAt']);
    final id = map['eventId'] as String? ?? '';
    if (startsAt == null || id.isEmpty) return null;
    return SharedEvent(
      eventId: id,
      title: map['title'] as String? ?? '',
      type: EventType.values.asNameMap()[map['type']] ?? EventType.other,
      startsAt: startsAt,
      endsAt: parseDate(map['endsAt']),
      location: map['location'] as String? ?? '',
      teamId: map['teamId'] as String?,
      teamName: map['teamName'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'eventId': eventId,
    'title': title,
    'type': type.name,
    'startsAt': startsAt,
    'endsAt': ?endsAt,
    if (location.isNotEmpty) 'location': location,
    'teamId': ?teamId,
    'teamName': ?teamName,
  };
}

/// The post a repost shares, and who wrote it.
class RepostOf {
  const RepostOf({
    required this.postId,
    required this.authorId,
    this.authorName = '',
  });

  final String postId;
  final String authorId;
  final String authorName;

  static RepostOf? fromMap(Map<String, dynamic> map) {
    final id = map['postId'] as String? ?? '';
    if (id.isEmpty) return null;
    return RepostOf(
      postId: id,
      authorId: map['authorId'] as String? ?? '',
      authorName: map['authorName'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
    'postId': postId,
    'authorId': authorId,
    'authorName': authorName,
  };
}

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
    this.event,
    this.repostOf,
    this.likedBy = const [],
    this.repostedBy = const [],
    this.commentCount = 0,
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

  /// Set for a shared event.
  final SharedEvent? event;

  /// Set when this post reposts someone else's post: [body] is the
  /// reposter's note, and the original is shown inside it.
  final RepostOf? repostOf;

  /// Who liked it, and who reposted it. Each person adds or removes only
  /// themselves (firestore.rules); the post's author doesn't edit these.
  final List<String> likedBy;
  final List<String> repostedBy;

  /// Kept by the `follows-commentCount` Cloud Function; nobody writes it
  /// from the app.
  final int commentCount;

  int get likeCount => likedBy.length;
  int get repostCount => repostedBy.length;

  bool get isRepost => repostOf != null;

  /// The post a repost shares, or this one.
  String get originalId => repostOf?.postId ?? id;

  /// The id of [uid]'s repost of post [originalId]: one per person, so a
  /// post can't be reposted twice and the repost is found without a query.
  static String repostId(String originalId, String uid) =>
      'r_${originalId}_$uid';

  /// A repost of [original] (or of what it reposts) with [note].
  static UserPost repost(UserPost original, {String note = ''}) => UserPost(
    id: '',
    body: note.trim(),
    repostOf:
        original.repostOf ??
        RepostOf(
          postId: original.id,
          authorId: original.authorId,
          authorName: original.authorName,
        ),
  );

  /// A tournament the post is about (a FollowTarget key), so that
  /// tournament's followers see it too.
  final String? tournamentKey;
  final String? tournamentName;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isNew => id.isEmpty;
  UserPostKind get kind => repostOf != null
      ? UserPostKind.repost
      : workout != null
      ? UserPostKind.workout
      : event != null
      ? UserPostKind.event
      : UserPostKind.text;

  /// Text, a photo, a workout, an event or a repost.
  bool get hasContent =>
      body.trim().isNotEmpty ||
      images.isNotEmpty ||
      workout != null ||
      event != null ||
      repostOf != null;

  bool get edited =>
      createdAt != null &&
      updatedAt != null &&
      updatedAt!.difference(createdAt!).inMinutes >= 1;

  UserPost copyWith({
    String? body,
    List<String>? links,
    List<ChatAttachment>? images,
    Workout? Function()? workout,
    SharedEvent? Function()? event,
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
    event: event == null ? this.event : event(),
    repostOf: repostOf,
    likedBy: likedBy,
    repostedBy: repostedBy,
    commentCount: commentCount,
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
    event: switch (map['event']) {
      final Map<dynamic, dynamic> e when map['kind'] == 'event' =>
        SharedEvent.fromMap(Map<String, dynamic>.from(e)),
      _ => null,
    },
    repostOf: switch (map['repostOf']) {
      final Map<dynamic, dynamic> r when map['kind'] == 'repost' =>
        RepostOf.fromMap(Map<String, dynamic>.from(r)),
      _ => null,
    },
    likedBy: [for (final u in (map['likedBy'] as List?) ?? const []) '$u'],
    repostedBy: [
      for (final u in (map['repostedBy'] as List?) ?? const []) '$u',
    ],
    commentCount: switch (map['commentCount']) {
      final num n when n > 0 => n.toInt(),
      _ => 0,
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
    'event': event?.toMap(),
    'repostOf': repostOf?.toMap(),
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
