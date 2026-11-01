import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../domain/models/app_user.dart';
import '../../../domain/models/chat.dart';
import '../../../domain/models/team_post.dart';
import '../../../utils/result.dart';
import '../../services/attachment_storage.dart';
import '../../services/firestore_utils.dart';
import 'team_post_repository.dart';

/// Posts live in `teams/{teamId}/posts`; their photos in Cloud Storage
/// under `teams/{teamId}/posts/{postId}/`. firestore.rules and
/// storage.rules let anyone signed in read public posts and members the
/// rest.
class TeamPostRepositoryFirebase implements TeamPostRepository {
  TeamPostRepositoryFirebase({
    required AttachmentStorage attachments,
    FirebaseFirestore? firestore,
  }) : _files = attachments,
       _db = firestore ?? FirebaseFirestore.instance;

  final AttachmentStorage _files;
  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _posts(String teamId) =>
      _db.collection('teams').doc(teamId).collection('posts');

  /// Each save's uploads get their own folder, so a new photo never
  /// overwrites a kept one with the same name.
  static String imageFolder(String teamId, String postId) =>
      'teams/$teamId/posts/$postId/${DateTime.now().millisecondsSinceEpoch}';

  @override
  Stream<List<TeamPost>> watchPosts(String teamId, {bool publicOnly = false}) {
    // Non-members must filter on `public` for the rules to allow the query.
    // Sorted here so the filter needs no composite index.
    final Query<Map<String, dynamic>> q = publicOnly
        ? _posts(teamId).where('public', isEqualTo: true)
        : _posts(teamId);
    return q.snapshots().map(
      (snap) => [
        for (final d in snap.docs) TeamPost.fromMap(d.id, plainData(d.data())),
      ]..sort(TeamPost.newestFirst),
    );
  }

  @override
  Stream<List<TeamPost>> watchTournamentPosts(
    String groupId,
    String tournamentKey,
  ) => _posts(groupId)
      .where('public', isEqualTo: true)
      .where('tournamentKey', isEqualTo: tournamentKey)
      .snapshots()
      .map(
        (snap) => [
          for (final d in snap.docs)
            TeamPost.fromMap(d.id, plainData(d.data())),
        ]..sort(TeamPost.newestFirst),
      );

  @override
  Future<Result<void>> savePost(
    String teamId,
    PostDraft draft,
    AppUser author,
  ) => guard(() async {
    final post = draft.post;
    final ref = post.isNew ? _posts(teamId).doc() : _posts(teamId).doc(post.id);
    final before = post.isNew
        ? const <ChatAttachment>[]
        : TeamPost.fromMap(ref.id, plainData((await ref.get()).data())).images;
    final uploaded = draft.newImages.isEmpty
        ? const <ChatAttachment>[]
        : await _files.upload(imageFolder(teamId, ref.id), draft.newImages);
    final saved = post.copyWith(images: [...post.images, ...uploaded]);
    try {
      if (post.isNew) {
        await ref.set({
          ...saved.toEditableMap(),
          'authorId': author.uid,
          'authorName': author.label,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        await ref.update({
          ...saved.toEditableMap(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (_) {
      await _files
          .delete(uploaded.map((i) => i.path))
          .catchError((Object _) => <void>[]);
      rethrow;
    }
    final kept = {for (final i in saved.images) i.path};
    final removed = [
      for (final i in before)
        if (!kept.contains(i.path)) i.path,
    ];
    if (removed.isNotEmpty) await _files.delete(removed);
  });

  @override
  Future<Result<void>> deletePost(String teamId, String postId) =>
      guard(() async {
        final ref = _posts(teamId).doc(postId);
        final images = TeamPost.fromMap(
          postId,
          plainData((await ref.get()).data()),
        ).images;
        await ref.delete();
        await _files.delete(images.map((i) => i.path));
      });

  @override
  Future<Result<Uint8List>> downloadImage(ChatAttachment image) =>
      guard(() => _files.download(image));
}
