/// The server flags in the Firestore document `meta/flags` that the app acts
/// on besides the older kill switches (`FeatureFlags`): the lowest allowed
/// build per platform and whether video upload is open. The contract is
/// docs/specifications/contracts/meta-flags.md; this mirrors
/// `parseMetaFlags` and `isBuildAllowed` in packages/shared/src/meta_flags.ts
/// (same test vectors in test/domain/meta_flags_test.dart).
library;

/// What people are told when video upload is closed (`videoUploads` is not
/// true): the same words as the server's refusal.
class VideoUploadsClosedException implements Exception {
  const VideoUploadsClosedException();

  @override
  String toString() => "Video uploads aren't available right now.";
}

const videoUploadsClosed = VideoUploadsClosedException();

/// The platforms that have a build number gate. (The website has none.)
enum AppPlatform { ios, android }

class MetaFlags {
  const MetaFlags({
    this.minBuildIos = 0,
    this.minBuildAndroid = 0,
    this.videoUploads = false,
  });

  /// What applies when a field is missing, malformed or unreadable: no build
  /// gate, video uploads off.
  static const defaults = MetaFlags();

  /// Reads `meta/flags` data field by field: anything missing or of the wrong
  /// type takes its default, so a typo in the console never locks anyone out
  /// (`minBuild`) or opens video uploads (`videoUploads`).
  factory MetaFlags.parse(Object? data) {
    final d = data is Map ? data : const {};
    final mb = d['minBuild'] is Map ? d['minBuild'] as Map : const {};
    return MetaFlags(
      minBuildIos: _buildNumber(mb['ios']),
      minBuildAndroid: _buildNumber(mb['android']),
      videoUploads: d['videoUploads'] == true,
    );
  }

  /// Lowest build allowed to run on iOS; 0 means no gate.
  final int minBuildIos;

  /// Lowest build allowed to run on Android; 0 means no gate.
  final int minBuildAndroid;

  /// Whether native video upload is open.
  final bool videoUploads;

  int minBuildFor(AppPlatform platform) => switch (platform) {
    AppPlatform.ios => minBuildIos,
    AppPlatform.android => minBuildAndroid,
  };

  /// Whether [build] may run on [platform]. [flags] null (the read failed or
  /// timed out) allows it: the gate fails OPEN, an outage must not lock
  /// everyone out.
  static bool isBuildAllowed(
    MetaFlags? flags,
    AppPlatform platform,
    int build,
  ) => flags == null || build >= flags.minBuildFor(platform);

  @override
  bool operator ==(Object other) =>
      other is MetaFlags &&
      other.minBuildIos == minBuildIos &&
      other.minBuildAndroid == minBuildAndroid &&
      other.videoUploads == videoUploads;

  @override
  int get hashCode => Object.hash(minBuildIos, minBuildAndroid, videoUploads);

  @override
  String toString() =>
      'MetaFlags(ios: $minBuildIos, android: $minBuildAndroid, '
      'videoUploads: $videoUploads)';
}

/// A whole number >= 0 and under 2^53, else 0. Firestore may hand a whole
/// number back as an int or a double; the website sees both as one number.
int _buildNumber(Object? v) {
  if (v is int) return v >= 0 ? v : 0;
  if (v is double && v.isFinite && v >= 0 && v == v.truncateToDouble()) {
    return v <= 9007199254740991 ? v.toInt() : 0;
  }
  return 0;
}
