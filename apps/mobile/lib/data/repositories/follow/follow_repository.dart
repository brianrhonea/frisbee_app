import '../../../domain/models/app_user.dart';
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

  // Private profiles ------------------------------------------------------

  /// Whether [uid] has asked to follow the private profile [owner].
  Stream<bool> watchFollowRequested(String uid, String owner);

  /// Asks to follow [owner]'s private profile.
  Future<Result<void>> requestFollow(AppUser me, String owner);

  Future<Result<void>> cancelFollowRequest(String uid, String owner);

  /// People asking to follow [owner], oldest first.
  Stream<List<FollowRequest>> watchFollowRequests(String owner);

  /// Lets [request]'s sender follow [owner]: creates their follow and
  /// removes the request, together.
  Future<Result<void>> acceptFollowRequest(
    AppUser owner,
    FollowRequest request,
  );

  Future<Result<void>> declineFollowRequest(String owner, String requester);
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
