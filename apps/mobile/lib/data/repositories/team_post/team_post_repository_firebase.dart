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
import '../../services/upload_client.dart';
import '../outbox/outbox_payloads.dart';
import '../outbox/outbox_repository.dart';
import 'team_post_repository.dart';
import '../../../domain/models/word_filter.dart';

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
    UploadClient? uploads,
  }) : _api = api,
       _files = attachments,
       _db = firestore ?? FirebaseFirestore.instance,
       _shared = sharedStreams ?? SharedStreams.instance,
       _uploads = uploads ?? UploadClient(api: api),
       _outbox = outbox {
    outbox?.register(
      OutboxKind.teamPost,
      OutboxHandler(
        send: (job, files, author) async {
          final body = OutboxPayloads.teamPost(job);
          if (body == null) {
            return Result.error(
              const ApiException(
                'failed_precondition',
                OutboxPayloads.unmappable,
              ),
            );
          }
          return _create(job.target, job.id, body, files, ledger: outbox);
        },
        sent: (job) => existsOnServer(_posts(job.target).doc(job.id)),
      ),
    );
  }

  final UploadClient _uploads;

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
    final p = draft.post;
    if (refuseBlockedWords<void>([p.title, p.body, p.location]) case final r?) {
      return r;
    }
    draft = PostDraft(
      post: p.copyWith(
        title: maskSwearing(p.title),
        body: maskSwearing(p.body),
        location: maskSwearing(p.location),
      ),
      newImages: draft.newImages,
    );
    if (draft.newImages.where((i) => i.tooLarge).firstOrNull case final big?) {
      return Future.value(
        Result.error(
          AttachmentTooLargeException(
            big.name,
            limit: maxBytesFor(big.contentType),
          ),
        ),
      );
    }
    // Only new posts wait offline; an edit needs the post as it stands, so
    // offline it fails with a retry (contracts/phase1-writes.md D8).
    if (!draft.post.isNew) return _edit(teamId, draft);
    final id = _posts(teamId).doc().id;
    final outbox = _outbox;
    final post = draft.post;
    Future<Result<void>> now() {
      final body = OutboxPayloads.teamPost(
        OutboxJob(
          id: id,
          uid: author.uid,
          kind: OutboxKind.teamPost,
          createdAt: DateTime.now(),
          target: teamId,
          label: 'Team post',
          payload: {'post': jsonSafe(post.toEditableMap())},
          files: [
            for (final (i, f) in draft.newImages.indexed)
              OutboxFile(name: f.name, path: '$id/$i', size: f.size),
          ],
        ),
      );
      if (body == null) {
        return Future.value(
          Result.error(
            const ApiException(
              'invalid_argument',
              'Write something or add a photo.',
            ),
          ),
        );
      }
      return _create(teamId, id, body, draft.newImages, ledger: outbox);
    }

    if (outbox == null) return now();
    return outbox.submit(
      kind: OutboxKind.teamPost,
      id: id,
      target: teamId,
      label: 'Team post',
      payload: {'post': post.toEditableMap()},
      files: draft.newImages,
      sendNow: now,
    );
  }

  /// `POST /v1/teams/:teamId/posts` for post [id]: uploads the photos first
  /// (`teamImage`, for the team and post), then sends [body] with `id` and
  /// `uploadIds`. A 409 is `already_exists`, which the queue counts as sent.
  Future<Result<void>> _create(
    String teamId,
    String id,
    Map<String, Object?> body,
    List<NewAttachment> files, {
    UploadLedger? ledger,
  }) => guard(() async {
    final api = _api.required;
    final ready = files.isEmpty
        ? const <ReadyUpload>[]
        : await _uploads.uploadAll(
            purpose: UploadPurpose.teamImage,
            itemId: id,
            targetId: teamId,
            files: files,
            ledger: ledger,
            ledgerKey: id,
          );
    await api.post('/v1/teams/${Uri.encodeComponent(teamId)}/posts', {
      ...body,
      'id': id,
      'uploadIds': [for (final u in ready) u.id],
    });
  });

  /// `PATCH /v1/teams/:teamId/posts/:postId`: the text, links, the photos
  /// kept (`keepImages`) and new ones uploaded.
  Future<Result<void>> _edit(String teamId, PostDraft draft) => guard(() async {
    final api = _api.required;
    final post = draft.post;
    final ready = draft.newImages.isEmpty
        ? const <ReadyUpload>[]
        : await _uploads.uploadAll(
            purpose: UploadPurpose.teamImage,
            itemId: post.id,
            targetId: teamId,
            files: draft.newImages,
          );
    await api.patch(_postPath(teamId, post.id), {
      'title': post.title.trim(),
      'body': post.body,
      'location': post.location.trim(),
      'links': post.links,
      'public': post.isPublic,
      'keepImages': [for (final i in post.images) i.path],
      'uploadIds': [for (final u in ready) u.id],
      'tournamentKey': ?post.tournamentKey,
    });
  });

  @override
  Future<Result<void>> deletePost(String teamId, String postId) =>
      guard(() => _api.required.delete(_postPath(teamId, postId)));

  @override
  Future<Result<Uint8List>> downloadImage(ChatAttachment image) =>
      guard(() => _files.download(image));

  // Pins and comments (redesign F24) ------------------------------------

  static const _noApi =
      "Pins and comments aren't available in this version of the app. "
      'Update the app, or use stall10.app.';

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
