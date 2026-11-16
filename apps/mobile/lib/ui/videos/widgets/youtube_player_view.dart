import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../../domain/models/team_video.dart';

/// Builds the player for a video; tests swap in a stand-in, since the real
/// players need a platform web view.
typedef YouTubePlayerBuilder = Widget Function(String youtubeId);

/// YouTube's own embedded player, 16:9: the iframe player on Android and
/// iOS, elsewhere the thumbnail with a link to YouTube.
Widget youTubePlayer(String youtubeId) => switch (defaultTargetPlatform) {
  TargetPlatform.android ||
  TargetPlatform.iOS => _IframePlayer(youtubeId: youtubeId),
  _ => WatchOnYouTube(youtubeId: youtubeId),
};

class _IframePlayer extends StatefulWidget {
  const _IframePlayer({required this.youtubeId});

  final String youtubeId;

  @override
  State<_IframePlayer> createState() => _IframePlayerState();
}

class _IframePlayerState extends State<_IframePlayer> {
  late final _controller = YoutubePlayerController.fromVideoId(
    videoId: widget.youtubeId,
    params: const YoutubePlayerParams(
      showFullscreenButton: true,
      strictRelatedVideos: true,
    ),
  );

  @override
  void dispose() {
    unawaited(_controller.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      YoutubePlayer(controller: _controller, aspectRatio: 16 / 9);
}

/// The video's thumbnail with a play button that opens it on YouTube.
class WatchOnYouTube extends StatelessWidget {
  const WatchOnYouTube({super.key, required this.youtubeId});

  final String youtubeId;

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 16 / 9,
    child: Material(
      color: Colors.black,
      child: InkWell(
        onTap: () => launchUrl(
          Uri.parse(TeamVideo.watchUrlOf(youtubeId)),
          mode: LaunchMode.externalApplication,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            VideoThumbnail(youtubeId: youtubeId),
            const Center(
              child: Chip(
                avatar: Icon(Icons.play_arrow),
                label: Text('Watch on YouTube'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// YouTube's thumbnail for a video, cropped to fill; a placeholder while
/// it loads or if it can't.
class VideoThumbnail extends StatelessWidget {
  const VideoThumbnail({super.key, required this.youtubeId});

  final String youtubeId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Icon(Icons.smart_display_outlined, color: scheme.outline),
    );
    return Image.network(
      TeamVideo.thumbnailUrlOf(youtubeId),
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => placeholder,
      loadingBuilder: (_, child, progress) =>
          progress == null ? child : placeholder,
    );
  }
}
