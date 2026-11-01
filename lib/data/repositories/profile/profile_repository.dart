import '../../../domain/models/app_user.dart';
import '../../../domain/models/player_profile.dart';
import '../../../utils/result.dart';

/// Players' public profiles (`profiles/{uid}`), readable by anyone signed
/// in. Each player writes only their own.
abstract class ProfileRepository {
  /// Null when the player has no profile (e.g. no display name yet).
  Stream<PlayerProfile?> watchProfile(String uid);

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
