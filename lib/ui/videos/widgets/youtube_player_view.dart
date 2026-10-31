import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_windows/webview_windows.dart' as win;
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../../domain/models/team_video.dart';

/// Builds the player for a video; tests swap in a stand-in, since the real
/// players need a platform web view.
typedef YouTubePlayerBuilder = Widget Function(String youtubeId);

/// YouTube's own embedded player, 16:9: the iframe player on Android, iOS
/// and macOS, the same embed in an Edge WebView2 on Windows, and elsewhere
/// the thumbnail with a link to YouTube.
Widget youTubePlayer(String youtubeId) => switch (defaultTargetPlatform) {
  _ when kIsWeb => _IframePlayer(youtubeId: youtubeId),
  TargetPlatform.android ||
  TargetPlatform.iOS ||
  TargetPlatform.macOS => _IframePlayer(youtubeId: youtubeId),
  TargetPlatform.windows => _WindowsPlayer(youtubeId: youtubeId),
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

/// The embed in an Edge WebView2. YouTube's embed won't play without a
/// page origin, so a small player page is served from a virtual https host
/// mapped to a temp folder, rather than loaded as a bare string.
class _WindowsPlayer extends StatefulWidget {
  const _WindowsPlayer({required this.youtubeId});

  final String youtubeId;

  @override
  State<_WindowsPlayer> createState() => _WindowsPlayerState();
}

enum _WinState { starting, ready, failed }

class _WindowsPlayerState extends State<_WindowsPlayer> {
  static final _log = Logger('YouTubePlayer');
  static const _host = 'player.ultiup.app';

  final _controller = win.WebviewController();
  var _state = _WinState.starting;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  /// The player page, written once per run. The video id comes from the
  /// query string and is checked before it goes into the embed URL.
  static Future<String> _playerFolder() async {
    final dir = Directory('${Directory.systemTemp.path}/ultiup_player');
    await dir.create(recursive: true);
    await File('${dir.path}/player.html').writeAsString(_playerHtml);
    return dir.path;
  }

  Future<void> _start() async {
    try {
      if (await win.WebviewController.getWebViewVersion() == null) {
        throw StateError('WebView2 runtime is not installed');
      }
      final folder = await _playerFolder();
      await _controller.initialize();
      await _controller.addVirtualHostNameMapping(
        _host,
        folder,
        win.WebviewHostResourceAccessKind.allow,
      );
      // YouTube's title and logo links open new windows; keep them out.
      await _controller.setPopupWindowPolicy(win.WebviewPopupWindowPolicy.deny);
      await _controller.setBackgroundColor(Colors.black);
      await _controller.loadUrl(
        'https://$_host/player.html?v=${widget.youtubeId}',
      );
      if (mounted) setState(() => _state = _WinState.ready);
    } on Object catch (e) {
      _log.warning('Windows player failed', e);
      if (mounted) setState(() => _state = _WinState.failed);
    }
  }

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => switch (_state) {
    _WinState.failed => WatchOnYouTube(youtubeId: widget.youtubeId),
    _WinState.starting => const AspectRatio(
      aspectRatio: 16 / 9,
      child: ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator()),
      ),
    ),
    _WinState.ready => AspectRatio(
      aspectRatio: 16 / 9,
      child: win.Webview(_controller),
    ),
  };
}

const _playerHtml = '''<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  html, body { margin: 0; height: 100%; background: #000; overflow: hidden; }
  iframe { border: 0; width: 100%; height: 100%; }
</style>
</head>
<body>
<script>
  var id = new URLSearchParams(location.search).get('v') || '';
  if (/^[A-Za-z0-9_-]{11}\$/.test(id)) {
    var f = document.createElement('iframe');
    f.src = 'https://www.youtube-nocookie.com/embed/' + id +
        '?rel=0&playsinline=1&origin=' + encodeURIComponent(location.origin);
    f.allow = 'autoplay; encrypted-media; picture-in-picture; fullscreen';
    f.allowFullscreen = true;
    f.referrerPolicy = 'strict-origin-when-cross-origin';
    document.body.appendChild(f);
  }
</script>
</body>
</html>
''';

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
