import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../data/repositories/video/video_repository.dart';
import '../../../domain/models/team.dart';
import '../../../domain/models/team_video.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// Backs a video's page: the player and its description.
class VideoViewModel extends ChangeNotifier {
  VideoViewModel({
    required this.teamId,
    required this.videoId,
    required VideoRepository videoRepository,
    required TeamRepository teamRepository,
    required AuthRepository authRepository,
  }) : _videos = videoRepository,
       _auth = authRepository {
    deleteVideo = Command0<void>(
      () => videoRepository.deleteVideo(teamId, videoId),
    );
    _subs = [
      videoRepository.watchVideo(teamId, videoId).listen((v) {
        _video = v;
        _loaded = true;
        notifyListeners();
        if (v?.file case final file? when file.path != _urlFor) {
          unawaited(_loadUrl(file));
        }
      }, onError: _onError),
      teamRepository.watchTeam(teamId).listen((t) {
        _team = t;
        notifyListeners();
      }, onError: _onError),
    ];
  }

  final String teamId;
  final String videoId;
  final VideoRepository _videos;
  final AuthRepository _auth;
  late final List<StreamSubscription<Object?>> _subs;

  late final Command0<void> deleteVideo;

  TeamVideo? _video;

  /// Null once loaded means it was deleted or isn't readable.
  TeamVideo? get video => _video;

  Team? _team;

  bool _loaded = false;
  bool get loaded => _loaded || _error != null;

  Object? _error;
  Object? get error => _error;

  /// Where to stream an uploaded video from, once fetched.
  String? _fileUrl;
  String? get fileUrl => _fileUrl;
  String? _urlFor;

  Object? _fileError;
  Object? get fileError => _fileError;

  Future<void> _loadUrl(VideoFile file) async {
    _urlFor = file.path;
    _fileUrl = null;
    _fileError = null;
    final result = await _videos.fileUrl(file);
    if (_disposed || _urlFor != file.path) return;
    switch (result) {
      case Ok(:final value):
        _fileUrl = value;
      case Error(:final error):
        _fileError = error;
    }
    notifyListeners();
  }

  bool get canEdit => _team?.canEdit(_auth.currentUser?.uid ?? '') ?? false;

  void _onError(Object e) {
    _error = e;
    notifyListeners();
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    for (final s in _subs) {
      s.cancel();
    }
    deleteVideo.dispose();
    super.dispose();
  }
}
