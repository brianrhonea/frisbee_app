import 'dart:typed_data';

import '../../../domain/models/app_user.dart';
import '../../../domain/models/chat.dart';
import '../../../domain/models/team_post.dart';
import '../../../utils/result.dart';

abstract class TeamPostRepository {
  /// The team's posts, newest first. Members see every post; pass
  /// [publicOnly] for everyone else, who may read only public ones.
  Stream<List<TeamPost>> watchPosts(String teamId, {bool publicOnly = false});

  /// Creates the post when [TeamPost.isNew], otherwise updates its editable
  /// fields. Uploads [PostDraft.newImages] and deletes photos dropped from
  /// the saved post. Owners, coaches and captains only.
  Future<Result<void>> savePost(String teamId, PostDraft draft, AppUser author);

  /// Deletes the post and its photos.
  Future<Result<void>> deletePost(String teamId, String postId);

  /// A post photo's bytes.
  Future<Result<Uint8List>> downloadImage(ChatAttachment image);
}
