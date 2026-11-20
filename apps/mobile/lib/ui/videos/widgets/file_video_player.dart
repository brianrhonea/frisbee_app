import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../data/services/synced_video.dart';
import 'video_controllers.dart';

/// Builds the player for an uploaded video's stream URL; tests swap in a
/// stand-in, since media_kit needs its native libraries.
typedef FileVideoPlayerBuilder = Widget Function(String url);

/// The same, handing [onController] a controller to seek it with (a
/// video's notes, F4), and null when it goes.
typedef SeekableFilePlayerBuilder =
    Widget Function(
      String url, [
      ValueChanged<SyncedVideoController?>? onController,
    ]);

/// Plays an uploaded video file with media_kit (libmpv), on every platform, with
/// its standard controls.
Widget fileVideoPlayer(
  String url, [
  ValueChanged<SyncedVideoController?>? onController,
]) => _FilePlayer(url: url, onController: onController);

class _FilePlayer extends StatefulWidget {
  const _FilePlayer({required this.url, this.onController});

  final String url;
  final ValueChanged<SyncedVideoController?>? onController;

  @override
  State<_FilePlayer> createState() => _FilePlayerState();
}

class _FilePlayerState extends State<_FilePlayer> {
  late final _player = Player();
  late final _controller = VideoController(_player);

  @override
  void initState() {
    super.initState();
    unawaited(_player.open(Media(widget.url), play: false));
    widget.onController?.call(MediaKitVideoController(_player));
  }

  @override
  void dispose() {
    widget.onController?.call(null);
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 16 / 9,
    child: ColoredBox(
      color: Colors.black,
      child: Video(controller: _controller),
    ),
  );
}
