import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../data/repositories/video/video_repository.dart';
import '../../../domain/models/team.dart';
import '../../../domain/models/team_video.dart';
import '../../../domain/models/video_folder.dart';
import '../../../utils/command.dart';

/// Which videos the Videos section shows.
sealed class VideoFilter {
  const VideoFilter();
}

class AllVideos extends VideoFilter {
  const AllVideos();
}

/// Videos in no folder, or in one that was deleted.
class UnsortedVideos extends VideoFilter {
  const UnsortedVideos();
}

class InFolder extends VideoFilter {
  const InFolder(this.folderId);

  final String folderId;

  @override
  bool operator ==(Object other) =>
      other is InFolder && other.folderId == folderId;

  @override
  int get hashCode => folderId.hashCode;
}

/// Backs a team's Videos section: the list, its folders, and for admins
/// deleting and filing videos and managing folders.
class TeamVideosViewModel extends ChangeNotifier {
  TeamVideosViewModel({
    required this.teamId,
    required VideoRepository videoRepository,
    required TeamRepository teamRepository,
    required AuthRepository authRepository,
  }) : _auth = authRepository {
    deleteVideo = Command1<void, String>(
      (id) => videoRepository.deleteVideo(teamId, id),
    );
    moveVideo = Command1<void, ({String videoId, String folderId})>(
      (m) => videoRepository.moveVideo(teamId, m.videoId, m.folderId),
    );
    saveFolder = Command1<String, VideoFolder>(
      (f) => videoRepository.saveFolder(teamId, f),
    );
    deleteFolder = Command1<void, String>(
      (id) => videoRepository.deleteFolder(teamId, id),
    );
    _subs = [
      videoRepository.watchVideos(teamId).listen((v) {
        _videos = v;
        _loaded = true;
        notifyListeners();
      }, onError: _onError),
      videoRepository.watchFolders(teamId).listen((f) {
        _folders = f;
        // The folder being viewed was deleted.
        if (_filter case InFolder(
          :final folderId,
        ) when !f.any((x) => x.id == folderId)) {
          _filter = const AllVideos();
        }
        notifyListeners();
      }, onError: _onError),
      teamRepository.watchTeam(teamId).listen((t) {
        _team = t;
        notifyListeners();
      }, onError: _onError),
    ];
  }

  final String teamId;
  final AuthRepository _auth;
  late final List<StreamSubscription<Object?>> _subs;

  late final Command1<void, String> deleteVideo;
  late final Command1<void, ({String videoId, String folderId})> moveVideo;

  /// Creates or renames a folder; the result is its id.
  late final Command1<String, VideoFolder> saveFolder;
  late final Command1<void, String> deleteFolder;

  List<TeamVideo> _videos = const [];
  List<TeamVideo> get videos => _videos;

  List<VideoFolder> _folders = const [];

  /// A–Z.
  List<VideoFolder> get folders => _folders;

  VideoFilter _filter = const AllVideos();
  VideoFilter get filter => _filter;

  set filter(VideoFilter value) {
    if (value == _filter) return;
    _filter = value;
    notifyListeners();
  }

  /// The folder [video] is filed in; null when unsorted.
  VideoFolder? folderOf(TeamVideo video) =>
      _folders.where((f) => f.id == video.folderId).firstOrNull;

  /// The folder being viewed, if one is.
  VideoFolder? get currentFolder => switch (_filter) {
    InFolder(:final folderId) =>
      _folders.where((f) => f.id == folderId).firstOrNull,
    _ => null,
  };

  bool _matches(TeamVideo v, VideoFilter f) => switch (f) {
    AllVideos() => true,
    UnsortedVideos() => folderOf(v) == null,
    InFolder(:final folderId) => v.folderId == folderId,
  };

  /// The videos [filter] shows, newest first.
  List<TeamVideo> get visibleVideos => [
    for (final v in _videos)
      if (_matches(v, _filter)) v,
  ];

  int countIn(VideoFilter f) => _videos.where((v) => _matches(v, f)).length;

  /// Bytes the team's uploads use, out of [TeamVideo.teamQuotaBytes].
  int get usedBytes => TeamVideo.bytesUsed(_videos);

  Team? _team;

  bool _loaded = false;
  bool get loaded => _loaded || _error != null;

  Object? _error;
  Object? get error => _error;

  /// Owners, coaches and captains post, edit, file and delete videos, and
  /// manage folders.
  bool get canEdit => _team?.canEdit(_auth.currentUser?.uid ?? '') ?? false;

  void _onError(Object e) {
    _error = e;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    deleteVideo.dispose();
    moveVideo.dispose();
    saveFolder.dispose();
    deleteFolder.dispose();
    super.dispose();
  }
}
