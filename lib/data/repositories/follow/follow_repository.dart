import '../../../domain/models/follow.dart';
import '../../../utils/result.dart';

/// What a user follows, at `users/{uid}/follows/{key}`, and how many follow
/// each target, at `followCounts/{key}` (kept by Cloud Functions).
abstract class FollowRepository {
  /// Everything [uid] follows, newest first.
  Stream<List<Follow>> watchFollows(String uid);

  /// [uid]'s follow of [key], or null when not following.
  Stream<Follow?> watchFollow(String uid, String key);

  /// Starts following [target]; [notify] turns on post notifications.
  Future<Result<void>> follow(
    String uid,
    FollowTarget target, {
    bool notify = false,
  });

  Future<Result<void>> unfollow(String uid, String key);

  /// Turns post notifications for one follow on or off.
  Future<Result<void>> setNotify(String uid, String key, bool notify);

  /// How many people follow [key], and, for a user key, how many targets
  /// that user follows.
  Stream<FollowCounts> watchCounts(String key);
}

class FollowCounts {
  const FollowCounts({this.followers = 0, this.following = 0});

  final int followers;
  final int following;

  factory FollowCounts.fromMap(Map<String, dynamic>? map) => FollowCounts(
    followers: ((map?['followers'] as num?)?.toInt() ?? 0).clamp(0, 1 << 31),
    following: ((map?['following'] as num?)?.toInt() ?? 0).clamp(0, 1 << 31),
  );
}
