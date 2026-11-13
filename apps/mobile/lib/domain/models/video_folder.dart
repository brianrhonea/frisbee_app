import 'model_utils.dart';

/// A folder in a team's Videos section, e.g. "Game film" or "Highlights".
/// Videos point at one by id ([TeamVideo.folderId]); a video with no
/// folder, or whose folder was deleted, is unsorted. Owners, coaches and
/// captains manage folders; members see them.
class VideoFolder {
  const VideoFolder({required this.id, required this.name, this.createdAt});

  /// firestore.rules enforces it too; keep them in step.
  static const maxName = 40;

  /// Empty id means the folder has not been saved yet.
  final String id;
  final String name;
  final DateTime? createdAt;

  bool get isNew => id.isEmpty;

  factory VideoFolder.fromMap(String id, Map<String, dynamic> map) =>
      VideoFolder(
        id: id,
        name: map['name'] as String? ?? '',
        createdAt: parseDate(map['createdAt']),
      );

  /// A–Z, ignoring case.
  static int byName(VideoFolder a, VideoFolder b) =>
      a.name.toLowerCase().compareTo(b.name.toLowerCase());
}
