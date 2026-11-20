import 'package:media_kit/media_kit.dart' hide PlayerState;
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../../data/services/synced_video.dart';

// [SyncedVideoController]s over the two players: media_kit for uploads
// and YouTube's iframe player for links. Watch together drives them; a
// video's page seeks them to its notes (F4).

/// An uploaded video in media_kit.
class MediaKitVideoController implements SyncedVideoController {
  MediaKitVideoController(this._p);

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

Duration _seconds(num s) => Duration(milliseconds: (s * 1000).round());

/// A YouTube link in the iframe player.
class IframeVideoController implements SyncedVideoController {
  IframeVideoController(this._c);

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
