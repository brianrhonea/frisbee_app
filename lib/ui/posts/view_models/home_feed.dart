import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/follow/follow_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../data/repositories/team_post/team_post_repository.dart';
import '../../../data/repositories/user_post/user_post_repository.dart';
import '../../../domain/models/feed_item.dart';
import '../../../domain/models/follow.dart';
import '../../../domain/models/team.dart';
import '../../../domain/models/team_post.dart';
import '../../../utils/result.dart';

/// The home feed: the user's own posts and those of people they follow,
/// every post of their teams and groups, public posts of teams they
/// follow, and posts about tournaments they follow, newest first.
///
/// Watches what the user follows and which teams they're on, and keeps one
/// source per query, adding and dropping them as those change. Each source
/// keeps its newest page live; "Show older posts" fetches the next page
/// once (a cursor read) instead of re-reading every source with a bigger
/// limit.
class HomeFeed extends ChangeNotifier {
  HomeFeed({
    required this.uid,
    required FollowRepository followRepository,
    required TeamRepository teamRepository,
    required TeamPostRepository teamPostRepository,
    required UserPostRepository userPostRepository,
  }) : _teamPosts = teamPostRepository,
       _userPosts = userPostRepository {
    if (uid.isEmpty) {
      _followsLoaded = _teamsLoaded = true;
      return;
    }
    _followsSub = followRepository
        .watchFollows(uid)
        .listen(
          (f) {
            _follows = f;
            _followsLoaded = true;
            _sync();
          },
          onError: (Object _) {
            _followsLoaded = true;
            _sync();
          },
        );
    _teamsSub = teamRepository
        .watchMyTeams(uid)
        .listen(
          (t) {
            _teams = t;
            _teamsLoaded = true;
            _sync();
          },
          onError: (Object _) {
            _teamsLoaded = true;
            _sync();
          },
        );
  }

  static const pageSize = 20;

  /// Page fetches per [loadMore] at most, so one tap can't run away.
  static const _maxRounds = 5;

  final String uid;
  final TeamPostRepository _teamPosts;
  final UserPostRepository _userPosts;

  StreamSubscription<List<Follow>>? _followsSub;
  StreamSubscription<List<Team>>? _teamsSub;
  List<Follow> _follows = const [];
  List<Team> _teams = const [];
  bool _followsLoaded = false;
  bool _teamsLoaded = false;
  bool _loadingMore = false;
  bool _disposed = false;

  /// Source key → its live first page and the older pages fetched.
  final _sources = <String, _FeedSource>{};

  bool get loaded => _followsLoaded && _teamsLoaded;

  /// What the user follows, newest first.
  List<Follow> get follows => _follows;

  /// Teams and groups the user is on.
  List<Team> get teams => _teams;

  /// Each source has loaded down to some date; below the newest of those
  /// dates a source might be missing posts, so the feed stops there.
  DateTime? get _cutoff {
    DateTime? cutoff;
    for (final s in _sources.values) {
      if (s.exhausted) continue;
      final oldest = s.oldest;
      if (oldest != null && (cutoff == null || oldest.isAfter(cutoff))) {
        cutoff = oldest;
      }
    }
    return cutoff;
  }

  List<FeedItem> get items {
    final cutoff = _cutoff;
    return [
      for (final item in mergeFeed([for (final s in _sources.values) s.items]))
        if (cutoff == null ||
            item.createdAt == null ||
            !item.createdAt!.isBefore(cutoff))
          item,
    ];
  }

  /// Whether [loadMore] could show more.
  bool get hasMore => _sources.values.any((s) => !s.exhausted);

  bool get loadingMore => _loadingMore;

  /// Shows older posts: fetches the next page from the sources holding the
  /// feed back, until about a page more is shown.
  Future<void> loadMore() async {
    if (_loadingMore || !hasMore) return;
    _loadingMore = true;
    notifyListeners();
    final target = items.length + pageSize;
    for (var round = 0; round < _maxRounds; round++) {
      final cutoff = _cutoff;
      if (cutoff == null) break;
      final binding = [
        for (final s in _sources.values)
          if (!s.exhausted && s.oldest == cutoff) s,
      ];
      await Future.wait([for (final s in binding) s.fetchMore(pageSize)]);
      if (_disposed) return;
      if (items.length >= target || !hasMore) break;
    }
    _loadingMore = false;
    notifyListeners();
  }

  _FeedSource _source(
    Stream<List<FeedItem>> live,
    Future<List<FeedItem>?> Function(DateTime before, int limit)? older,
  ) => _FeedSource(
    live: live,
    fetch: older,
    onChange: () {
      if (!_disposed) notifyListeners();
    },
  );

  Future<List<FeedItem>?> Function(DateTime, int) _userPages(
    UserPostFilter filter,
    List<String> values, {
    bool skipReposts = false,
  }) =>
      (before, limit) async => switch (await _userPosts.fetchPostsBefore(
        filter,
        values,
        before: before,
        limit: limit,
      )) {
        Ok(:final value) => [
          for (final post in value)
            if (!skipReposts || !post.isRepost) UserPostItem(post),
        ],
        Error() => null,
      };

  Future<List<FeedItem>?> Function(DateTime, int) _teamPages(
    String teamId,
    String name, {
    bool publicOnly = false,
  }) =>
      (before, limit) async => switch (await _teamPosts.fetchPostsBefore(
        teamId,
        publicOnly: publicOnly,
        before: before,
        limit: limit,
      )) {
        Ok(:final value) => [
          for (final post in value)
            TeamPostItem(teamId: teamId, teamName: name, post: post),
        ],
        Error() => null,
      };

  void _sync() {
    final myTeams = {for (final t in _teams) t.id: t};
    final wanted = <String, _FeedSource Function()>{};

    final authors = [
      uid,
      for (final f in _follows)
        if (f.type == FollowType.user) f.target.id,
    ]..sort();
    wanted['authors:${authors.join(',')}'] = () => _source(
      _userPosts
          .watchPostsByAuthors(authors, limit: pageSize)
          .map((p) => [for (final post in p) UserPostItem(post)]),
      _userPages(UserPostFilter.authors, authors),
    );

    final tags = [
      for (final f in _follows)
        if (f.type == FollowType.tournament) f.key,
    ]..sort();
    if (tags.isNotEmpty) {
      wanted['tags:${tags.join(',')}'] = () => _source(
        _userPosts
            .watchPostsForTournaments(tags, limit: pageSize)
            .map((p) => [for (final post in p) UserPostItem(post)]),
        _userPages(UserPostFilter.tournaments, tags),
      );
    }

    // Events shared from the schedules of the user's teams, by anyone
    // (not only people they follow). Reposts reach the reposter's
    // followers, not the whole team again.
    final teamIds = [for (final t in _teams) t.id]..sort();
    if (teamIds.isNotEmpty) {
      wanted['teamEvents:${teamIds.join(',')}'] = () => _source(
        _userPosts
            .watchPostsForTeamEvents(teamIds, limit: pageSize)
            .map(
              (p) => [
                for (final post in p)
                  if (!post.isRepost) UserPostItem(post),
              ],
            ),
        _userPages(UserPostFilter.teamEvents, teamIds, skipReposts: true),
      );
    }

    for (final t in _teams) {
      wanted['team:${t.id}'] = () => _source(
        _teamItems(t.id, t.name, _teamPosts.watchPosts(t.id, limit: pageSize)),
        _teamPages(t.id, t.name),
      );
    }
    for (final f in _follows) {
      final target = f.target;
      if (f.type == FollowType.team && !myTeams.containsKey(target.id)) {
        wanted['public:${target.id}'] = () => _source(
          _teamItems(
            target.id,
            target.name,
            _teamPosts.watchPosts(target.id, publicOnly: true, limit: pageSize),
          ),
          _teamPages(target.id, target.name, publicOnly: true),
        );
      }
      final group = target.groupId;
      if (f.type == FollowType.tournament &&
          group != null &&
          !myTeams.containsKey(group)) {
        // Few posts per tournament: the whole set is live.
        wanted['tournament:${f.key}'] = () => _source(
          _teamItems(
            group,
            target.name,
            _teamPosts.watchTournamentPosts(group, f.key),
          ),
          null,
        );
      }
    }

    for (final key in _sources.keys.toList()) {
      if (!wanted.containsKey(key)) _sources.remove(key)?.dispose();
    }
    for (final MapEntry(:key, value: open) in wanted.entries) {
      _sources[key] ??= open();
    }
    notifyListeners();
  }

  Stream<List<FeedItem>> _teamItems(
    String teamId,
    String teamName,
    Stream<List<TeamPost>> posts,
  ) => posts.map(
    (p) => [
      for (final post in p)
        TeamPostItem(teamId: teamId, teamName: teamName, post: post),
    ],
  );

  @override
  void dispose() {
    _disposed = true;
    _followsSub?.cancel();
    _teamsSub?.cancel();
    for (final s in _sources.values) {
      s.dispose();
    }
    super.dispose();
  }
}

/// One feed source: its newest [HomeFeed.pageSize] posts live, plus older
/// pages fetched on demand and posts newer ones pushed out of the live
/// page.
class _FeedSource {
  _FeedSource({
    required Stream<List<FeedItem>> live,
    required this.fetch,
    required this.onChange,
  }) {
    _sub = live.listen(
      _onLive,
      onError: (Object _) {
        _live = const [];
        _liveLoaded = true;
        onChange();
      },
    );
  }

  /// Null when the live stream already holds every post.
  final Future<List<FeedItem>?> Function(DateTime before, int limit)? fetch;
  final VoidCallback onChange;
  late final StreamSubscription<List<FeedItem>> _sub;
  List<FeedItem> _live = const [];
  bool _liveLoaded = false;
  final _older = <String, FeedItem>{};
  bool _fetchedAll = false;

  List<FeedItem> get items => [..._older.values, ..._live];

  /// Nothing more on the server than what's loaded (or not loaded yet, so
  /// it can't hold the feed back).
  bool get exhausted =>
      !_liveLoaded ||
      fetch == null ||
      _fetchedAll ||
      (_older.isEmpty && _live.length < HomeFeed.pageSize);

  /// The oldest post loaded.
  DateTime? get oldest => _oldestOf(items);

  static DateTime? _oldestOf(Iterable<FeedItem> items) {
    DateTime? oldest;
    for (final item in items) {
      final at = item.createdAt;
      if (at != null && (oldest == null || at.isBefore(oldest))) oldest = at;
    }
    return oldest;
  }

  void _onLive(List<FeedItem> next) {
    // A new post pushes the oldest out of a full live page: keep it. A
    // deleted one isn't older than the whole new page.
    if (_liveLoaded && next.length >= HomeFeed.pageSize) {
      final ids = {for (final i in next) i.id};
      final newOldest = _oldestOf(next);
      for (final i in _live) {
        final at = i.createdAt;
        if (!ids.contains(i.id) &&
            at != null &&
            newOldest != null &&
            at.isBefore(newOldest)) {
          _older[i.id] = i;
        }
      }
    }
    for (final i in next) {
      _older.remove(i.id);
    }
    _live = next;
    _liveLoaded = true;
    onChange();
  }

  Future<void> fetchMore(int limit) async {
    final fetch = this.fetch;
    final before = oldest;
    if (fetch == null || before == null) {
      _fetchedAll = true;
      return;
    }
    final page = await fetch(before, limit);
    // A failed fetch stops paging this source rather than retrying.
    if (page == null || page.length < limit) _fetchedAll = true;
    for (final i in page ?? const <FeedItem>[]) {
      _older[i.id] = i;
    }
    onChange();
  }

  void dispose() => _sub.cancel();
}
