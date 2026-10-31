import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../data/repositories/video/video_repository.dart';
import '../../../data/services/youtube_info_service.dart';
import '../../../domain/models/team.dart';
import '../../../domain/models/team_video.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// Whether a pasted link points at a video the team can watch here.
enum LinkCheck {
  /// Nothing pasted yet.
  empty,

  /// Not a YouTube link.
  invalid,
  checking,

  /// Public or unlisted, and embedding is allowed.
  embeddable,

  /// Private, deleted, or the owner turned embedding off.
  notEmbeddable,

  /// YouTube couldn't be reached; the link may still be fine.
  unknown,
}

/// Posts or edits a team video. Form state lives in the screen; this loads
/// the original, checks links with YouTube, and saves.
class VideoEditorViewModel extends ChangeNotifier {
  VideoEditorViewModel({
    required this.teamId,
    required this.videoId,
    required VideoRepository videoRepository,
    required TeamRepository teamRepository,
    required AuthRepository authRepository,
    required YouTubeInfoService youTubeInfo,
  }) : _videos = videoRepository,
       _teams = teamRepository,
       _auth = authRepository,
       _info = youTubeInfo {
    load = Command0<void>(_load)..execute();
    save = Command1<String, TeamVideo>(_save);
  }

  final String teamId;

  /// Null when posting a new video.
  final String? videoId;
  final VideoRepository _videos;
  final TeamRepository _teams;
  final AuthRepository _auth;
  final YouTubeInfoService _info;

  late final Command0<void> load;

  /// Result value is the saved video's id.
  late final Command1<String, TeamVideo> save;

  bool get isNew => videoId == null;

  Team? _team;
  TeamVideo? _original;

  bool get canEdit => _team?.canEdit(_auth.currentUser?.uid ?? '') ?? false;

  /// Starting values for the form.
  TeamVideo get initial => _original ?? const TeamVideo(id: '', youtubeId: '');

  LinkCheck _check = LinkCheck.empty;
  LinkCheck get linkCheck => _check;

  /// The id of the last link checked, valid or not.
  String? _checkedId;
  String? get youtubeId => _checkedId;

  /// The video's title on YouTube, once checked.
  String? _youTubeTitle;
  String? get youTubeTitle => _youTubeTitle;

  String? _channel;
  String? get channel => _channel;

  Future<Result<void>> _load() async {
    try {
      _team = await _teams.watchTeam(teamId).first;
      final id = videoId;
      if (id != null) {
        _original = await _videos.watchVideo(teamId, id).first;
        if (_original == null) {
          return Result.error(Exception('Video not found.'));
        }
      }
    } on Exception catch (e) {
      return Result.error(e);
    }
    notifyListeners();
    if (!canEdit) {
      return Result.error(Exception('Only admins can post videos.'));
    }
    if (_original case final v?) await checkLink(v.youtubeId);
    return const Result.ok(null);
  }

  /// Checks a pasted link: parses the video id, then asks YouTube whether
  /// it can be embedded and what it's called.
  Future<void> checkLink(String link) async {
    final id = TeamVideo.youtubeIdFrom(link);
    if (id != null && id == _checkedId && _check != LinkCheck.unknown) return;
    _checkedId = id;
    _youTubeTitle = null;
    _channel = null;
    if (id == null) {
      _check = link.trim().isEmpty ? LinkCheck.empty : LinkCheck.invalid;
      notifyListeners();
      return;
    }
    _check = LinkCheck.checking;
    notifyListeners();
    LinkCheck check;
    YouTubeInfo? info;
    try {
      info = await _info.lookUp(id);
      check = info == null ? LinkCheck.notEmbeddable : LinkCheck.embeddable;
    } on Exception {
      check = LinkCheck.unknown;
    }
    // A newer link was pasted while this one was checked.
    if (_checkedId != id || _disposed) return;
    _check = check;
    _youTubeTitle = info?.title;
    _channel = info?.channel;
    notifyListeners();
  }

  Future<Result<String>> _save(TeamVideo draft) async {
    if (!canEdit) {
      return Result.error(Exception('Only admins can post videos.'));
    }
    if (TeamVideo.youtubeIdFrom(draft.youtubeId) != draft.youtubeId) {
      return Result.error(Exception('Paste a YouTube link.'));
    }
    final title = draft.title.trim().isNotEmpty
        ? draft.title.trim()
        : (_youTubeTitle ?? '').trim();
    if (title.isEmpty) {
      return Result.error(Exception('Give the video a title.'));
    }
    final user = _auth.currentUser;
    if (user == null) return Result.error(Exception('Sign in to post.'));
    return _videos.saveVideo(
      teamId,
      draft.copyWith(
        id: videoId ?? '',
        title: title.length > TeamVideo.maxTitle
            ? title.substring(0, TeamVideo.maxTitle)
            : title,
      ),
      user,
    );
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    load.dispose();
    save.dispose();
    super.dispose();
  }
}
