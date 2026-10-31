import 'model_utils.dart';

/// A YouTube video shared with a team, e.g. a meeting recording uploaded as
/// unlisted. Only the video's id and a description are stored; the video
/// itself stays on YouTube and plays in its embedded player. Owners,
/// coaches and captains post; members watch.
class TeamVideo {
  const TeamVideo({
    required this.id,
    required this.youtubeId,
    this.title = '',
    this.description = '',
    this.authorId = '',
    this.authorName = '',
    this.createdAt,
    this.updatedAt,
  });

  /// Limits firestore.rules enforces too; keep them in step.
  static const maxTitle = 100;
  static const maxDescription = 2000;

  /// Empty id means the video has not been saved yet.
  final String id;

  /// The 11-character YouTube video id.
  final String youtubeId;
  final String title;
  final String description;
  final String authorId;
  final String authorName;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isNew => id.isEmpty;

  String get watchUrl => watchUrlOf(youtubeId);
  String get thumbnailUrl => thumbnailUrlOf(youtubeId);

  static String watchUrlOf(String youtubeId) =>
      'https://www.youtube.com/watch?v=$youtubeId';

  /// YouTube's 480×360 thumbnail; every video has one.
  static String thumbnailUrlOf(String youtubeId) =>
      'https://i.ytimg.com/vi/$youtubeId/hqdefault.jpg';

  static final _idPattern = RegExp(r'^[A-Za-z0-9_-]{11}$');

  /// The video id in a YouTube link (watch, youtu.be, shorts, live, embed)
  /// or a bare id; null if [text] isn't one.
  static String? youtubeIdFrom(String text) {
    final t = text.trim();
    if (_idPattern.hasMatch(t)) return t;
    final uri = Uri.tryParse(
      RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(t) ? t : 'https://$t',
    );
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return null;
    }
    final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^(www|m)\.'), '');
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    final String? id = switch (host) {
      'youtu.be' => segments.firstOrNull,
      'youtube.com' ||
      'music.youtube.com' ||
      'youtube-nocookie.com' => switch (segments) {
        ['watch', ...] => uri.queryParameters['v'],
        ['shorts' || 'live' || 'embed' || 'v', final id, ...] => id,
        _ => null,
      },
      _ => null,
    };
    return id != null && _idPattern.hasMatch(id) ? id : null;
  }

  TeamVideo copyWith({
    String? id,
    String? youtubeId,
    String? title,
    String? description,
  }) => TeamVideo(
    id: id ?? this.id,
    youtubeId: youtubeId ?? this.youtubeId,
    title: title ?? this.title,
    description: description ?? this.description,
    authorId: authorId,
    authorName: authorName,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );

  factory TeamVideo.fromMap(String id, Map<String, dynamic> map) => TeamVideo(
    id: id,
    youtubeId: map['youtubeId'] as String? ?? '',
    title: map['title'] as String? ?? '',
    description: map['description'] as String? ?? '',
    authorId: map['authorId'] as String? ?? '',
    authorName: map['authorName'] as String? ?? '',
    createdAt: parseDate(map['createdAt']),
    updatedAt: parseDate(map['updatedAt']),
  );

  /// Fields editors may change.
  Map<String, dynamic> toEditableMap() => {
    'youtubeId': youtubeId,
    'title': title.trim(),
    'description': description.trim(),
  };

  /// Newest first; unsaved timestamps (pending writes) count as now.
  static int newestFirst(TeamVideo a, TeamVideo b) =>
      (b.createdAt ?? DateTime(9999)).compareTo(a.createdAt ?? DateTime(9999));
}
