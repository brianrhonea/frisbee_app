import 'team_post.dart';
import 'user_post.dart';

/// One entry in the home feed: a person's post or a team/group post.
sealed class FeedItem {
  const FeedItem();

  /// Unique across both kinds.
  String get id;
  DateTime? get createdAt;

  /// Newest first; pending server timestamps count as now.
  static int newestFirst(FeedItem a, FeedItem b) =>
      (b.createdAt ?? DateTime(9999)).compareTo(a.createdAt ?? DateTime(9999));
}

class UserPostItem extends FeedItem {
  const UserPostItem(this.post);

  final UserPost post;

  @override
  String get id => 'user/${post.id}';

  @override
  DateTime? get createdAt => post.createdAt;
}

class TeamPostItem extends FeedItem {
  const TeamPostItem({
    required this.teamId,
    required this.teamName,
    required this.post,
  });

  final String teamId;
  final String teamName;
  final TeamPost post;

  @override
  String get id => 'team/$teamId/${post.id}';

  @override
  DateTime? get createdAt => post.createdAt;
}

/// Combines the feed's sources into one newest-first list of at most
/// [limit] items. The same post can come from several sources (a followed
/// author who tagged a followed tournament), so items are deduped by id.
List<FeedItem> mergeFeed(Iterable<Iterable<FeedItem>> sources, {int? limit}) {
  final byId = <String, FeedItem>{
    for (final source in sources)
      for (final item in source) item.id: item,
  };
  final items = byId.values.toList()..sort(FeedItem.newestFirst);
  return limit == null || items.length <= limit
      ? items
      : items.sublist(0, limit);
}
