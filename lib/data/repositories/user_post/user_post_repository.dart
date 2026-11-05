import 'dart:typed_data';

import '../../../domain/models/app_user.dart';
import '../../../domain/models/chat.dart';
import '../../../domain/models/user_post.dart';
import '../../../utils/result.dart';

/// Posts people write themselves, at `posts/{id}`; photos in Cloud Storage
/// under `users/{uid}/posts/{postId}/`. Anyone signed in can read them.
abstract class UserPostRepository {
  /// [authorId]'s posts, newest first.
  Stream<List<UserPost>> watchPostsBy(String authorId, {int limit = 50});

  /// The newest posts by any of [authorIds], newest first.
  Stream<List<UserPost>> watchPostsByAuthors(
    List<String> authorIds, {
    int limit = 50,
  });

  /// The newest posts tagged with any of [tournamentKeys].
  Stream<List<UserPost>> watchPostsForTournaments(
    List<String> tournamentKeys, {
    int limit = 50,
  });

  /// The newest posts sharing an event on any of [teamIds]' schedules, so
  /// the team's members see them as well as the author's followers.
  Stream<List<UserPost>> watchPostsForTeamEvents(
    List<String> teamIds, {
    int limit = 50,
  });

  /// One page of older posts for the home feed: up to [limit] posts made
  /// before [before] matching [filter] on any of [values], newest first.
  Future<Result<List<UserPost>>> fetchPostsBefore(
    UserPostFilter filter,
    List<String> values, {
    required DateTime before,
    int limit = 20,
  });

  /// Null once deleted.
  Stream<UserPost?> watchPost(String id);

  /// Creates the post when [UserPost.isNew], otherwise updates it. Uploads
  /// [UserPostDraft.newImages] and deletes photos dropped from it. Returns
  /// the post id.
  Future<Result<String>> savePost(UserPostDraft draft, AppUser author);

  /// Likes or unlikes post [postId] as [uid].
  Future<Result<void>> setLiked(String postId, String uid, bool liked);

  /// Reposts [original] (or what it reposts) to [me]'s followers, with
  /// [note]. Each person reposts a post at most once; returns the repost's
  /// id ([UserPost.repostId]).
  Future<Result<String>> repost(UserPost original, String note, AppUser me);

  /// Takes back [uid]'s repost of post [originalId].
  Future<Result<void>> undoRepost(String originalId, String uid);

  /// Deletes the post and its photos. Authors only.
  Future<Result<void>> deletePost(String id);

  Future<Result<Uint8List>> downloadImage(ChatAttachment image);
}

/// Which posts [UserPostRepository.fetchPostsBefore] pages through; the
/// same sets as watchPostsByAuthors, watchPostsForTournaments and
/// watchPostsForTeamEvents.
enum UserPostFilter { authors, tournaments, teamEvents }
