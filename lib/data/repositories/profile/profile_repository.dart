import '../../../domain/models/direct_message.dart';

/// The public people directory, `profiles/{uid}`: name and photo.
abstract class ProfileRepository {
  /// Null when the user has no public profile (no display name yet, or a
  /// deleted account).
  Stream<UserProfile?> watchProfile(String uid);
}
