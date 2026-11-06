import '../../../domain/models/direct_message.dart';

/// Looks up people's public directory listings (name, photo, username)
/// by uid, for labelling messages and comments.
abstract class PeopleRepository {
  /// [uid]'s listing, or null if they have none. Fetched once per uid
  /// and then served from memory.
  Future<UserProfile?> person(String uid);

  /// The listing for [uid] if it's already been fetched.
  UserProfile? cached(String uid);
}
