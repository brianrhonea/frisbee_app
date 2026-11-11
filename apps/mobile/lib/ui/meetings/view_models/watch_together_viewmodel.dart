import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/meeting/meeting_repository.dart';
import '../../../data/repositories/video/video_repository.dart';
import '../../../data/services/synced_video.dart';
import '../../../domain/models/app_user.dart';
import '../../../domain/models/meeting_playback.dart';
import '../../../domain/models/team_video.dart';
import '../../../domain/models/video_folder.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// Watch together in a meeting: an admin, the presenter, plays a team
/// video and everyone's player follows: play, pause, seek and which video.
/// Each person plays it on their own device, so it's full quality, not a
/// screen share.
///
/// The shared state is a [MeetingPlayback]. Once a second ([tick]) a
/// viewer's player is nudged to match it: play or pause, and a seek when
/// it's more than [tolerance] off. The presenter's player is the source of
/// truth; while it plays it rewrites the state every [heartbeat] so
/// viewers correct for its buffering.
class WatchTogetherViewModel extends ChangeNotifier {
  WatchTogetherViewModel({
    required this.teamId,
    required this.meetingId,
    required MeetingRepository meetingRepository,
    required VideoRepository videoRepository,
    required this.user,
    required this.canControl,
    DateTime Function()? clock,
    bool autoTick = true,
  }) : _meetings = meetingRepository,
       _videoRepo = videoRepository,
       _now = clock ?? DateTime.now,
       _autoTick = autoTick {
    show = Command1<void, String>(_show);
    play = Command0<void>(() => _transport(playing: true));
    pause = Command0<void>(() => _transport(playing: false));
    seek = Command1<void, Duration>((d) => _transport(position: d));
    stop = Command0<void>(_stop);
    takeControl = Command0<void>(_takeControl);
    _subs = [
      _meetings.watchPlayback(teamId, meetingId).listen(_onPlayback),
      _videoRepo.watchVideos(teamId).listen((v) {
        _videos = v;
        _loadUrl();
        notifyListeners();
      }, onError: (_) {}),
      _videoRepo.watchFolders(teamId).listen((f) {
        _folders = f;
        notifyListeners();
      }, onError: (_) {}),
    ];
  }

  static const tolerance = Duration(milliseconds: 1500);
  static const heartbeat = Duration(seconds: 10);

  final String teamId;
  final String meetingId;
  final AppUser user;

  /// Admins: start, drive, take over and stop.
  final bool canControl;
  final MeetingRepository _meetings;
  final VideoRepository _videoRepo;
  final DateTime Function() _now;
  final bool _autoTick;
  late final List<StreamSubscription<Object?>> _subs;
  Timer? _timer;
  bool _disposed = false;

  /// Admins: puts a video up for everyone, paused at the start.
  late final Command1<void, String> show;
  late final Command0<void> play;
  late final Command0<void> pause;
  late final Command1<void, Duration> seek;

  /// Admins: back to the call for everyone.
  late final Command0<void> stop;

  /// Admins: become the presenter.
  late final Command0<void> takeControl;

  MeetingPlayback? _playback;
  MeetingPlayback? get playback => _playback;
  bool get active => _playback != null;

  List<TeamVideo> _videos = const [];

  /// The team's videos, newest first, to pick from.
  List<TeamVideo> get videos => _videos;

  List<VideoFolder> _folders = const [];
  List<VideoFolder> get folders => _folders;

  /// The video being watched; null when none, or it was removed.
  TeamVideo? get video => switch (_playback) {
    final p? => _videos.where((v) => v.id == p.videoId).firstOrNull,
    null => null,
  };

  bool get isPresenter => _playback?.presenterId == user.uid;

  /// This user drives playback.
  bool get controlling => canControl && isPresenter;

  /// Where to stream an upload from.
  String? _fileUrl;
  String? get fileUrl => _fileUrl;
  String? _urlFor;
  bool _urlFailed = false;
  bool get fileFailed => _urlFailed;

  SyncedVideoController? _controller;
  double _volume = 1;

  /// The local player's last report, for the scrubber.
  PlayerStatus? _status;
  Duration get position => _status?.position ?? Duration.zero;
  Duration? get duration => _status?.duration;
  bool get localPlaying => _status?.playing ?? false;

  /// The player won't start on its own (autoplay blocked); the user has
  /// to tap it.
  bool _needsTap = false;
  bool get needsTap => _needsTap;
  int _stalled = 0;

  DateTime? _lastWrite;

  void _onPlayback(MeetingPlayback? p) {
    final videoChanged = p?.videoId != _playback?.videoId;
    _playback = p;
    // Ticks only while there's something to watch.
    if (p == null) {
      _timer?.cancel();
      _timer = null;
    } else if (_autoTick) {
      _timer ??= Timer.periodic(const Duration(seconds: 1), (_) => tick());
    }
    if (videoChanged) {
      _status = null;
      _needsTap = false;
      _stalled = 0;
    }
    _loadUrl();
    notifyListeners();
    // Apply play, pause and seeks straight away rather than at the next
    // tick, so everyone moves together.
    if (!videoChanged) unawaited(tick());
  }

  void _loadUrl() {
    final file = video?.file;
    if (file == null || _urlFor == file.path) return;
    _urlFor = file.path;
    _fileUrl = null;
    _urlFailed = false;
    unawaited(
      _videoRepo.fileUrl(file).then((r) {
        if (_disposed || _urlFor != file.path) return;
        switch (r) {
          case Ok(:final value):
            _fileUrl = value;
          case Error():
            _urlFailed = true;
        }
        notifyListeners();
      }),
    );
  }

  /// The player widget hands over its controller once it's built, and
  /// null when it goes away.
  void attach(SyncedVideoController? controller) {
    _controller = controller;
    _status = null;
    if (controller != null) {
      unawaited(controller.setVolume(_volume));
      unawaited(tick());
    }
  }

  /// Follows the call's output volume and mute, 0–1.
  void setVolume(double volume) {
    _volume = volume.clamp(0.0, 1.0);
    unawaited(_controller?.setVolume(_volume));
  }

  bool _ticking = false;

  /// Matches the local player to [playback]; see the class docs.
  @visibleForTesting
  Future<void> tick() async {
    final c = _controller;
    final p = _playback;
    if (c == null || p == null || _ticking) return;
    _ticking = true;
    try {
      final s = await c.status();
      if (_disposed || s == null || !identical(c, _controller)) return;
      _status = s;
      if (controlling) {
        await _presenterTick(p, s);
      } else {
        await _follow(c, p, s);
      }
      if (!_disposed) notifyListeners();
    } finally {
      _ticking = false;
    }
  }

  Future<void> _follow(
    SyncedVideoController c,
    MeetingPlayback p,
    PlayerStatus s,
  ) async {
    var target = p.positionAt(_now());
    if (s.duration case final d? when d > Duration.zero && target > d) {
      target = d;
    }
    if (p.playing && !s.playing) {
      await c.play();
      // Still not playing after a few tries: the platform wants a tap.
      _needsTap = ++_stalled >= 3;
    } else {
      _stalled = 0;
      _needsTap = false;
      if (!p.playing && s.playing) await c.pause();
    }
    if ((s.position - target).abs() > tolerance) await c.seekTo(target);
  }

  Future<void> _presenterTick(MeetingPlayback p, PlayerStatus s) async {
    if (!p.playing) return;
    final ended = switch (s.duration) {
      final d? when d > Duration.zero =>
        !s.playing && s.position >= d - const Duration(seconds: 1),
      _ => false,
    };
    if (ended) {
      await _write(p.copyWith(playing: false, position: s.position));
    } else if (s.playing &&
        (_lastWrite == null || _now().difference(_lastWrite!) >= heartbeat)) {
      await _write(p.copyWith(position: s.position));
    }
  }

  Future<Result<void>> _write(MeetingPlayback p) {
    _lastWrite = _now();
    return _meetings.setPlayback(teamId, meetingId, p);
  }

  Result<void>? _notAllowed() => canControl
      ? null
      : Result.error(Exception('Only admins can play videos for everyone.'));

  Future<Result<void>> _show(String videoId) async {
    if (_notAllowed() case final e?) return e;
    return _write(
      MeetingPlayback(
        videoId: videoId,
        playing: false,
        position: Duration.zero,
        presenterId: user.uid,
        presenterName: user.label,
      ),
    );
  }

  /// Play, pause or seek, from the presenter's own player position.
  Future<Result<void>> _transport({bool? playing, Duration? position}) async {
    if (_notAllowed() case final e?) return e;
    final p = _playback;
    if (p == null) return Result.error(Exception('Pick a video first.'));
    final c = _controller;
    final at =
        position ?? (await c?.status())?.position ?? p.positionAt(_now());
    final next = p.copyWith(
      playing: playing ?? p.playing,
      position: at,
      presenterId: user.uid,
      presenterName: user.label,
    );
    // Move the presenter's own player now; viewers follow the write.
    if (c != null) {
      if (position != null) await c.seekTo(position);
      if (playing == true) await c.play();
      if (playing == false) await c.pause();
    }
    return _write(next);
  }

  Future<Result<void>> _takeControl() async {
    if (_notAllowed() case final e?) return e;
    final p = _playback;
    if (p == null) return Result.error(Exception('Nothing is playing.'));
    return _write(
      p.copyWith(
        position: _status?.position ?? p.positionAt(_now()),
        presenterId: user.uid,
        presenterName: user.label,
      ),
    );
  }

  Future<Result<void>> _stop() async {
    if (_notAllowed() case final e?) return e;
    return _meetings.stopPlayback(teamId, meetingId);
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    for (final c in [show, play, pause, seek, stop, takeControl]) {
      c.dispose();
    }
    super.dispose();
  }
}
