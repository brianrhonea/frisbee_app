import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../data/repositories/video/video_repository.dart';
import '../../../data/services/file_picker_service.dart';
import '../../../data/services/youtube_info_service.dart';
import '../../../domain/models/team.dart';
import '../../../domain/models/team_video.dart';
import '../../../domain/models/video_folder.dart';
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

/// Where a new video comes from.
enum VideoSource { youTube, upload }

/// Posts or edits a team video. Form state lives in the screen; this loads
/// the original, checks YouTube links or picks a video file, and saves.
class VideoEditorViewModel extends ChangeNotifier {
  VideoEditorViewModel({
    required this.teamId,
    required this.videoId,
    required VideoRepository videoRepository,
    required TeamRepository teamRepository,
    required AuthRepository authRepository,
    required YouTubeInfoService youTubeInfo,
    required FilePickerService filePicker,
    this.initialFolderId,
  }) : _videos = videoRepository,
       _teams = teamRepository,
       _auth = authRepository,
       _info = youTubeInfo,
       _picker = filePicker {
    load = Command0<void>(_load)..execute();
    save = Command1<String, TeamVideo>(_save);
  }

  final String teamId;

  /// Null when posting a new video.
  final String? videoId;

  /// The folder a new video starts in, e.g. the one being viewed.
  final String? initialFolderId;
  final VideoRepository _videos;
  final TeamRepository _teams;
  final AuthRepository _auth;
  final YouTubeInfoService _info;
  final FilePickerService _picker;

  late final Command0<void> load;

  /// Result value is the saved video's id.
  late final Command1<String, TeamVideo> save;

  bool get isNew => videoId == null;

  Team? _team;
  TeamVideo? _original;

  bool get canEdit => _team?.canEdit(_auth.currentUser?.uid ?? '') ?? false;

  /// Starting values for the form.
  TeamVideo get initial =>
      _original ??
      TeamVideo(
        id: '',
        folderId: _folders.any((f) => f.id == initialFolderId)
            ? initialFolderId!
            : '',
      );

  List<VideoFolder> _folders = const [];

  /// The team's folders, A–Z, to file the video in.
  List<VideoFolder> get folders => _folders;

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

  VideoSource _source = VideoSource.youTube;

  /// A new video's source; an existing one keeps its own.
  VideoSource get source => switch (_original) {
    final v? => v.isYouTube ? VideoSource.youTube : VideoSource.upload,
    null => _source,
  };

  set source(VideoSource value) {
    if (!isNew || value == _source) return;
    _source = value;
    notifyListeners();
  }

  /// Bytes the team's uploads already use, out of
  /// [TeamVideo.teamQuotaBytes].
  int _usedBytes = 0;
  int get usedBytes => _usedBytes;

  /// The video file picked to upload.
  PickedFile? _file;
  PickedFile? get pickedFile => _file;

  /// Why [pickedFile] can't be uploaded, if it can't.
  String? _fileProblem;
  String? get fileProblem => _fileProblem;

  /// 0–1 while uploading.
  double? _progress;
  double? get uploadProgress => _progress;

  /// Picks a video file and checks its type and the per-file and per-team
  /// limits.
  Future<void> pickFile() async {
    final file = await _picker.pickVideo(VideoFile.types.keys.toList());
    if (file == null || _disposed) return;
    _file = file;
    final size = file.size;
    _fileProblem = file.path == null
        ? "This device can't upload files that big."
        : VideoFile.contentTypeFor(file.name) == null
        ? "UltiUP can't play that kind of file. Use MP4, MOV, MKV, WebM, "
              'AVI, WMV, MPEG or 3GP.'
        : size == null || size <= 0
        ? "Couldn't read that file."
        : size > TeamVideo.maxFileBytes
        ? 'Videos can be up to '
              '${TeamVideo.formatBytes(TeamVideo.maxFileBytes)}; this one is '
              '${TeamVideo.formatBytes(size)}. Upload longer videos to YouTube.'
        : _usedBytes + size > TeamVideo.teamQuotaBytes
        ? 'The team has '
              '${TeamVideo.formatBytes(TeamVideo.teamQuotaBytes - _usedBytes)} '
              'of its ${TeamVideo.formatBytes(TeamVideo.teamQuotaBytes)} left. '
              'Remove an uploaded video, or use YouTube.'
        : null;
    notifyListeners();
  }

  Future<Result<void>> _load() async {
    try {
      _team = await _teams.watchTeam(teamId).first;
      _usedBytes = TeamVideo.bytesUsed(await _videos.watchVideos(teamId).first);
      _folders = await _videos.watchFolders(teamId).first;
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
    if (_original case final v? when v.isYouTube) await checkLink(v.youtubeId);
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
    final uploading = isNew && _source == VideoSource.upload;
    final keepsFile = _original?.isYouTube == false;
    if (!uploading &&
        !keepsFile &&
        TeamVideo.youtubeIdFrom(draft.youtubeId) != draft.youtubeId) {
      return Result.error(Exception('Paste a YouTube link.'));
    }
    final picked = _file;
    if (uploading && (picked == null || _fileProblem != null)) {
      return Result.error(
        Exception(_fileProblem ?? 'Pick a video file to upload.'),
      );
    }
    final title = draft.title.trim().isNotEmpty
        ? draft.title.trim()
        : (_youTubeTitle ?? '').trim();
    if (title.isEmpty) {
      return Result.error(Exception('Give the video a title.'));
    }
    final user = _auth.currentUser;
    if (user == null) return Result.error(Exception('Sign in to post.'));
    final video = draft.copyWith(
      id: videoId ?? '',
      title: title.length > TeamVideo.maxTitle
          ? title.substring(0, TeamVideo.maxTitle)
          : title,
    );
    if (!uploading) return _videos.saveVideo(teamId, video, user);
    _progress = 0;
    notifyListeners();
    final result = await _videos.uploadVideo(
      teamId,
      video,
      (path: picked!.path!, name: picked.name, size: picked.size!),
      user,
      onProgress: (p) {
        if (_disposed) return;
        _progress = p;
        notifyListeners();
      },
    );
    if (!_disposed) {
      _progress = null;
      notifyListeners();
    }
    return result;
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
