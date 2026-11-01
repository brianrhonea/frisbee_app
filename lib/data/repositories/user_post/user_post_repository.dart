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

  /// Null once deleted.
  Stream<UserPost?> watchPost(String id);

  /// Creates the post when [UserPost.isNew], otherwise updates it. Uploads
  /// [UserPostDraft.newImages] and deletes photos dropped from it. Returns
  /// the post id.
  Future<Result<String>> savePost(UserPostDraft draft, AppUser author);

  /// Deletes the post and its photos. Authors only.
  Future<Result<void>> deletePost(String id);

  Future<Result<Uint8List>> downloadImage(ChatAttachment image);
}
