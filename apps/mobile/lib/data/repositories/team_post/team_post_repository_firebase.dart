import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../domain/models/app_user.dart';
import '../../../domain/models/chat.dart';
import '../../../domain/models/outbox.dart';
import '../../../domain/models/team_post.dart';
import '../../../utils/result.dart';
import '../../services/api_client.dart';
import '../../services/attachment_storage.dart';
import '../../services/firestore_utils.dart';
import '../../services/shared_streams.dart';
import '../outbox/outbox_repository.dart';
import 'team_post_repository.dart';

/// Posts live in `teams/{teamId}/posts`; their photos in Cloud Storage
/// under `teams/{teamId}/posts/{postId}/`. firestore.rules and
/// storage.rules let anyone signed in read public posts and members the
/// rest.
class TeamPostRepositoryFirebase implements TeamPostRepository {
  TeamPostRepositoryFirebase({
    required AttachmentStorage attachments,
    FirebaseFirestore? firestore,
    SharedStreams? sharedStreams,
    OutboxRepository? outbox,
    ApiClient? api,
  }) : _api = api,
       _files = attachments,
       _db = firestore ?? FirebaseFirestore.instance,
       _shared = sharedStreams ?? SharedStreams.instance,
       _outbox = outbox {
    outbox?.register(
      OutboxKind.teamPost,
      OutboxHandler(
        send: (job, files, author) => _save(
          job.target,
          PostDraft(
            post: TeamPost.fromMap(
              '',
              Map<String, dynamic>.from(
                job.payload['post'] as Map? ?? const {},
              ),
            ),
            newImages: files,
          ),
          author,
          newId: job.id,
        ),
        sent: (job) => existsOnServer(_posts(job.target).doc(job.id)),
      ),
    );
  }

  /// Holds new posts made offline until they can go out.
  final OutboxRepository? _outbox;

  /// Pins and comments go through the API (redesign F24).
  final ApiClient? _api;

  final AttachmentStorage _files;
  final FirebaseFirestore _db;

  /// One listener per query, shared by every screen (see [SharedStreams]).
  final SharedStreams _shared;

  CollectionReference<Map<String, dynamic>> _posts(String teamId) =>
      _db.collection('teams').doc(teamId).collection('posts');

  /// Each save's uploads get their own folder, so a new photo never
  /// overwrites a kept one with the same name.
  static String imageFolder(String teamId, String postId) =>
      'teams/$teamId/posts/$postId/${DateTime.now().millisecondsSinceEpoch}';

  @override
  Stream<List<TeamPost>> watchPosts(
    String teamId, {
    bool publicOnly = false,
    int? limit,
  }) => _shared.get('posts/$teamId/$publicOnly/${limit ?? 'all'}', () {
    // Non-members must filter on `public` for the rules to allow the query
    // (public + createdAt has a composite index).
    Query<Map<String, dynamic>> q = publicOnly
        ? _posts(teamId).where('public', isEqualTo: true)
        : _posts(teamId);
    if (limit != null) {
      q = q.orderBy('createdAt', descending: true).limit(limit);
    }
    return countedSnapshots(q, 'teamPosts').map(
      (snap) => [
        for (final d in snap.docs) TeamPost.fromMap(d.id, plainData(d.data())),
      ]..sort(TeamPost.newestFirst),
    );
  });

  @override
  Future<Result<List<TeamPost>>> fetchPostsBefore(
    String teamId, {
    bool publicOnly = false,
    required DateTime before,
    int limit = 20,
  }) => guard(() async {
    Query<Map<String, dynamic>> q = publicOnly
        ? _posts(teamId).where('public', isEqualTo: true)
        : _posts(teamId);
    final snap = await q
        .where('createdAt', isLessThan: Timestamp.fromDate(before))
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    if (!snap.metadata.isFromCache) {
      FirestoreReads.add('teamPosts', snap.docs.length);
    }
    return [
      for (final d in snap.docs) TeamPost.fromMap(d.id, plainData(d.data())),
    ]..sort(TeamPost.newestFirst);
  });

  @override
  Stream<List<TeamPost>> watchTournamentPosts(
    String groupId,
    String tournamentKey,
  ) => _shared.get(
    'tournamentPosts/$groupId/$tournamentKey',
    () =>
        countedSnapshots(
          _posts(groupId)
              .where('public', isEqualTo: true)
              .where('tournamentKey', isEqualTo: tournamentKey),
          'tournamentPosts',
        ).map(
          (snap) => [
            for (final d in snap.docs)
              TeamPost.fromMap(d.id, plainData(d.data())),
          ]..sort(TeamPost.newestFirst),
        ),
  );

  @override
  Future<Result<void>> savePost(
    String teamId,
    PostDraft draft,
    AppUser author,
  ) {
    final outbox = _outbox;
    // Only new posts wait offline; an edit needs the post as it stands.
    if (outbox == null ||
        !draft.post.isNew ||
        draft.newImages.any((i) => i.tooLarge)) {
      return _save(teamId, draft, author);
    }
    final id = _posts(teamId).doc().id;
    return outbox.submit(
      kind: OutboxKind.teamPost,
      id: id,
      target: teamId,
      label: 'Team post',
      payload: {'post': draft.post.toEditableMap()},
      files: draft.newImages,
      sendNow: () => _save(teamId, draft, author, newId: id),
    );
  }

  /// Saves [draft]; a new post gets [newId] (the queue's) or a fresh id.
  Future<Result<void>> _save(
    String teamId,
    PostDraft draft,
    AppUser author, {
    String? newId,
  }) => guard(() async {
    final post = draft.post;
    final ref = post.isNew
        ? _posts(teamId).doc(newId)
        : _posts(teamId).doc(post.id);
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

  // Pins and comments (redesign F24) ------------------------------------

  static const _noApi =
      'Pins and comments need a newer app version. Update the app to use them.';

  ApiClient get _client =>
      _api ?? (throw const ApiException('unavailable', _noApi));

  String _postPath(String teamId, String postId) =>
      '/v1/teams/${Uri.encodeComponent(teamId)}/posts/'
      '${Uri.encodeComponent(postId)}';

  @override
  bool get canUseFeedExtras => _api != null;

  @override
  Stream<List<TeamPost>> watchPinnedPosts(
    String teamId, {
    bool publicOnly = false,
  }) => _shared.get('pinnedPosts/$teamId/$publicOnly', () {
    // Firestore leaves out posts without pinnedAt. Non-members filter on
    // `public` (public + pinnedAt has a composite index).
    final q = publicOnly
        ? _posts(teamId).where('public', isEqualTo: true)
        : _posts(teamId);
    return countedSnapshots(
      q.orderBy('pinnedAt', descending: true).limit(TeamPost.pinsMax),
      'teamPosts',
    ).map(
      (snap) => [
        for (final d in snap.docs) TeamPost.fromMap(d.id, plainData(d.data())),
      ],
    );
  });

  @override
  Future<Result<void>> pinPost(String teamId, String postId, {String? unpin}) =>
      guard(
        () =>
            _client.put('${_postPath(teamId, postId)}/pin', {'unpin': ?unpin}),
      );

  @override
  Future<Result<void>> unpinPost(String teamId, String postId) =>
      guard(() => _client.delete('${_postPath(teamId, postId)}/pin'));

  @override
  Stream<List<TeamPostComment>> watchComments(String teamId, String postId) =>
      _shared.get(
        'teamPostComments/$teamId/$postId',
        () =>
            countedSnapshots(
              _posts(teamId)
                  .doc(postId)
                  .collection('comments')
                  .orderBy('createdAt', descending: true)
                  .limit(TeamPostComment.shown),
              'teamPostComments',
            ).map(
              (snap) => [
                for (final d in snap.docs.reversed)
                  TeamPostComment.fromMap(d.id, plainData(d.data())),
              ],
            ),
      );

  @override
  Future<Result<void>> addComment(String teamId, String postId, String body) =>
      guard(
        () => _client.post('${_postPath(teamId, postId)}/comments', {
          'body': body,
        }),
      );

  @override
  Future<Result<void>> deleteComment(
    String teamId,
    String postId,
    String commentId,
  ) => guard(
    () => _client.delete(
      '${_postPath(teamId, postId)}/comments/${Uri.encodeComponent(commentId)}',
    ),
  );
}
