import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' hide PlayerState;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../../data/services/synced_video.dart';
import '../../../domain/models/team_video.dart';
import 'video_controllers.dart';
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
    widget.onController(MediaKitVideoController(_player));
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
    widget.onController(IframeVideoController(_controller));
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
