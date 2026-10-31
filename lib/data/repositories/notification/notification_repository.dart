import '../../../domain/models/notification.dart';
import '../../../utils/result.dart';

/// Notification preferences, the in-app feed, and push on this device.
///
/// Cloud Functions decide who gets what and write the feed; the app only
/// stores preferences, registers devices and marks entries read.
abstract class NotificationRepository {
  Stream<NotificationPreferences> watchPreferences(String uid);

  /// Turns [category] on or off for every team.
  Future<Result<void>> setCategory(
    String uid,
    NotificationCategory category, {
    required bool on,
  });

  /// Overrides [category] for one team.
  Future<Result<void>> setTeamCategory(
    String uid,
    String teamId,
    NotificationCategory category, {
    required bool on,
  });

  /// Drops [teamId]'s overrides so it follows the defaults again.
  Future<Result<void>> resetTeam(String uid, String teamId);

  Future<Result<void>> setRoomMuted(
    String uid,
    String teamId,
    String roomId, {
    required bool muted,
  });

  /// The newest notifications, newest first.
  Stream<List<AppNotification>> watchFeed(String uid);

  Future<Result<void>> markRead(String uid, Iterable<String> ids);

  Future<Result<void>> delete(String uid, Iterable<String> ids);

  bool get pushSupported;

  Future<PushStatus> pushStatus();

  /// Asks for permission if needed and registers this device for [uid].
  Future<Result<PushStatus>> enablePush(String uid);

  /// Called at sign-in: registers this device if push is already allowed,
  /// keeps its token fresh, and records the time zone reminders use.
  Future<void> syncDevice(String uid);

  /// Called before sign-out so the next user doesn't get [uid]'s pushes.
  Future<void> unregisterDevice(String uid);

  /// Routes of tapped push notifications.
  Stream<String> get openedRoutes;
}
