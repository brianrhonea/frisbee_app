import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/browse/browse_repository.dart';
import '../../../domain/models/user_post.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';
import 'post_images.dart';

/// The community feed: the newest public posts on Stall 10, for everyone,
/// signed in or not.
class CommunityFeedViewModel extends ChangeNotifier with PostImages {
  CommunityFeedViewModel({
    required BrowseRepository browseRepository,
    required AuthRepository authRepository,
  }) : browse = browseRepository,
       _auth = authRepository {
    load = Command0<void>(_load)..execute();
    loadMore = Command0<void>(_loadMore);
  }

  @override
  final BrowseRepository browse;
  final AuthRepository _auth;

  /// Members open a post to like or comment on it; visitors are asked to
  /// join first.
  bool get signedIn => _auth.isAuthenticated;

  /// Loads the first page again.
  late final Command0<void> load;

  /// Loads the page after [posts].
  late final Command0<void> loadMore;

  List<UserPost> _posts = const [];
  List<UserPost> get posts => _posts;

  DateTime? _next;
  bool get hasMore => _next != null;

  Future<Result<void>> _load() async {
    switch (await browse.feed()) {
      case Ok(:final value):
        _posts = value.posts;
        _next = value.next;
        notifyListeners();
        return const Result.ok(null);
      case Error(:final error):
        return Result.error(error);
    }
  }

  Future<Result<void>> _loadMore() async {
    final before = _next;
    if (before == null) return const Result.ok(null);
    switch (await browse.feed(before: before)) {
      case Ok(:final value):
        _posts = [..._posts, ...value.posts];
        _next = value.next;
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
