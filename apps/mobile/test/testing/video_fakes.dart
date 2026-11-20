import 'dart:async';

import 'package:flutter/material.dart';
import 'package:frisbee_app/data/repositories/video/video_repository.dart';
import 'package:frisbee_app/data/services/synced_video.dart';
import 'package:frisbee_app/data/services/youtube_info_service.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/team_video.dart';
import 'package:frisbee_app/domain/models/video_comment.dart';
import 'package:frisbee_app/domain/models/video_folder.dart';
import 'package:frisbee_app/utils/result.dart';

class FakeVideoRepository implements VideoRepository {
  /// teamId → videos.
  final videos = <String, List<TeamVideo>>{};
  final _changes = StreamController<void>.broadcast();
  var _next = 0;

  List<TeamVideo> _of(String teamId) =>
      [...?videos[teamId]]..sort(TeamVideo.newestFirst);

  @override
  Stream<List<TeamVideo>> watchVideos(String teamId) async* {
    final changes = _changes.stream.map((_) => _of(teamId));
    yield _of(teamId);
    yield* changes;
  }

  @override
  Stream<TeamVideo?> watchVideo(String teamId, String videoId) async* {
    TeamVideo? find() =>
        videos[teamId]?.where((v) => v.id == videoId).firstOrNull;
    final changes = _changes.stream.map((_) => find());
    yield find();
    yield* changes;
  }

  @override
  Future<Result<String>> saveVideo(
    String teamId,
    TeamVideo video,
    AppUser author,
  ) async {
    final list = videos.putIfAbsent(teamId, () => []);
    final id = video.isNew ? 'v${++_next}' : video.id;
    final i = list.indexWhere((v) => v.id == id);
    final saved = TeamVideo(
      id: id,
      youtubeId: video.youtubeId,
      file: i < 0 ? video.file : list[i].file,
      folderId: video.folderId,
      title: video.title.trim(),
      description: video.description.trim(),
      authorId: i < 0 ? author.uid : list[i].authorId,
      authorName: i < 0 ? author.label : list[i].authorName,
      createdAt: i < 0 ? DateTime(2026, 11, 1, _next) : list[i].createdAt,
      updatedAt: DateTime(2026, 11, 2),
    );
    if (i < 0) {
      list.add(saved);
    } else {
      list[i] = saved;
    }
    _changes.add(null);
    return Result.ok(id);
  }

  /// Files uploaded by [uploadVideo], by name.
  final uploaded = <String>[];

  @override
  Future<Result<String>> uploadVideo(
    String teamId,
    TeamVideo video,
    VideoUpload upload,
    AppUser author, {
    void Function(double progress)? onProgress,
  }) async {
    onProgress?.call(0.5);
    uploaded.add(upload.name);
    onProgress?.call(1);
    return saveVideo(
      teamId,
      video.copyWith(
        youtubeId: '',
        file: VideoFile(
          path: 'teams/$teamId/videos/new/${upload.name}',
          name: upload.name,
          size: upload.size,
          contentType: VideoFile.contentTypeFor(upload.name)!,
        ),
      ),
      author,
    );
  }

  @override
  Future<Result<String>> fileUrl(VideoFile file) async =>
      Result.ok('https://files.test/${file.name}');

  @override
  Future<Result<void>> deleteVideo(String teamId, String videoId) async {
    videos[teamId]?.removeWhere((v) => v.id == videoId);
    comments.remove('$teamId/$videoId');
    _changes.add(null);
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> moveVideo(
    String teamId,
    String videoId,
    String folderId,
  ) async {
    final list = videos[teamId] ?? [];
    final i = list.indexWhere((v) => v.id == videoId);
    if (i < 0) return Result.error(Exception('No such video'));
    list[i] = list[i].copyWith(folderId: folderId);
    _changes.add(null);
    return const Result.ok(null);
  }

  /// teamId → folders.
  final folders = <String, List<VideoFolder>>{};
  final _folderChanges = StreamController<void>.broadcast();

  List<VideoFolder> _foldersOf(String teamId) =>
      [...?folders[teamId]]..sort(VideoFolder.byName);

  @override
  Stream<List<VideoFolder>> watchFolders(String teamId) async* {
    final changes = _folderChanges.stream.map((_) => _foldersOf(teamId));
    yield _foldersOf(teamId);
    yield* changes;
  }

  @override
  Future<Result<String>> saveFolder(String teamId, VideoFolder folder) async {
    final list = folders.putIfAbsent(teamId, () => []);
    final id = folder.isNew ? 'f${++_next}' : folder.id;
    final saved = VideoFolder(id: id, name: folder.name.trim());
    final i = list.indexWhere((f) => f.id == id);
    if (i < 0) {
      list.add(saved);
    } else {
      list[i] = saved;
    }
    _folderChanges.add(null);
    return Result.ok(id);
  }

  @override
  Future<Result<void>> deleteFolder(String teamId, String folderId) async {
    final list = videos[teamId] ?? [];
    for (var i = 0; i < list.length; i++) {
      if (list[i].folderId == folderId) {
        list[i] = list[i].copyWith(folderId: '');
      }
    }
    folders[teamId]?.removeWhere((f) => f.id == folderId);
    _changes.add(null);
    _folderChanges.add(null);
    return const Result.ok(null);
  }

  /// Off for a build without the API.
  bool extras = true;

  /// The signed-in user's id and name, for comments the fake adds.
  String uid = 'me';
  String name = 'Me';

  /// Set to make the next write fail with it.
  Object? failWith;

  /// "teamId/videoId" -> its notes and comments.
  final comments = <String, List<VideoComment>>{};
  final _commentChanges = StreamController<void>.broadcast();

  /// Tags sent, as (videoId, eventId).
  final tagged = <(String, String?)>[];

  @override
  bool get canUseVideoExtras => extras;

  @override
  Stream<List<VideoComment>> watchComments(
    String teamId,
    String videoId,
  ) async* {
    List<VideoComment> of() => [...?comments['$teamId/$videoId']];
    yield of();
    yield* _commentChanges.stream.map((_) => of());
  }

  Result<void>? _failure() {
    final e = failWith;
    if (e == null) return null;
    failWith = null;
    return Result.error(e is Exception ? e : Exception('$e'));
  }

  @override
  Future<Result<void>> addComment(
    String teamId,
    String videoId, {
    required String body,
    int? atMs,
    int? endMs,
  }) async {
    if (_failure() case final f?) return f;
    comments
        .putIfAbsent('$teamId/$videoId', () => [])
        .add(
          VideoComment(
            id: 'c${++_next}',
            authorId: uid,
            authorName: name,
            body: body,
            atMs: atMs,
            endMs: endMs,
            createdAt: DateTime(2026, 11, 20, 12, _next),
          ),
        );
    _commentChanges.add(null);
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> deleteComment(
    String teamId,
    String videoId,
    String commentId,
  ) async {
    if (_failure() case final f?) return f;
    comments['$teamId/$videoId']?.removeWhere((c) => c.id == commentId);
    _commentChanges.add(null);
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> tagEvent(
    String teamId,
    String videoId,
    String? eventId,
  ) async {
    if (_failure() case final f?) return f;
    tagged.add((videoId, eventId));
    final list = videos[teamId] ?? [];
    final i = list.indexWhere((v) => v.id == videoId);
    if (i < 0) return Result.error(Exception('No such video'));
    final v = list[i];
    list[i] = TeamVideo(
      id: v.id,
      youtubeId: v.youtubeId,
      file: v.file,
      folderId: v.folderId,
      title: v.title,
      description: v.description,
      authorId: v.authorId,
      authorName: v.authorName,
      createdAt: v.createdAt,
      updatedAt: v.updatedAt,
      eventId: eventId ?? '',
    );
    _changes.add(null);
    return const Result.ok(null);
  }

  @override
  Stream<List<TeamVideo>> watchEventVideos(
    String teamId,
    String eventId,
  ) async* {
    List<TeamVideo> of() =>
        _of(teamId).where((v) => v.eventId == eventId).toList();
    yield of();
    yield* _changes.stream.map((_) => of());
  }
}

/// Answers lookups from [videos]; ids not in it can't be embedded.
/// Set [offline] to make lookups throw.
class FakeYouTubeInfoService implements YouTubeInfoService {
  FakeYouTubeInfoService([this.videos = const {}]);

  final Map<String, YouTubeInfo> videos;
  bool offline = false;
  final lookedUp = <String>[];

  @override
  Future<YouTubeInfo?> lookUp(String youtubeId) async {
    lookedUp.add(youtubeId);
    if (offline) throw Exception('offline');
    return videos[youtubeId];
  }
}

/// Stands in for YouTube's player, which needs a platform web view. Hands
/// [onController] a [FakeVideoController].
Widget fakePlayer(
  String youtubeId, [
  ValueChanged<SyncedVideoController?>? onController,
]) => _FakePlayer(label: 'player:$youtubeId', onController: onController);

/// Stands in for media_kit's player, which needs native libraries.
Widget fakeFilePlayer(
  String url, [
  ValueChanged<SyncedVideoController?>? onController,
]) => _FakePlayer(label: 'file player:$url', onController: onController);

/// A player a test moves by hand: set [position]; seeks and plays are kept.
class FakeVideoController implements SyncedVideoController {
  /// The last one a fake player handed over.
  static FakeVideoController? last;

  Duration position = Duration.zero;
  final seeks = <Duration>[];
  bool playing = false;

  /// False: not loaded yet, so [status] is null (YouTube before it plays).
  bool ready = true;

  @override
  Future<void> play() async => playing = true;

  @override
  Future<void> pause() async => playing = false;

  @override
  Future<void> seekTo(Duration to) async {
    seeks.add(to);
    position = to;
  }

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<PlayerStatus?> status() async => ready
      ? (
          position: position,
          duration: const Duration(hours: 1),
          playing: playing,
        )
      : null;
}

class _FakePlayer extends StatefulWidget {
  const _FakePlayer({required this.label, this.onController});

  final String label;
  final ValueChanged<SyncedVideoController?>? onController;

  @override
  State<_FakePlayer> createState() => _FakePlayerState();
}

class _FakePlayerState extends State<_FakePlayer> {
  @override
  void initState() {
    super.initState();
    if (widget.onController case final on?) {
      on(FakeVideoController.last = FakeVideoController());
    }
  }

  @override
  void dispose() {
    widget.onController?.call(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(widget.label);
}
