import 'chat.dart';
import 'model_utils.dart';

/// An announcement on a team's home page. Owners, coaches and captains
/// post; [isPublic] posts are shown to anyone who finds the team, the rest
/// to members only. Besides text, a post can have a [location], [links]
/// and photos ([images], in Cloud Storage).
class TeamPost {
  const TeamPost({
    required this.id,
    this.body = '',
    this.title = '',
    this.location = '',
    this.links = const [],
    this.images = const [],
    this.isPublic = false,
    this.tournamentKey,
    this.authorId = '',
    this.authorName = '',
    this.createdAt,
    this.updatedAt,
    this.pinnedAt,
    this.commentCount = 0,
  });

  /// Limits firestore.rules enforces too; keep them in step.
  static const maxLinks = 5;
  static const maxImages = 4;

  /// Most pinned posts on a team's feed (`teamPostPinsMax` in
  /// `@stall10/shared` team_posts.ts; the API holds it).
  static const pinsMax = 3;

  /// Empty id means the post has not been saved yet.
  final String id;
  final String title;
  final String body;
  final String location;

  /// http(s) URLs, in the order the author added them.
  final List<String> links;

  /// Photos, stored like chat attachments.
  final List<ChatAttachment> images;
  final bool isPublic;

  /// A community tournament the post is about (a FollowTarget key), so the
  /// tournament's followers see it in their feed.
  final String? tournamentKey;
  final String authorId;
  final String authorName;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// When a team admin pinned it (redesign F24); null when not pinned.
  /// Only the API sets it.
  final DateTime? pinnedAt;

  /// Comments on it, kept by the `follows-teamPostCommentCount` function
  /// (missing reads as 0); nobody writes it.
  final int commentCount;

  bool get isNew => id.isEmpty;

  bool get isPinned => pinnedAt != null;

  /// A post needs text or at least one photo.
  bool get hasContent => body.trim().isNotEmpty || images.isNotEmpty;

  /// Edited after it was posted.
  bool get edited =>
      createdAt != null &&
      updatedAt != null &&
      updatedAt!.difference(createdAt!).inMinutes >= 1;

  TeamPost copyWith({
    String? title,
    String? body,
    String? location,
    List<String>? links,
    List<ChatAttachment>? images,
    bool? isPublic,
    String? Function()? tournamentKey,
  }) => TeamPost(
    id: id,
    title: title ?? this.title,
    body: body ?? this.body,
    location: location ?? this.location,
    links: links ?? this.links,
    images: images ?? this.images,
    isPublic: isPublic ?? this.isPublic,
    tournamentKey: tournamentKey == null ? this.tournamentKey : tournamentKey(),
    authorId: authorId,
    authorName: authorName,
    createdAt: createdAt,
    updatedAt: updatedAt,
    pinnedAt: pinnedAt,
    commentCount: commentCount,
  );

  factory TeamPost.fromMap(String id, Map<String, dynamic> map) => TeamPost(
    id: id,
    title: map['title'] as String? ?? '',
    body: map['body'] as String? ?? '',
    location: map['location'] as String? ?? '',
    links: [for (final l in (map['links'] as List?) ?? const []) '$l'],
    images: [
      for (final a in (map['images'] as List?) ?? const [])
        if (a is Map) ChatAttachment.fromMap(Map<String, dynamic>.from(a)),
    ],
    isPublic: map['public'] as bool? ?? false,
    tournamentKey: map['tournamentKey'] as String?,
    authorId: map['authorId'] as String? ?? '',
    authorName: map['authorName'] as String? ?? '',
    createdAt: parseDate(map['createdAt']),
    updatedAt: parseDate(map['updatedAt']),
    pinnedAt: parseDate(map['pinnedAt']),
    commentCount: switch (map['commentCount']) {
      final num n when n > 0 => n.toInt(),
      _ => 0,
    },
  );

  /// Fields editors may change.
  Map<String, dynamic> toEditableMap() => {
    'title': title,
    'body': body,
    'location': location,
    'links': links,
    'images': [for (final i in images) i.toMap()],
    'public': isPublic,
    if (tournamentKey != null) 'tournamentKey': tournamentKey,
  };

  /// Newest first; unsaved timestamps (pending writes) count as now.
  static int newestFirst(TeamPost a, TeamPost b) =>
      (b.createdAt ?? DateTime(9999)).compareTo(a.createdAt ?? DateTime(9999));

  /// [text] as an http(s) link, adding `https://` when no scheme is given;
  /// null if it isn't a usable web address.
  static String? normalizeLink(String text) {
    final t = text.trim();
    if (t.isEmpty || t.contains(RegExp(r'\s'))) return null;
    final withScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(t)
        ? t
        : 'https://$t';
    final uri = Uri.tryParse(withScheme);
    if (uri == null ||
        !(uri.isScheme('http') || uri.isScheme('https')) ||
        !uri.host.contains('.') ||
        withScheme.length > 500) {
      return null;
    }
    // The scheme in lower case ("Https://…" too), as the server's check wants.
    return uri.scheme + withScheme.substring(uri.scheme.length);
  }
}

/// A team feed in order (`arrangeTeamFeed` in `@stall10/shared`): the
/// pinned posts first, newest pin first (at most [TeamPost.pinsMax]), then
/// the rest newest first. [pinned] and [recent] may overlap; each post
/// shows once, [recent]'s copy winning, so a post unpinned since [pinned]
/// was read drops to the rest.
({List<TeamPost> pinned, List<TeamPost> rest}) arrangeTeamFeed(
  Iterable<TeamPost> pinned,
  Iterable<TeamPost> recent,
) {
  final byId = <String, TeamPost>{
    for (final p in [...pinned, ...recent]) p.id: p,
  };
  final far = DateTime(9999);
  final top = byId.values.where((p) => p.isPinned).toList()
    ..sort((a, b) => (b.pinnedAt ?? far).compareTo(a.pinnedAt ?? far));
  final shown = top.take(TeamPost.pinsMax).toList();
  final ids = {for (final p in shown) p.id};
  final rest = [
    for (final p in byId.values)
      if (!ids.contains(p.id)) p,
  ]..sort(TeamPost.newestFirst);
  return (pinned: shown, rest: rest);
}

/// "Comment", "1 comment", "4 comments" (`teamPostCommentLabel`).
String teamPostCommentLabel(int count) => switch (count) {
  <= 0 => 'Comment',
  1 => '1 comment',
  _ => '$count comments',
};

/// A comment on a team post (redesign F24):
/// `teams/{teamId}/posts/{postId}/comments/{id}`. Members read them; the
/// API writes them; its author or a team admin deletes one.
class TeamPostComment {
  const TeamPostComment({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.body,
    this.createdAt,
  });

  /// Longest comment (`teamPostCommentLimits.body`).
  static const maxLength = 1000;

  /// The newest this many show, oldest first (the rules' cap).
  static const shown = 100;

  final String id;
  final String authorId;
  final String authorName;
  final String body;
  final DateTime? createdAt;

  factory TeamPostComment.fromMap(String id, Map<String, dynamic> map) =>
      TeamPostComment(
        id: id,
        authorId: map['authorId'] as String? ?? '',
        authorName: map['authorName'] as String? ?? '',
        body: map['body'] as String? ?? '',
        createdAt: parseDate(map['createdAt']),
      );
}

/// A post as written in the editor: the post plus photos picked but not yet
/// uploaded.
class PostDraft {
  const PostDraft({required this.post, this.newImages = const []});

  /// Kept photos are in [TeamPost.images]; ones removed from the original
  /// are deleted when saved.
  final TeamPost post;
  final List<NewAttachment> newImages;
}
