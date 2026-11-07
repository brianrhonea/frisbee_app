import 'package:flutter/foundation.dart';

import '../../../domain/models/direct_message.dart';

/// Looks up people's public directory listings (name, photo, username)
/// by uid, for labelling messages, comments and posts with their current
/// photo rather than the one saved when they wrote it.
///
/// Notifies listeners when a listing arrives or changes, so avatars
/// showing it redraw.
abstract class PeopleRepository extends ChangeNotifier {
  /// [uid]'s listing, or null if they have none. Fetched once, then served
  /// from memory and refreshed now and then so changed photos show up.
  Future<UserProfile?> person(String uid);

  /// The listing for [uid] if it's already been fetched.
  UserProfile? cached(String uid);

  /// Puts [profile] straight into the cache, e.g. after the user changes
  /// their own photo.
  void remember(UserProfile profile);
}
