import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:media_kit/media_kit.dart' hide PlayerState;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:webview_windows/webview_windows.dart' as win;
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
/// media_kit for uploads, and YouTube's player for links (the iframe player
/// on Android, iOS and macOS; the IFrame API page in WebView2 on Windows).
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
    _ when kIsWeb => _IframePlayer(
      id: video.youtubeId,
      onController: onController,
    ),
    TargetPlatform.android || TargetPlatform.iOS || TargetPlatform.macOS =>
      _IframePlayer(id: video.youtubeId, onController: onController),
    TargetPlatform.windows => _WindowsPlayer(
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

// YouTube: WebView2 on Windows -----------------------------------------------

class _WindowsPlayer extends StatefulWidget {
  const _WindowsPlayer({required this.id, required this.onController});

  final String id;
  final ValueChanged<SyncedVideoController?> onController;

  @override
  State<_WindowsPlayer> createState() => _WindowsPlayerState();
}

class _WindowsPlayerState extends State<_WindowsPlayer> {
  static final _log = Logger('SyncedYouTubePlayer');

  final _controller = win.WebviewController();
  var _ready = false;
  var _failed = false;

  /// The page, written once per run beside the regular player page.
  static Future<String> _folder() async {
    final dir = Directory('${Directory.systemTemp.path}/ultiup_player');
    await dir.create(recursive: true);
    await File('${dir.path}/synced.html').writeAsString(_syncedHtml);
    return dir.path;
  }

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      if (await win.WebviewController.getWebViewVersion() == null) {
        throw StateError('WebView2 runtime is not installed');
      }
      await ensureWebViewEnvironment();
      final folder = await _folder();
      await _controller.initialize();
      await _controller.addVirtualHostNameMapping(
        youTubePlayerHost,
        folder,
        win.WebviewHostResourceAccessKind.allow,
      );
      await _controller.setPopupWindowPolicy(win.WebviewPopupWindowPolicy.deny);
      await _controller.setBackgroundColor(Colors.black);
      await _controller.loadUrl(
        'https://$youTubePlayerHost/synced.html?v=${widget.id}',
      );
      if (!mounted) return;
      setState(() => _ready = true);
      widget.onController(_WebViewController(_controller));
    } on Object catch (e) {
      _log.warning('Windows synced player failed', e);
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    widget.onController(null);
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _failed
      ? WatchOnYouTube(youtubeId: widget.id)
      : !_ready
      ? const _Loading()
      : _fit(win.Webview(_controller));
}

/// Talks to `window.ultiup` in [_syncedHtml].
class _WebViewController implements SyncedVideoController {
  _WebViewController(this._c);

  final win.WebviewController _c;

  Future<dynamic> _run(String js) async {
    try {
      return await _c.executeScript(js);
    } on Object {
      // The page is reloading or the view is going; the next tick retries.
      return null;
    }
  }

  @override
  Future<void> play() => _run('ultiup.play()');

  @override
  Future<void> pause() => _run('ultiup.pause()');

  @override
  Future<void> seekTo(Duration position) =>
      _run('ultiup.seek(${position.inMilliseconds / 1000})');

  @override
  Future<void> setVolume(double volume) =>
      _run('ultiup.volume(${(volume * 100).round()})');

  @override
  Future<PlayerStatus?> status() async {
    final s = await _run('ultiup.status()');
    if (s is! Map) return null;
    final duration = s['d'];
    if (duration is! num || duration <= 0) return null;
    final state = s['s'];
    return (
      position: _seconds(s['t'] as num? ?? 0),
      duration: _seconds(duration),
      // 1 playing, 3 buffering.
      playing: state == 1 || state == 3,
    );
  }
}

/// YouTube's IFrame Player API with its controls hidden, driven through
/// `window.ultiup`. The video id is checked before it's used.
const _syncedHtml = '''<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  html, body { margin: 0; height: 100%; background: #000; overflow: hidden; }
  #p, iframe { border: 0; width: 100%; height: 100%; }
</style>
</head>
<body>
<div id="p"></div>
<script>
  var id = new URLSearchParams(location.search).get('v') || '';
  var player = null, ready = false;
  window.ultiup = {
    play: function () { if (ready) player.playVideo(); },
    pause: function () { if (ready) player.pauseVideo(); },
    seek: function (s) { if (ready) player.seekTo(s, true); },
    volume: function (v) { if (ready) player.setVolume(v); },
    status: function () {
      if (!ready) return null;
      return { t: player.getCurrentTime(), d: player.getDuration(),
               s: player.getPlayerState() };
    }
  };
  function onYouTubeIframeAPIReady() {
    if (!/^[A-Za-z0-9_-]{11}\$/.test(id)) return;
    player = new YT.Player('p', {
      host: 'https://www.youtube-nocookie.com',
      videoId: id,
      playerVars: { controls: 0, disablekb: 1, rel: 0, playsinline: 1,
                    fs: 0, origin: location.origin },
      events: { onReady: function () { ready = true; } }
    });
  }
</script>
<script src="https://www.youtube.com/iframe_api"></script>
</body>
</html>
''';
