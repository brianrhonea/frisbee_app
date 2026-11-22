import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/event/event_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../data/repositories/video/video_repository.dart';
import '../../../data/services/synced_video.dart';
import '../../../domain/models/team.dart';
import '../../../domain/models/team_event.dart';
import '../../../domain/models/team_video.dart';
import '../../../domain/models/video_comment.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// A note or comment to add: a note has [atMs], a clip [endMs] too.
typedef CommentDraft = ({String body, int? atMs, int? endMs});

/// Backs a video's page: the player and its description, its notes, clips
/// and comments (F4, F5), and the event it's tagged to (F6).
class VideoViewModel extends ChangeNotifier {
  VideoViewModel({
    required this.teamId,
    required this.videoId,
    required VideoRepository videoRepository,
    required TeamRepository teamRepository,
    required AuthRepository authRepository,
    EventRepository? eventRepository,
  }) : _videos = videoRepository,
       _auth = authRepository,
       _eventRepo = eventRepository {
    deleteVideo = Command0<void>(
      () => videoRepository.deleteVideo(teamId, videoId),
    );
    addComment = Command1<void, CommentDraft>(_addComment);
    deleteComment = Command1<void, String>(
      (id) => videoRepository.deleteComment(teamId, videoId, id),
    );
    tagEvent = Command1<void, String?>(
      (id) => videoRepository.tagEvent(teamId, videoId, id),
    );
    _subs = [
      videoRepository.watchVideo(teamId, videoId).listen((v) {
        _video = v;
        _loaded = true;
        _watchTaggedEvent();
        notifyListeners();
        if (v?.file case final file? when file.path != _urlFor) {
          unawaited(_loadUrl(file));
        }
      }, onError: _onError),
      teamRepository.watchTeam(teamId).listen((t) {
        _team = t;
        _watchEvents();
        notifyListeners();
      }, onError: _onError),
      videoRepository.watchComments(teamId, videoId).listen((list) {
        final split = VideoComment.split(list);
        _notes = split.notes;
        _comments = split.comments;
        notifyListeners();
        // Comments can't be read (e.g. rules not deployed yet): the page
        // still plays.
      }, onError: (Object _) {}),
    ];
  }

  final String teamId;
  final String videoId;
  final VideoRepository _videos;
  final AuthRepository _auth;
  final EventRepository? _eventRepo;
  late final List<StreamSubscription<Object?>> _subs;

  late final Command0<void> deleteVideo;

  /// Adds a comment, or a note or clip when it has a time.
  late final Command1<void, CommentDraft> addComment;

  /// Deletes a note or comment by id.
  late final Command1<void, String> deleteComment;

  /// Tags the video to an event by id; null untags it.
  late final Command1<void, String?> tagEvent;

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

  String get uid => _auth.currentUser?.uid ?? '';

  bool get canEdit => _team?.canEdit(uid) ?? false;

  // Notes, clips and comments (F4, F5) ----------------------------------------

  List<VideoComment> _notes = const [];
  List<VideoComment> _comments = const [];

  /// Notes and clips, by time.
  List<VideoComment> get notes => _notes;

  /// Plain comments, oldest first.
  List<VideoComment> get comments => _comments;

  /// Members add notes and comments, through the API.
  bool get canComment =>
      _videos.canUseVideoExtras && _team?.roleOf(uid) != null;

  /// Its author, or someone who manages the team.
  bool canDelete(VideoComment c) =>
      _videos.canUseVideoExtras && (c.authorId == uid || canEdit);

  SyncedVideoController? _player;

  /// The page's player, once it's ready (null when it goes, or when the
  /// platform's player can't seek, e.g. YouTube's thumbnail on desktop).
  void attachPlayer(SyncedVideoController? player) {
    if (identical(player, _player)) return;
    _player = player;
    // Players attach and detach while the tree builds: tell listeners after.
    scheduleMicrotask(() {
      if (!_disposed) notifyListeners();
    });
  }

  /// Whether notes can be pinned to the player's time and tapped to seek.
  bool get canSeek => _player != null;

  int? _noteStart;
  int? _noteEnd;

  /// Where the note being written starts, once marked.
  int? get noteStartMs => _noteStart;

  /// Where it ends (a clip), once marked.
  int? get noteEndMs => _noteEnd;

  /// Where the player is; null without one. A player that hasn't loaded
  /// yet (YouTube before it first plays) is at the start.
  Future<int?> _position() async {
    final player = _player;
    if (player == null) return null;
    return (await player.status())?.position.inMilliseconds ?? 0;
  }

  /// Pins the note being written to where the player is now.
  Future<void> markStart() async {
    final at = await _position();
    if (at == null || _disposed) return;
    _noteStart = at;
    if (_noteEnd case final end? when end <= at) _noteEnd = null;
    notifyListeners();
  }

  /// Ends it here, making it a clip; must be after its start (marked now
  /// if it wasn't).
  Future<void> markEnd() async {
    final at = await _position();
    if (at == null || _disposed) return;
    final start = _noteStart;
    if (start == null) {
      _noteStart = at;
    } else if (at > start) {
      _noteEnd = at;
    }
    notifyListeners();
  }

  /// Back to a plain note (no end).
  void clearEnd() {
    _noteEnd = null;
    notifyListeners();
  }

  /// Adds a note at the marked time (where the player is now, if none was
  /// marked), a clip when an end was marked too. Whether it was added.
  Future<bool> addNote(String body) async {
    if (_noteStart == null) await markStart();
    final at = _noteStart;
    if (at == null || _disposed) return false;
    await addComment.execute((body: body, atMs: at, endMs: _noteEnd));
    return addComment.completed;
  }

  /// Plays from a note's time.
  Future<void> seekTo(VideoComment note) async {
    final at = note.atMs;
    if (at == null) return;
    await _player?.seekTo(Duration(milliseconds: at));
    await _player?.play();
  }

  Future<Result<void>> _addComment(CommentDraft draft) async {
    final body = draft.body.trim();
    if (body.isEmpty) return Result.error(Exception('Write something first.'));
    final result = await _videos.addComment(
      teamId,
      videoId,
      body: body,
      atMs: draft.atMs,
      endMs: draft.atMs == null ? null : draft.endMs,
    );
    if (result is Ok && draft.atMs != null) {
      _noteStart = null;
      _noteEnd = null;
    }
    return result;
  }

  // The tagged event (F6) ------------------------------------------------------

  /// Managers tag videos, through the API, when this page can read events.
  bool get canTag => canEdit && _videos.canUseVideoExtras && _eventRepo != null;

  String? _eventFor;
  StreamSubscription<TeamEvent?>? _eventSub;
  TeamEvent? _taggedEvent;
  bool _taggedLoaded = false;

  /// The event the video is tagged to, once read; null while it loads, or
  /// when it was deleted or isn't readable ([taggedMissing]).
  TeamEvent? get taggedEvent => _taggedEvent;

  /// Tagged to an event that's gone or can't be seen.
  bool get taggedMissing =>
      (_video?.eventId.isNotEmpty ?? false) &&
      (_eventRepo == null || (_taggedLoaded && _taggedEvent == null));

  void _watchTaggedEvent() {
    final id = _video?.eventId ?? '';
    if (id == _eventFor) return;
    _eventFor = id;
    unawaited(_eventSub?.cancel());
    _eventSub = null;
    _taggedEvent = null;
    _taggedLoaded = false;
    final repo = _eventRepo;
    if (id.isEmpty || repo == null) return;
    _eventSub = repo
        .watchEvent(teamId, id)
        .listen(
          (e) {
            _taggedEvent = e;
            _taggedLoaded = true;
            notifyListeners();
          },
          onError: (Object _) {
            _taggedEvent = null;
            _taggedLoaded = true;
            notifyListeners();
          },
        );
  }

  StreamSubscription<List<TeamEvent>>? _eventsSub;
  List<TeamEvent> _events = const [];

  /// Events a manager can tag: the last year's and the next month's,
  /// newest first; in a community, only those for everyone.
  List<TeamEvent> get taggableEvents => _events;

  void _watchEvents() {
    final repo = _eventRepo;
    final team = _team;
    if (_eventsSub != null || repo == null || team == null || !canTag) return;
    final now = DateTime.now();
    _eventsSub = repo
        .watchEvents(
          teamId,
          since: now.subtract(const Duration(days: 365)),
          audience: team.eventAudienceOf(uid),
        )
        .listen((list) {
          final until = now.add(const Duration(days: 31));
          _events =
              list
                  .where(
                    (e) =>
                        e.startsAt.isBefore(until) &&
                        (!team.isOrganization ||
                            e.audience.contains('everyone')),
                  )
                  .toList()
                ..sort((a, b) => b.startsAt.compareTo(a.startsAt));
          notifyListeners();
        }, onError: (Object _) {});
  }

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
    unawaited(_eventSub?.cancel());
    unawaited(_eventsSub?.cancel());
    deleteVideo.dispose();
    addComment.dispose();
    deleteComment.dispose();
    tagEvent.dispose();
    super.dispose();
  }
}
