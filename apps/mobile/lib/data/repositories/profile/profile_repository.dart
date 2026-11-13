import '../../../domain/models/app_user.dart';
import '../../../domain/models/chat.dart';
import '../../../domain/models/player_profile.dart';
import '../../../utils/result.dart';

/// The two pictures on a profile: the round profile picture and the wide
/// header photo above it.
enum ProfileImage {
  photo('profile picture'),
  header('header photo');

  const ProfileImage(this.label);

  final String label;
}

/// Players' profiles (`profiles/{uid}`), readable by anyone signed in.
/// Each player writes only their own. A private profile's details live in
/// `profiles/{uid}/private/details`, for the player and the people whose
/// follow they accepted.
abstract class ProfileRepository {
  /// Null when the player has no profile (e.g. no display name yet). A
  /// private profile this viewer may not see comes back
  /// [PlayerProfile.locked], with only the name, username and photo.
  Stream<PlayerProfile?> watchProfile(String uid);

  /// Makes [user]'s profile private (moving the details to the private
  /// doc) or public again (moving them back).
  Future<Result<void>> setPrivate(AppUser user, bool private);

  /// Which sections others see. Hidden ones are taken off the published
  /// profile at once; shown ones come back the next time the player's app
  /// publishes their summary.
  Future<Result<void>> saveVisibility(AppUser user, ProfileVisibility v);

  /// Saves what [user] wrote about themselves. [tags] index the profile
  /// for search by school, hometown and team.
  Future<Result<void>> saveDetails(
    AppUser user,
    ProfileDetails details, {
    required List<String> tags,
  });

  /// Publishes [summary] (teams, season stats, recent games) for [user].
  /// Parts the player hides should already be empty.
  Future<Result<void>> publishSummary(
    AppUser user,
    ProfileSummary summary, {
    required List<String> tags,
  });

  /// Uploads [image] as [user]'s [kind] and returns its URL. Nothing shows
  /// it until it's set: the profile picture with
  /// AuthRepository.updatePhotoUrl, the header with [setHeader].
  Future<Result<String>> uploadImage(
    AppUser user,
    ProfileImage kind,
    NewAttachment image,
  );

  /// Sets [user]'s header photo; null removes it. Shown even on a private
  /// profile, like the name and profile picture.
  Future<Result<void>> setHeader(AppUser user, String? url);

  /// Deletes an uploaded image that's no longer shown. Best effort: URLs
  /// it didn't upload are left alone.
  Future<void> deleteImage(String url);

  /// Players whose name, school, hometown or team matches every word of
  /// [query].
  Future<Result<List<PlayerProfile>>> searchPlayers(String query);
}
