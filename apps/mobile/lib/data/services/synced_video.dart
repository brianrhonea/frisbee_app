/// What a player reports when asked.
typedef PlayerStatus = ({Duration position, Duration? duration, bool playing});

/// A video player that something else drives, as in a meeting's watch
/// together: it has no controls of its own. Implemented over media_kit for
/// uploads and YouTube's player for links (see `synced_video_player.dart`).
abstract class SyncedVideoController {
  Future<void> play();
  Future<void> pause();
  Future<void> seekTo(Duration position);

  /// 0–1.
  Future<void> setVolume(double volume);

  /// Where it is; null until the player is ready.
  Future<PlayerStatus?> status();
}
