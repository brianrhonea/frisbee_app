import '../../../domain/models/app_user.dart';
import '../../../domain/models/player_profile.dart';
import '../../../utils/result.dart';

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

  /// Players whose name, school, hometown or team matches every word of
  /// [query].
  Future<Result<List<PlayerProfile>>> searchPlayers(String query);
}
