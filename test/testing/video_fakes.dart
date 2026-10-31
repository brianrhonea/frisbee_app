import 'dart:async';

import 'package:flutter/material.dart';
import 'package:frisbee_app/data/repositories/video/video_repository.dart';
import 'package:frisbee_app/data/services/youtube_info_service.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/team_video.dart';
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

  @override
  Future<Result<void>> deleteVideo(String teamId, String videoId) async {
    videos[teamId]?.removeWhere((v) => v.id == videoId);
    _changes.add(null);
    return const Result.ok(null);
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

/// Stands in for YouTube's player, which needs a platform web view.
Widget fakePlayer(String youtubeId) => Text('player:$youtubeId');
