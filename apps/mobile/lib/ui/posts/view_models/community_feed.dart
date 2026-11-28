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
  CommunityFeed({
    required UserPostRepository userPostRepository,
    this.refreshTimeout = const Duration(seconds: 10),
  }) : _posts = userPostRepository;

  /// How long [refresh] waits for the new first page before it returns
  /// (the page still swaps in when it arrives).
  final Duration refreshTimeout;

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
  ///
  /// The posts on screen stay until the new first page and its posts have
  /// arrived, then swap in at once. Completes then, or after
  /// [refreshTimeout] (the swap still happens when the page arrives).
  Future<void> refresh() {
    if (!_started) return Future.value();
    return _refresh().timeout(refreshTimeout, onTimeout: () {});
  }

  StreamSubscription<List<UserPost>>? _staged;
  Completer<void>? _stagedFirst;

  Future<void> _refresh() async {
    final generation = ++_generation;
    _dropStaged();
    // A page being loaded for "older" is dropped by the generation check.
    _loading = false;
    if (!available) {
      _loaded = true;
      notifyListeners();
      return;
    }
    final result = await _posts.fetchCommunityPage();
    if (_disposed || generation != _generation) return;
    switch (result) {
      case Error():
        // Keep what's showing; the error note offers to try again.
        _error = true;
        notifyListeners();
      case Ok(:final value):
        final ids = value.ids;
        if (ids.isNotEmpty) {
          final first = _stagedFirst = Completer<void>();
          var got = false;
          void arrived() {
            if (!got) {
              got = true;
              if (!first.isCompleted) first.complete();
            }
          }

          _staged = _posts.watchPostsByIds(ids).listen((list) {
            for (final id in ids) {
              _byId.remove(id);
            }
            for (final p in list) {
              _byId[p.id] = p;
            }
            arrived();
            notifyListeners();
          }, onError: (Object _) => arrived());
          await first.future;
          if (_disposed || generation != _generation) return;
        }
        _cancel();
        if (_staged case final staged?) {
          _subs.add(staged);
          _staged = null;
          _stagedFirst = null;
        }
        final keep = ids.toSet();
        _byId.removeWhere((id, _) => !keep.contains(id));
        _ids
          ..clear()
          ..addAll(ids);
        _next = value.next;
        _lastBefore = null;
        _waiting = 0;
        _loaded = true;
        _error = false;
        notifyListeners();
    }
  }

  void _dropStaged() {
    final staged = _staged;
    _staged = null;
    if (staged != null) unawaited(staged.cancel());
    final first = _stagedFirst;
    _stagedFirst = null;
    if (first != null && !first.isCompleted) first.complete();
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
    _dropStaged();
    _cancel();
    super.dispose();
  }
}
