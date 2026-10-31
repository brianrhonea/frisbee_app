import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../data/repositories/video/video_repository.dart';
import '../../../domain/models/team.dart';
import '../../../domain/models/team_video.dart';
import '../../../utils/command.dart';

/// Backs a team's Videos section: the list, and deleting for admins.
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
    _subs = [
      videoRepository.watchVideos(teamId).listen((v) {
        _videos = v;
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
  final AuthRepository _auth;
  late final List<StreamSubscription<Object?>> _subs;

  late final Command1<void, String> deleteVideo;

  List<TeamVideo> _videos = const [];
  List<TeamVideo> get videos => _videos;

  Team? _team;

  bool _loaded = false;
  bool get loaded => _loaded || _error != null;

  Object? _error;
  Object? get error => _error;

  /// Owners, coaches and captains post, edit and delete videos.
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
