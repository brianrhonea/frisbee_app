import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/user_post/user_post_repository.dart';
import '../../../domain/models/user_post.dart';
import '../../../utils/result.dart';

/// The community feed (Home's Community tab, as on the website): the
/// newest posts by public profiles, a page at a time.
///
/// The API picks each page's posts (`GET /v1/feed`, which leaves out
/// private profiles); each page is then watched in Firestore, so likes,
/// reposts, edits and deletions show as they happen. Nothing loads until
/// [start], the first time the tab is opened.
class CommunityFeed extends ChangeNotifier {
  CommunityFeed({required UserPostRepository userPostRepository})
    : _posts = userPostRepository;

  final UserPostRepository _posts;

  /// Ids in feed order, across every page loaded.
  final _ids = <String>[];
  final _byId = <String, UserPost>{};
  final _subs = <StreamSubscription<List<UserPost>>>[];
  int? _next;

  /// The cursor of the page last asked for, to retry it after an error.
  int? _lastBefore;

  /// Pages whose posts haven't arrived from Firestore yet.
  int _waiting = 0;
  bool _started = false;
  bool _loaded = false;
  bool _loading = false;
  bool _error = false;
  bool _disposed = false;

  /// Bumped by [refresh], so a page from before it is dropped.
  int _generation = 0;

  /// Whether this build has a community feed at all.
  bool get available => _posts.hasCommunityFeed;

  /// Something to show: the first page has loaded, posts and all (or
  /// failed). Stays true while older pages load under it.
  bool get loaded => _loaded && !(_waiting > 0 && posts.isEmpty);

  /// A page is loading, from the API or its posts from Firestore.
  bool get loading => _loading || _waiting > 0;

  /// The last page failed to load; [loadMore] (or [refresh]) tries again.
  bool get error => _error;

  /// More pages after these, even if this one came up short.
  bool get hasMore => _next != null;

  /// The posts loaded so far, newest first.
  List<UserPost> get posts => [for (final id in _ids) ?_byId[id]];

  /// Loads the first page, once.
  void start() {
    if (_started) return;
    _started = true;
    unawaited(_load());
  }

  /// The next page, or the first again after an error.
  Future<void> loadMore() async {
    if (_loading) return;
    if (_error) return _load(before: _lastBefore);
    if (_next case final next?) return _load(before: next);
  }

  /// Back to the newest posts, if the tab has been opened.
  Future<void> refresh() async {
    if (!_started) return;
    _generation++;
    _cancel();
    _ids.clear();
    _byId.clear();
    _next = null;
    _lastBefore = null;
    _waiting = 0;
    _loaded = false;
    _loading = false;
    _error = false;
    notifyListeners();
    await _load();
  }

  Future<void> _load({int? before}) async {
    if (!available) {
      _loaded = true;
      notifyListeners();
      return;
    }
    final generation = _generation;
    _lastBefore = before;
    _loading = true;
    _error = false;
    notifyListeners();
    final result = await _posts.fetchCommunityPage(before: before);
    if (_disposed || generation != _generation) return;
    _loading = false;
    switch (result) {
      case Ok(:final value):
        final fresh = [
          for (final id in value.ids)
            if (!_ids.contains(id)) id,
        ];
        _ids.addAll(fresh);
        _next = value.next;
        if (fresh.isNotEmpty) _watch(fresh);
      case Error():
        _error = true;
    }
    _loaded = true;
    notifyListeners();
  }

  /// Keeps one page's posts up to date; a post missing from its snapshot
  /// was deleted.
  void _watch(List<String> ids) {
    var first = true;
    _waiting++;
    _subs.add(
      _posts
          .watchPostsByIds(ids)
          .listen(
            (list) {
              if (first) {
                first = false;
                _waiting--;
              }
              for (final id in ids) {
                _byId.remove(id);
              }
              for (final p in list) {
                _byId[p.id] = p;
              }
              notifyListeners();
            },
            // Keeps what it had; the next refresh watches again.
            onError: (Object _) {
              if (first) {
                first = false;
                _waiting--;
                notifyListeners();
              }
            },
          ),
    );
  }

  void _cancel() {
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _subs.clear();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancel();
    super.dispose();
  }
}
