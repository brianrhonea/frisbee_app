import 'model_utils.dart';

/// A video file uploaded to Cloud Storage for a [TeamVideo].
class VideoFile {
  const VideoFile({
    required this.path,
    required this.name,
    required this.size,
    this.contentType = 'video/mp4',
  });

  /// Storage path, under `teams/{teamId}/videos/{videoId}/`.
  final String path;
  final String name;

  /// Bytes.
  final int size;

  final String contentType;

  /// File extensions that can be uploaded, and their content types. Keep in
  /// step with `validFile` in firestore.rules.
  static const types = {
    'mp4': 'video/mp4',
    'm4v': 'video/x-m4v',
    'mov': 'video/quicktime',
    'mkv': 'video/x-matroska',
    'webm': 'video/webm',
    'avi': 'video/x-msvideo',
    'wmv': 'video/x-ms-wmv',
    'mpg': 'video/mpeg',
    'mpeg': 'video/mpeg',
    '3gp': 'video/3gpp',
  };

  static String extensionOf(String name) {
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  /// The content type for a file called [name]; null if it can't be
  /// uploaded.
  static String? contentTypeFor(String name) => types[extensionOf(name)];

  /// [name] without its video extension, e.g. for a default title.
  static String baseName(String name) => types.containsKey(extensionOf(name))
      ? name.substring(0, name.lastIndexOf('.'))
      : name;

  /// "MKV", "MP4", ...
  String get format {
    final ext = extensionOf(name);
    return ext.isEmpty ? 'Video' : ext.toUpperCase();
  }

  factory VideoFile.fromMap(Map<String, dynamic> map) => VideoFile(
    path: map['path'] as String? ?? '',
    name: map['name'] as String? ?? '',
    size: (map['size'] as num?)?.toInt() ?? 0,
    contentType: map['contentType'] as String? ?? 'video/mp4',
  );

  Map<String, dynamic> toMap() => {
    'path': path,
    'name': name,
    'size': size,
    'contentType': contentType,
  };
}

/// A video shared with a team, e.g. a meeting recording: either a YouTube
/// video (only its id is stored; it plays in YouTube's embedded player) or
/// a video file uploaded to the team ([file]). Owners, coaches and captains post;
/// members watch.
class TeamVideo {
  const TeamVideo({
    required this.id,
    this.youtubeId = '',
    this.file,
    this.folderId = '',
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

  /// Uploads: per file (storage.rules and firestore.rules enforce it), and
  /// per team (the app enforces it; rules can't add files up).
  static const maxFileBytes = 500 * 1024 * 1024;
  static const teamQuotaBytes = 5 * 1024 * 1024 * 1024;

  /// Empty id means the video has not been saved yet.
  final String id;

  /// The 11-character YouTube video id; empty for an upload.
  final String youtubeId;

  /// The uploaded file; null for a YouTube video.
  final VideoFile? file;

  bool get isYouTube => file == null;

  /// The [VideoFolder] it's filed in; empty when unsorted.
  final String folderId;
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
    VideoFile? file,
    String? folderId,
    String? title,
    String? description,
  }) => TeamVideo(
    id: id ?? this.id,
    youtubeId: youtubeId ?? this.youtubeId,
    file: file ?? this.file,
    folderId: folderId ?? this.folderId,
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
    file: map['file'] is Map
        ? VideoFile.fromMap(Map<String, dynamic>.from(map['file'] as Map))
        : null,
    folderId: map['folderId'] as String? ?? '',
    title: map['title'] as String? ?? '',
    description: map['description'] as String? ?? '',
    authorId: map['authorId'] as String? ?? '',
    authorName: map['authorName'] as String? ?? '',
    createdAt: parseDate(map['createdAt']),
    updatedAt: parseDate(map['updatedAt']),
  );

  /// Fields editors may change. The file is set once, when the video is
  /// created ([toCreateMap]).
  Map<String, dynamic> toEditableMap() => {
    'youtubeId': youtubeId,
    'folderId': folderId,
    'title': title.trim(),
    'description': description.trim(),
  };

  Map<String, dynamic> toCreateMap() => {
    ...toEditableMap(),
    'file': file?.toMap(),
  };

  /// Bytes used by uploads in [videos].
  static int bytesUsed(Iterable<TeamVideo> videos) =>
      videos.fold(0, (sum, v) => sum + (v.file?.size ?? 0));

  /// "1.2 GB", "340 MB".
  static String formatBytes(int bytes) {
    const gb = 1024 * 1024 * 1024;
    const mb = 1024 * 1024;
    if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(1)} GB';
    return '${(bytes / mb).ceil()} MB';
  }

  /// Newest first; unsaved timestamps (pending writes) count as now.
  static int newestFirst(TeamVideo a, TeamVideo b) =>
      (b.createdAt ?? DateTime(9999)).compareTo(a.createdAt ?? DateTime(9999));
}
