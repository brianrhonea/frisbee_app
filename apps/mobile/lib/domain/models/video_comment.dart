import 'model_utils.dart';

/// A note, clip or comment on a team video (redesign F4, F5), in
/// `teams/{teamId}/videos/{videoId}/comments` (`VideoCommentDoc` in
/// packages/shared). A comment pinned to a time ([atMs]) is a note; a note
/// with an end ([endMs]) is a clip. Written through the API only.
class VideoComment {
  const VideoComment({
    required this.id,
    required this.authorId,
    this.authorName = '',
    required this.body,
    this.atMs,
    this.endMs,
    this.createdAt,
  });

  /// `videoCommentLimits` in packages/shared.
  static const maxBody = 1000;
  static const maxMs = 24 * 3600 * 1000;

  final String id;
  final String authorId;
  final String authorName;
  final String body;

  /// Where it's pinned in the video; null for a plain comment.
  final int? atMs;

  /// Where a clip ends; null unless it's a clip.
  final int? endMs;
  final DateTime? createdAt;

  bool get isNote => atMs != null;
  bool get isClip => atMs != null && endMs != null;

  /// "1:23", or "1:23–1:40" for a clip (`videoNoteTime`).
  String get timeLabel {
    final start = formatTime(atMs ?? 0);
    final end = endMs;
    return end == null ? start : '$start–${formatTime(end)}';
  }

  /// "0:07", "1:23", "1:02:03" (`formatVideoTime`).
  static String formatTime(int ms) {
    final total = ms < 0 ? 0 : ms ~/ 1000;
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = (total % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
  }

  factory VideoComment.fromMap(String id, Map<String, dynamic> map) =>
      VideoComment(
        id: id,
        authorId: map['authorId'] as String? ?? '',
        authorName: map['authorName'] as String? ?? '',
        body: map['body'] as String? ?? '',
        atMs: (map['atMs'] as num?)?.toInt(),
        endMs: (map['endMs'] as num?)?.toInt(),
        createdAt: parseDate(map['createdAt']),
      );

  static int _created(VideoComment c) =>
      c.createdAt?.millisecondsSinceEpoch ?? 1 << 62;

  /// Notes by time (ties oldest first) and comments oldest first, unsaved
  /// last (`splitVideoComments`).
  static ({List<VideoComment> notes, List<VideoComment> comments}) split(
    Iterable<VideoComment> all,
  ) {
    final notes = all.where((c) => c.isNote).toList()
      ..sort((a, b) {
        final t = a.atMs!.compareTo(b.atMs!);
        return t != 0 ? t : _created(a).compareTo(_created(b));
      });
    final comments = all.where((c) => !c.isNote).toList()
      ..sort((a, b) => _created(a).compareTo(_created(b)));
    return (notes: notes, comments: comments);
  }
}
