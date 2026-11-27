import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../domain/models/app_user.dart';
import '../../../domain/models/chat.dart';
import '../../../domain/models/user_post.dart';
import '../../../utils/result.dart';
import '../../services/api_client.dart';
import '../../services/attachment_storage.dart';
import '../../services/upload_client.dart';
import '../../services/firestore_utils.dart';
import 'user_post_repository.dart';
import '../../../domain/models/outbox.dart';
import '../outbox/outbox_payloads.dart';
import '../outbox/outbox_repository.dart';
import '../../../domain/models/word_filter.dart';
import '../../../domain/models/follow.dart';

/// Reads and writes `posts` in Firestore; the community feed comes from
/// the Stall 10 API ([ApiClient], `GET /v1/feed`), which leaves out private
/// profiles' posts as the website's does.
class UserPostRepositoryFirebase implements UserPostRepository {
  UserPostRepositoryFirebase({
    required AttachmentStorage attachments,
    FirebaseFirestore? firestore,
    ApiClient? api,
    UploadClient? uploads,
    OutboxRepository? outbox,
  }) : _files = attachments,
       _db = firestore ?? FirebaseFirestore.instance,
       _api = api,
       _uploads = uploads ?? UploadClient(api: api),
       _outbox = outbox {
    outbox?.register(
      OutboxKind.userPost,
      OutboxHandler(
        send: (job, files, author) async {
          final post = _queuedPost(job);
          if (post != null && _isRecordedWorkout(post)) {
            return _asVoid(
              await _saveRecordedWorkout(post, author, job.id, files),
            );
          }
          final body = OutboxPayloads.userPost(job);
          if (body == null) {
            return Result.error(
              const ApiException(
                'failed_precondition',
                OutboxPayloads.unmappable,
              ),
            );
          }
          return _asVoid(
            await _create(job.id, body, files, ledger: outbox, key: job.id),
          );
        },
        sent: (job) => existsOnServer(_posts.doc(job.id)),
      ),
    );
  }

  static Result<void> _asVoid<T>(Result<T> r) => switch (r) {
    Ok() => const Result.ok(null),
    Error(:final error) => Result.error(error),
  };

  /// The post a queued job holds, as the composer made it.
  static UserPost? _queuedPost(OutboxJob job) => job.payload['post'] is Map
      ? UserPost.fromMap(
          '',
          Map<String, dynamic>.from(job.payload['post'] as Map),
        )
      : null;

  /// A recorded run (with its GPS route or seconds): the API's workout can't
  /// carry those yet, so it's saved the old way. See
  /// [OutboxPayloads.workoutNeedsDirect].
  static bool _isRecordedWorkout(UserPost post) =>
      OutboxPayloads.workoutNeedsDirect(post.workout?.toMap());

  final UploadClient _uploads;

  /// Holds new posts made offline until they can go out.
  final OutboxRepository? _outbox;

  final AttachmentStorage _files;
  final FirebaseFirestore _db;

  /// The Stall 10 API, when this build has one.
  final ApiClient? _api;

  /// Firestore takes at most 30 values in an `in` filter.
  static const inLimit = 30;

  CollectionReference<Map<String, dynamic>> get _posts =>
      _db.collection('posts');

  /// Whether [uid]'s profile is private: their new posts say so
  /// (`private`, which the rules check against the profile).
  Future<bool> _profileIsPrivate(String uid) async =>
      (await _db.collection('profiles').doc(uid).get()).data()?['private'] ==
      true;

  List<UserPost> _list(QuerySnapshot<Map<String, dynamic>> snap) => [
    for (final d in snap.docs) UserPost.fromMap(d.id, plainData(d.data())),
  ];

  @override
  Stream<List<UserPost>> watchPostsBy(
    String authorId, {
    int limit = 50,
    bool includePrivate = false,
  }) => watchPostsByAuthors(
    [authorId],
    limit: limit,
    includePrivate: includePrivate ? {authorId} : const {},
  );

  @override
  Stream<List<UserPost>> watchPostsByAuthors(
    List<String> authorIds, {
    int limit = 50,
    Set<String> includePrivate = const {},
  }) {
    final (:everything, :public) = _splitAuthors(authorIds, includePrivate);
    final queries = [
      // One whose follow was taken away (removed, or unfollowed a moment
      // ago) is refused by the rules: shown as none, not a failed feed.
      for (final a in everything)
        _newest(
          _posts.where('authorId', isEqualTo: a),
          limit,
        ).transform(_hiddenIsGone),
      for (final c in _chunks(public))
        _newest(_publicOnly.where('authorId', whereIn: c), limit),
    ];
    return _merge(queries, limit);
  }

  @override
  Stream<List<UserPost>> watchPostsForTournaments(
    List<String> tournamentKeys, {
    int limit = 50,
  }) => _watchIn('tournamentKey', tournamentKeys, limit);

  @override
  Stream<List<UserPost>> watchPostsForTeamEvents(
    List<String> teamIds, {
    int limit = 50,
  }) => _watchIn('event.teamId', teamIds, limit);

  @override
  Future<Result<List<UserPost>>> fetchPostsBefore(
    UserPostFilter filter,
    List<String> values, {
    required DateTime before,
    int limit = 20,
    Set<String> includePrivate = const {},
  }) => guard(() async {
    Future<List<UserPost>> page(Query<Map<String, dynamic>> q) => q
        .where('createdAt', isLessThan: Timestamp.fromDate(before))
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get()
        .then(_list);
    final List<Future<List<UserPost>>> pages;
    if (filter == UserPostFilter.authors) {
      final (:everything, :public) = _splitAuthors(values, includePrivate);
      pages = [
        // A follow taken away: none, as in watchPostsByAuthors.
        for (final a in everything)
          page(_posts.where('authorId', isEqualTo: a)).catchError(
            (Object _) => const <UserPost>[],
            test: (e) =>
                e is FirebaseException && e.code == 'permission-denied',
          ),
        for (final c in _chunks(public))
          page(_publicOnly.where('authorId', whereIn: c)),
      ];
    } else {
      final field = filter == UserPostFilter.tournaments
          ? 'tournamentKey'
          : 'event.teamId';
      pages = [
        for (final c in _chunks(values.toSet().toList()))
          page(_publicOnly.where(field, whereIn: c)),
      ];
    }
    final all = [for (final l in await Future.wait(pages)) ...l]
      ..sort(UserPost.newestFirst);
    return all.take(limit).toList();
  });

  /// Public posts (the rules let anyone read those in any query).
  Query<Map<String, dynamic>> get _publicOnly =>
      _posts.where('private', isEqualTo: false);

  /// [authorIds] split into those asked for one at a time, every post
  /// (the ones in [includePrivate]), and the rest, public posts only.
  static ({List<String> everything, List<String> public}) _splitAuthors(
    List<String> authorIds,
    Set<String> includePrivate,
  ) {
    final unique = authorIds.toSet().toList();
    return (
      everything: [
        for (final a in unique)
          if (includePrivate.contains(a)) a,
      ],
      public: [
        for (final a in unique)
          if (!includePrivate.contains(a)) a,
      ],
    );
  }

  static List<List<String>> _chunks(List<String> values) => [
    for (var i = 0; i < values.length; i += inLimit)
      values.skip(i).take(inLimit).toList(),
  ];

  Stream<List<UserPost>> _newest(Query<Map<String, dynamic>> q, int limit) => q
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map(_list);

  static Stream<List<UserPost>> _merge(
    List<Stream<List<UserPost>>> queries,
    int limit,
  ) => switch (queries.length) {
    0 => Stream.value(const []),
    1 => queries.single,
    _ => _combine(queries, limit),
  };

  @override
  bool get hasCommunityFeed => _api != null;

  @override
  bool get hasTagTournaments => _api != null;

  @override
  Future<Result<List<FollowTarget>>> tagTournaments() => guard(() async {
    final api = _api;
    if (api == null) {
      throw const ApiException('unavailable', 'Needs the API.');
    }
    final r = await api.send('GET', '/v1/me/tag-tournaments');
    final out = <FollowTarget>[];
    for (final t in (r['tournaments'] as List?) ?? const []) {
      if (t is! Map) continue;
      final k = FollowTarget.parseTournamentKey(t['key'] as String?);
      if (k == null) continue;
      out.add(
        FollowTarget.tournament(
          k.hostId,
          k.tournamentId,
          t['name'] as String? ?? 'Tournament',
        ),
      );
    }
    return out;
  });

  @override
  Future<Result<CommunityFeedPage>> fetchCommunityPage({int? before}) =>
      guard(() async {
        final api = _api;
        if (api == null) {
          throw const ApiException(
            'unavailable',
            "The community feed isn't available in this build.",
          );
        }
        final page = await api.send(
          'GET',
          before == null ? '/v1/feed' : '/v1/feed?before=$before',
        );
        final next = page['next'];
        return (
          ids: [
            for (final p in (page['posts'] as List?) ?? const [])
              if (p is Map && p['id'] is String) p['id'] as String,
          ],
          next: next is num ? next.toInt() : null,
        );
      });

  @override
  Stream<List<UserPost>> watchPostsByIds(List<String> ids) {
    final unique = ids.toSet().toList();
    // One listener a post, not an `in` query: the rules check a query by
    // id post by post, so one that turned private (and this user doesn't
    // follow) would fail them all. Such a post just drops out.
    return _merge([
      for (final id in unique)
        _posts
            .doc(id)
            .snapshots()
            .map(
              (d) => d.exists
                  ? [UserPost.fromMap(d.id, plainData(d.data()))]
                  : const <UserPost>[],
            )
            .transform(_hiddenIsGone),
    ], unique.length);
  }

  /// A post the rules won't let this user read is left out.
  static final _hiddenIsGone =
      StreamTransformer<List<UserPost>, List<UserPost>>.fromHandlers(
        handleError: (e, stack, sink) =>
            e is FirebaseException && e.code == 'permission-denied'
            ? sink.add(const [])
            : sink.addError(e, stack),
      );

  /// Newest [limit] public posts whose [field] is one of [values], querying
  /// in chunks of [inLimit] and merging.
  Stream<List<UserPost>> _watchIn(
    String field,
    List<String> values,
    int limit,
  ) => _merge([
    for (final c in _chunks(values.toSet().toList()))
      _newest(_publicOnly.where(field, whereIn: c), limit),
  ], limit);

  static Stream<List<UserPost>> _combine(
    List<Stream<List<UserPost>>> streams,
    int limit,
  ) {
    late final StreamController<List<UserPost>> out;
    final latest = List<List<UserPost>?>.filled(streams.length, null);
    final subs = <StreamSubscription<List<UserPost>>>[];
    void emit() {
      if (latest.any((l) => l == null)) return;
      final all = [for (final l in latest) ...?l]..sort(UserPost.newestFirst);
      out.add(all.take(limit).toList());
    }

    out = StreamController<List<UserPost>>(
      onListen: () {
        for (var i = 0; i < streams.length; i++) {
          subs.add(
            streams[i].listen((v) {
              latest[i] = v;
              emit();
            }, onError: out.addError),
          );
        }
      },
      onCancel: () async {
        for (final s in subs) {
          await s.cancel();
        }
      },
    );
    return out.stream;
  }

  @override
  Stream<UserPost?> watchPost(String id) => _posts
      .doc(id)
      .snapshots()
      .map((d) => d.exists ? UserPost.fromMap(d.id, plainData(d.data())) : null)
      .handleError(
        // A private profile's post, for someone they haven't approved.
        (Object e) => throw const PostHiddenException(),
        test: (e) => e is FirebaseException && e.code == 'permission-denied',
      );

  @override
  Future<Result<String>> savePost(UserPostDraft draft, AppUser author) async {
    if (refuseBlockedWords<String>([draft.post.body]) case final r?) return r;
    draft = UserPostDraft(
      post: draft.post.copyWith(body: maskSwearing(draft.post.body)),
      newImages: draft.newImages,
    );
    if (draft.newImages.where((i) => i.tooLarge).firstOrNull case final big?) {
      return Result.error(
        AttachmentTooLargeException(
          big.name,
          limit: maxBytesFor(big.contentType),
        ),
      );
    }
    // Only new posts wait offline; an edit needs the post as it stands, so
    // offline it fails with a retry (contracts/phase1-writes.md D8).
    if (!draft.post.isNew) return _edit(draft);
    final id = _posts.doc().id;
    final post = draft.post;
    final outbox = _outbox;
    Future<Result<void>> now() async {
      if (_isRecordedWorkout(post)) {
        return _asVoid(
          await _saveRecordedWorkout(post, author, id, draft.newImages),
        );
      }
      final body = OutboxPayloads.userPost(
        OutboxJob(
          id: id,
          uid: author.uid,
          kind: OutboxKind.userPost,
          createdAt: DateTime.now(),
          target: 'posts',
          label: 'Post',
          payload: {'post': jsonSafe(post.toEditableMap())},
          files: [
            for (final (i, f) in draft.newImages.indexed)
              OutboxFile(name: f.name, path: '$id/$i', size: f.size),
          ],
        ),
      );
      if (body == null) {
        return Result.error(
          const ApiException(
            'invalid_argument',
            'Write something or add a photo.',
          ),
        );
      }
      return _asVoid(
        await _create(id, body, draft.newImages, ledger: outbox, key: id),
      );
    }

    if (outbox == null) {
      return switch (await now()) {
        Ok() => Result.ok(id),
        Error(:final error) => Result.error(error),
      };
    }
    final r = await outbox.submit(
      kind: OutboxKind.userPost,
      id: id,
      target: 'posts',
      label: 'Post',
      payload: {'post': post.toEditableMap()},
      files: draft.newImages,
      sendNow: now,
    );
    return switch (r) {
      Ok() => Result.ok(id),
      Error(:final error) => Result.error(error),
    };
  }

  /// `POST /v1/posts` for post [id]: uploads [files] first (photos, under
  /// [id]), then sends [body] with `id` and `uploadIds`. A 409 (it's
  /// already there) comes back as an `already_exists` error, which the
  /// queue counts as sent.
  Future<Result<String>> _create(
    String id,
    Map<String, Object?> body,
    List<NewAttachment> files, {
    UploadLedger? ledger,
    String? key,
  }) => guard(() async {
    final api = _api.required;
    final ready = files.isEmpty
        ? const <ReadyUpload>[]
        : await _uploads.uploadAll(
            purpose: UploadPurpose.post,
            itemId: id,
            files: files,
            ledger: ledger,
            ledgerKey: key,
          );
    final r = await api.post('/v1/posts', {
      ...body,
      'id': id,
      'uploadIds': [for (final u in ready) u.id],
    });
    return r['id'] as String? ?? id;
  });

  /// A recorded run saved straight to Firestore: its GPS route and seconds
  /// aren't in the API's workout yet.
  Future<Result<String>> _saveRecordedWorkout(
    UserPost post,
    AppUser author,
    String id,
    List<NewAttachment> files,
  ) => guard(() async {
    final ref = _posts.doc(id);
    // A replay of a post that already landed uploads nothing more.
    if (files.isNotEmpty && await existsOnServer(ref)) return id;
    // Photos go to Storage as before (users/{uid}/posts/{id}/...).
    final uploaded = files.isEmpty
        ? const <ChatAttachment>[]
        : await _files.upload(
            'users/${author.uid}/posts/$id/'
            '${DateTime.now().millisecondsSinceEpoch}',
            files,
          );
    final saved = post.copyWith(images: [...post.images, ...uploaded]);
    try {
      await ref.set({
        ...saved.toEditableMap(),
        'authorId': author.uid,
        'authorName': author.label,
        'authorPhotoUrl': author.photoUrl,
        'private': await _profileIsPrivate(author.uid),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      await _files
          .delete(uploaded.map((i) => i.path))
          .catchError((Object _) => <void>[]);
      rethrow;
    }
    return id;
  });

  /// `PATCH /v1/posts/:id`: the words, links and photos. The workout and a
  /// shared event can't change; a repost only has its note.
  Future<Result<String>> _edit(UserPostDraft draft) => guard(() async {
    final api = _api.required;
    final post = draft.post;
    final ready = draft.newImages.isEmpty
        ? const <ReadyUpload>[]
        : await _uploads.uploadAll(
            purpose: UploadPurpose.post,
            itemId: post.id,
            files: draft.newImages,
          );
    final body = <String, Object?>{'body': post.body.trim()};
    if (!post.isRepost) {
      body
        ..['links'] = post.links
        ..['keepImages'] = [for (final i in post.images) i.path]
        ..['uploadIds'] = [for (final u in ready) u.id]
        // Null takes the tag off.
        ..['tournament'] = post.tournamentKey == null
            ? null
            : {'key': post.tournamentKey, 'name': post.tournamentName ?? ''};
    }
    await api.patch('/v1/posts/${Uri.encodeComponent(post.id)}', body);
    return post.id;
  });

  @override
  Future<Result<void>> setLiked(String postId, String uid, bool liked) => guard(
    () => _api.required.send(
      liked ? 'PUT' : 'DELETE',
      '/v1/posts/${Uri.encodeComponent(postId)}/like',
    ),
  );

  @override
  Future<Result<String>> repost(UserPost original, String note, AppUser me) =>
      guard(() async {
        final originalId = original.originalId;
        await _api.required.put(
          '/v1/posts/${Uri.encodeComponent(originalId)}/repost',
          {'note': cleanText(note).trim()},
        );
        return UserPost.repostId(originalId, me.uid);
      });

  @override
  Future<Result<void>> undoRepost(String originalId, String uid) => guard(
    () => _api.required.send(
      'DELETE',
      '/v1/posts/${Uri.encodeComponent(originalId)}/repost',
    ),
  );

  @override
  Future<Result<void>> deletePost(String id) =>
      guard(() => _api.required.delete('/v1/posts/${Uri.encodeComponent(id)}'));

  @override
  Future<Result<Uint8List>> downloadImage(ChatAttachment image) =>
      guard(() => _files.download(image));
}
