import 'package:flutter/foundation.dart';

import '../../../data/repositories/browse/browse_repository.dart';
import '../../../domain/models/player_profile.dart';
import '../../../domain/models/user_post.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';
import 'post_images.dart';

/// A player's profile for signed-out visitors: what they've made public,
/// and their newest posts.
class PublicProfileViewModel extends ChangeNotifier with PostImages {
  PublicProfileViewModel({
    required this.uid,
    required BrowseRepository browseRepository,
  }) : browse = browseRepository {
    load = Command0<void>(_load)..execute();
    loadMore = Command0<void>(_loadMore);
  }

  final String uid;

  @override
  final BrowseRepository browse;

  late final Command0<void> load;
  late final Command0<void> loadMore;

  PlayerProfile? _profile;

  /// Null until loaded.
  PlayerProfile? get profile => _profile;

  List<UserPost> _posts = const [];
  List<UserPost> get posts => _posts;

  DateTime? _next;
  bool get hasMore => _next != null;

  Future<Result<void>> _load() async {
    switch (await browse.profile(uid)) {
      case Ok(:final value):
        _profile = value.profile;
        _posts = value.posts.posts;
        _next = value.posts.next;
        notifyListeners();
        return const Result.ok(null);
      case Error(:final error):
        return Result.error(error);
    }
  }

  Future<Result<void>> _loadMore() async {
    final before = _next;
    if (before == null) return const Result.ok(null);
    switch (await browse.profile(uid, before: before)) {
      case Ok(:final value):
        _posts = [..._posts, ...value.posts.posts];
        _next = value.posts.next;
        notifyListeners();
        return const Result.ok(null);
      case Error(:final error):
        return Result.error(error);
    }
  }

  @override
  void dispose() {
    load.dispose();
    loadMore.dispose();
    super.dispose();
  }
}
