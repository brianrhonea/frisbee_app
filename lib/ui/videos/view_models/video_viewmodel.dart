import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../data/repositories/video/video_repository.dart';
import '../../../domain/models/team.dart';
import '../../../domain/models/team_video.dart';
import '../../../utils/command.dart';

/// Backs a video's page: the player and its description.
class VideoViewModel extends ChangeNotifier {
  VideoViewModel({
    required this.teamId,
    required this.videoId,
    required VideoRepository videoRepository,
    required TeamRepository teamRepository,
    required AuthRepository authRepository,
  }) : _auth = authRepository {
    deleteVideo = Command0<void>(
      () => videoRepository.deleteVideo(teamId, videoId),
    );
    _subs = [
      videoRepository.watchVideo(teamId, videoId).listen((v) {
        _video = v;
        _loaded = true;
        notifyListeners();
      }, onError: _onError),
      teamRepository.watchTeam(teamId).listen((t) {
        _team = t;
        notifyListeners();
      }, onError: _onError),
    ];
  }

  final String teamId;
  final String videoId;
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
    super.dispose();
  }
}
