import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' hide PlayerState;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../../data/services/synced_video.dart';
import '../../../domain/models/team_video.dart';
import 'youtube_player_view.dart';

/// Builds a player that something else drives (watch together), and hands
/// its controller to [onController] once ready, and null when it goes.
/// [fileUrl] is the stream URL for an upload; null while it loads. Tests
/// swap in a stand-in, since the real players need native views.
typedef SyncedPlayerBuilder =
    Widget Function(
      TeamVideo video,
      String? fileUrl,
      ValueChanged<SyncedVideoController?> onController,
    );

/// A [SyncedVideoController] for a team video, with no controls of its own:
/// media_kit for uploads, and YouTube's iframe player for links.
Widget syncedVideoPlayer(
  TeamVideo video,
  String? fileUrl,
  ValueChanged<SyncedVideoController?> onController,
) {
  if (!video.isYouTube) {
    return fileUrl == null
        ? const _Loading()
        : _FilePlayer(url: fileUrl, onController: onController);
  }
  return switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => _IframePlayer(
      id: video.youtubeId,
      onController: onController,
    ),
    _ => WatchOnYouTube(youtubeId: video.youtubeId),
  };
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}

/// Fits the player in whatever space it's given, at 16:9.
Widget _fit(Widget player) => Center(
  child: AspectRatio(aspectRatio: 16 / 9, child: player),
);

// Uploads ---------------------------------------------------------------------

class _FilePlayer extends StatefulWidget {
  const _FilePlayer({required this.url, required this.onController});

  final String url;
  final ValueChanged<SyncedVideoController?> onController;

  @override
  State<_FilePlayer> createState() => _FilePlayerState();
}

class _FilePlayerState extends State<_FilePlayer> {
  late final _player = Player();
  late final _video = VideoController(_player);

  @override
  void initState() {
    super.initState();
    unawaited(_player.open(Media(widget.url), play: false));
    widget.onController(_MediaKitController(_player));
  }

  @override
  void dispose() {
    widget.onController(null);
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _fit(Video(controller: _video, controls: NoVideoControls));
}

class _MediaKitController implements SyncedVideoController {
  _MediaKitController(this._p);

  final Player _p;

  @override
  Future<void> play() => _p.play();

  @override
  Future<void> pause() => _p.pause();

  @override
  Future<void> seekTo(Duration position) => _p.seek(position);

  @override
  Future<void> setVolume(double volume) => _p.setVolume(volume * 100);

  @override
  Future<PlayerStatus?> status() async {
    final s = _p.state;
    // No duration until the file has loaded; seeks before then are lost.
    if (s.duration <= Duration.zero) return null;
    return (position: s.position, duration: s.duration, playing: s.playing);
  }
}

// YouTube: iframe player ------------------------------------------------------

class _IframePlayer extends StatefulWidget {
  const _IframePlayer({required this.id, required this.onController});

  final String id;
  final ValueChanged<SyncedVideoController?> onController;

  @override
  State<_IframePlayer> createState() => _IframePlayerState();
}

class _IframePlayerState extends State<_IframePlayer> {
  late final _controller = YoutubePlayerController.fromVideoId(
    videoId: widget.id,
    params: const YoutubePlayerParams(
      showControls: false,
      showFullscreenButton: false,
      strictRelatedVideos: true,
    ),
  );

  @override
  void initState() {
    super.initState();
    widget.onController(_IframeController(_controller));
  }

  @override
  void dispose() {
    widget.onController(null);
    unawaited(_controller.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _fit(YoutubePlayer(controller: _controller, aspectRatio: 16 / 9));
}

Duration _seconds(num s) => Duration(milliseconds: (s * 1000).round());

class _IframeController implements SyncedVideoController {
  _IframeController(this._c);

  final YoutubePlayerController _c;

  @override
  Future<void> play() => _c.playVideo();

  @override
  Future<void> pause() => _c.pauseVideo();

  @override
  Future<void> seekTo(Duration position) =>
      _c.seekTo(seconds: position.inMilliseconds / 1000, allowSeekAhead: true);

  @override
  Future<void> setVolume(double volume) => _c.setVolume((volume * 100).round());

  @override
  Future<PlayerStatus?> status() async {
    final duration = await _c.duration;
    if (duration <= 0) return null;
    final state = await _c.playerState;
    return (
      position: _seconds(await _c.currentTime),
      duration: _seconds(duration),
      // Buffering counts: it's on its way, so don't press play again.
      playing: state == PlayerState.playing || state == PlayerState.buffering,
    );
  }
}
