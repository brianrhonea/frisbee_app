import '../../../domain/models/app_user.dart';
import '../../../domain/models/team_video.dart';
import '../../../utils/result.dart';

abstract class VideoRepository {
  /// The team's videos, newest first. Members only.
  Stream<List<TeamVideo>> watchVideos(String teamId);

  /// One video; null once it's deleted.
  Stream<TeamVideo?> watchVideo(String teamId, String videoId);

  /// Creates the video when [TeamVideo.isNew], otherwise updates its link,
  /// title and description. Owners, coaches and captains only. The result
  /// is the video's id.
  Future<Result<String>> saveVideo(
    String teamId,
    TeamVideo video,
    AppUser author,
  );

  Future<Result<void>> deleteVideo(String teamId, String videoId);
}
