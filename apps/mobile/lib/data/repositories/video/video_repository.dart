import '../../../domain/models/app_user.dart';
import '../../../domain/models/team_video.dart';
import '../../../domain/models/video_folder.dart';
import '../../../utils/result.dart';

/// A video file on this device, to upload.
typedef VideoUpload = ({String path, String name, int size});

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

  /// Uploads [upload] to Cloud Storage, then creates a video for it with
  /// [video]'s title and description. [onProgress] gets 0–1 as it goes.
  /// The result is the new video's id.
  Future<Result<String>> uploadVideo(
    String teamId,
    TeamVideo video,
    VideoUpload upload,
    AppUser author, {
    void Function(double progress)? onProgress,
  });

  /// A URL to stream an uploaded video from. Fetched when it's played and
  /// never stored: Storage download URLs work for anyone who has them.
  Future<Result<String>> fileUrl(VideoFile file);

  /// Removes the video, and its file if it was uploaded.
  Future<Result<void>> deleteVideo(String teamId, String videoId);

  /// Files the video in [folderId]; empty to unsort it.
  Future<Result<void>> moveVideo(
    String teamId,
    String videoId,
    String folderId,
  );

  /// The team's video folders, A–Z. Members only.
  Stream<List<VideoFolder>> watchFolders(String teamId);

  /// Creates the folder when [VideoFolder.isNew], otherwise renames it.
  /// Owners, coaches and captains only. The result is the folder's id.
  Future<Result<String>> saveFolder(String teamId, VideoFolder folder);

  /// Deletes the folder; its videos become unsorted, not deleted.
  Future<Result<void>> deleteFolder(String teamId, String folderId);
}
