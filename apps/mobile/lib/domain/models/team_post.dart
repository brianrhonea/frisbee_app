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
  });

  /// Limits firestore.rules enforces too; keep them in step.
  static const maxLinks = 5;
  static const maxImages = 4;

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

  bool get isNew => id.isEmpty;

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
    return withScheme;
  }
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
