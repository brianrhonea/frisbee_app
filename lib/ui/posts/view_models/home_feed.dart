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

/// The home feed: the user's own posts and those of people they follow,
/// every post of their teams and groups, public posts of teams they
/// follow, and posts about tournaments they follow, newest first.
///
/// Watches what the user follows and which teams they're on, and keeps one
/// subscription per source, adding and dropping them as those change.
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

  final String uid;
  final TeamPostRepository _teamPosts;
  final UserPostRepository _userPosts;

  StreamSubscription<List<Follow>>? _followsSub;
  StreamSubscription<List<Team>>? _teamsSub;
  List<Follow> _follows = const [];
  List<Team> _teams = const [];
  bool _followsLoaded = false;
  bool _teamsLoaded = false;

  /// Source key → its subscription and latest items.
  final _sources = <String, StreamSubscription<Object?>>{};
  final _items = <String, List<FeedItem>>{};

  int _limit = pageSize;

  bool get loaded => _followsLoaded && _teamsLoaded;

  /// What the user follows, newest first.
  List<Follow> get follows => _follows;

  /// Teams and groups the user is on.
  List<Team> get teams => _teams;

  List<FeedItem> get items => mergeFeed(_items.values, limit: _limit);

  /// Whether [loadMore] could show more.
  bool get hasMore =>
      _items.values.fold<int>(0, (n, l) => n + l.length) > _limit;

  /// Shows another page of older posts.
  void loadMore() {
    _limit += pageSize;
    // Person and tournament queries are capped at the limit; ask again.
    for (final key in _sources.keys.where(_limited).toList()) {
      _drop(key);
    }
    _sync();
  }

  static bool _limited(String sourceKey) =>
      sourceKey.startsWith('authors:') || sourceKey.startsWith('tags:');

  void _sync() {
    final myTeams = {for (final t in _teams) t.id: t};
    final wanted = <String, Stream<List<FeedItem>> Function()>{};

    final authors = [
      uid,
      for (final f in _follows)
        if (f.type == FollowType.user) f.target.id,
    ]..sort();
    wanted['authors:${authors.join(',')}:$_limit'] = () => _userPosts
        .watchPostsByAuthors(authors, limit: _limit)
        .map((p) => [for (final post in p) UserPostItem(post)]);

    final tags = [
      for (final f in _follows)
        if (f.type == FollowType.tournament || f.type == FollowType.event)
          f.key,
    ]..sort();
    if (tags.isNotEmpty) {
      wanted['tags:${tags.join(',')}:$_limit'] = () => _userPosts
          .watchPostsForTournaments(tags, limit: _limit)
          .map((p) => [for (final post in p) UserPostItem(post)]);
    }

    for (final t in _teams) {
      wanted['team:${t.id}'] = () =>
          _teamItems(t.id, t.name, _teamPosts.watchPosts(t.id));
    }
    for (final f in _follows) {
      final target = f.target;
      if (f.type == FollowType.team && !myTeams.containsKey(target.id)) {
        wanted['public:${target.id}'] = () => _teamItems(
          target.id,
          target.name,
          _teamPosts.watchPosts(target.id, publicOnly: true),
        );
      }
      final group = target.groupId;
      if (f.type == FollowType.tournament &&
          group != null &&
          !myTeams.containsKey(group)) {
        wanted['tournament:${f.key}'] = () => _teamItems(
          group,
          target.name,
          _teamPosts.watchTournamentPosts(group, f.key),
        );
      }
    }

    for (final key in _sources.keys.toList()) {
      if (!wanted.containsKey(key)) _drop(key);
    }
    for (final MapEntry(:key, value: open) in wanted.entries) {
      if (_sources.containsKey(key)) continue;
      _sources[key] = open().listen((items) {
        _items[key] = items;
        notifyListeners();
      }, onError: (Object _) {});
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

  void _drop(String key) {
    _sources.remove(key)?.cancel();
    _items.remove(key);
  }

  @override
  void dispose() {
    _followsSub?.cancel();
    _teamsSub?.cancel();
    for (final s in _sources.values) {
      s.cancel();
    }
    super.dispose();
  }
}
