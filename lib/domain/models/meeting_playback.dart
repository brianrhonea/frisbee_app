import 'model_utils.dart';

/// A team video everyone in a live meeting watches together: which one,
/// whether it's playing, and where. The presenter, an admin, drives it;
/// everyone's player follows. Lives at
/// `teams/{teamId}/meetings/{meetingId}/playback/current`.
class MeetingPlayback {
  const MeetingPlayback({
    required this.videoId,
    required this.playing,
    required this.position,
    required this.presenterId,
    required this.presenterName,
    this.updatedAt,
  });

  /// A [TeamVideo] id on the same team.
  final String videoId;
  final bool playing;

  /// Where the video was at [updatedAt].
  final Duration position;
  final String presenterId;
  final String presenterName;

  /// Server time of the last change; null while the write is pending.
  final DateTime? updatedAt;

  /// Where the video should be at [now]: [position], plus the time since
  /// [updatedAt] while it plays. Device clocks are trusted to be close;
  /// the presenter's heartbeat keeps any error small.
  Duration positionAt(DateTime now) {
    if (!playing) return position;
    final since = now.difference(updatedAt ?? now);
    return since.isNegative ? position : position + since;
  }

  MeetingPlayback copyWith({
    String? videoId,
    bool? playing,
    Duration? position,
    String? presenterId,
    String? presenterName,
  }) => MeetingPlayback(
    videoId: videoId ?? this.videoId,
    playing: playing ?? this.playing,
    position: position ?? this.position,
    presenterId: presenterId ?? this.presenterId,
    presenterName: presenterName ?? this.presenterName,
    updatedAt: updatedAt,
  );

  factory MeetingPlayback.fromMap(Map<String, dynamic> map) => MeetingPlayback(
    videoId: map['videoId'] as String? ?? '',
    playing: map['playing'] as bool? ?? false,
    position: Duration(milliseconds: (map['positionMs'] as num?)?.toInt() ?? 0),
    presenterId: map['presenterId'] as String? ?? '',
    presenterName: map['presenterName'] as String? ?? '',
    updatedAt: parseDate(map['updatedAt']),
  );

  /// Everything but [updatedAt], which the server sets.
  Map<String, dynamic> toMap() => {
    'videoId': videoId,
    'playing': playing,
    'positionMs': position.inMilliseconds,
    'presenterId': presenterId,
    'presenterName': presenterName,
  };
}
