import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../domain/models/app_user.dart';
import '../../../domain/models/chat.dart';
import '../../../domain/models/user_post.dart';
import '../../../utils/result.dart';
import '../../services/api_client.dart';
import '../../services/attachment_storage.dart';
import '../../services/firestore_utils.dart';
import 'user_post_repository.dart';
import '../../../domain/models/outbox.dart';
import '../outbox/outbox_repository.dart';

/// Reads and writes `posts` in Firestore; the community feed comes from
/// the Stall 10 API ([ApiClient], `GET /v1/feed`), which leaves out private
/// profiles' posts as the website's does.
class UserPostRepositoryFirebase implements UserPostRepository {
  UserPostRepositoryFirebase({
    required AttachmentStorage attachments,
    FirebaseFirestore? firestore,
    ApiClient? api,
    OutboxRepository? outbox,
  }) : _files = attachments,
       _db = firestore ?? FirebaseFirestore.instance,
       _api = api,
       _outbox = outbox {
    outbox?.register(
      OutboxKind.userPost,
      OutboxHandler(
        send: (job, files, author) async {
          final post = UserPost.fromMap(
            '',
            Map<String, dynamic>.from(job.payload['post'] as Map? ?? const {}),
          );
          final r = await _save(
            UserPostDraft(post: post, newImages: files),
            author,
            newId: job.id,
          );
          return switch (r) {
            Ok() => const Result.ok(null),
            Error(:final error) => Result.error(error),
          };
        },
        sent: (job) => existsOnServer(_posts.doc(job.id)),
      ),
    );
  }

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

  static String imageFolder(String uid, String postId) =>
      'users/$uid/posts/$postId/${DateTime.now().millisecondsSinceEpoch}';

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
    final outbox = _outbox;
    // Only new posts wait offline; an edit needs the post as it stands.
    if (outbox == null ||
        !draft.post.isNew ||
        draft.newImages.any((i) => i.tooLarge)) {
      return _save(draft, author);
    }
    final id = _posts.doc().id;
    final r = await outbox.submit(
      kind: OutboxKind.userPost,
      id: id,
      target: 'posts',
      label: 'Post',
      payload: {'post': draft.post.toEditableMap()},
      files: draft.newImages,
      sendNow: () async => switch (await _save(draft, author, newId: id)) {
        Ok() => const Result.ok(null),
        Error(:final error) => Result.error(error),
      },
    );
    return switch (r) {
      Ok() => Result.ok(id),
      Error(:final error) => Result.error(error),
    };
  }

  /// Saves [draft]; a new post gets [newId] (the queue's) or a fresh id.
  Future<Result<String>> _save(
    UserPostDraft draft,
    AppUser author, {
    String? newId,
  }) => guard(() async {
    final post = draft.post;
    final ref = post.isNew ? _posts.doc(newId) : _posts.doc(post.id);
    final before = post.isNew
        ? const <ChatAttachment>[]
        : UserPost.fromMap(ref.id, plainData((await ref.get()).data())).images;
    final uploaded = draft.newImages.isEmpty
        ? const <ChatAttachment>[]
        : await _files.upload(imageFolder(author.uid, ref.id), draft.newImages);
    final saved = post.copyWith(images: [...post.images, ...uploaded]);
    try {
      if (post.isNew) {
        await ref.set({
          ...saved.toEditableMap(),
          'authorId': author.uid,
          'authorName': author.label,
          'authorPhotoUrl': author.photoUrl,
          'private': await _profileIsPrivate(author.uid),
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
    return ref.id;
  });

  @override
  Future<Result<void>> setLiked(String postId, String uid, bool liked) => guard(
    () => _posts.doc(postId).update({
      'likedBy': liked
          ? FieldValue.arrayUnion([uid])
          : FieldValue.arrayRemove([uid]),
    }),
  );

  @override
  Future<Result<String>> repost(UserPost original, String note, AppUser me) =>
      guard(() async {
        final post = UserPost.repost(original, note: note);
        final originalId = post.originalId;
        final id = UserPost.repostId(originalId, me.uid);
        final private = await _profileIsPrivate(me.uid);
        // Both or neither, so the count matches the reposts.
        final batch = _db.batch()
          ..set(_posts.doc(id), {
            ...post.toEditableMap(),
            'authorId': me.uid,
            'authorName': me.label,
            'authorPhotoUrl': me.photoUrl,
            'private': private,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          })
          ..update(_posts.doc(originalId), {
            'repostedBy': FieldValue.arrayUnion([me.uid]),
          });
        await batch.commit();
        return id;
      });

  @override
  Future<Result<void>> undoRepost(String originalId, String uid) =>
      guard(() async {
        final batch = _db.batch()
          ..delete(_posts.doc(UserPost.repostId(originalId, uid)))
          ..update(_posts.doc(originalId), {
            'repostedBy': FieldValue.arrayRemove([uid]),
          });
        await batch.commit();
      });

  @override
  Future<Result<void>> deletePost(String id) => guard(() async {
    final ref = _posts.doc(id);
    final images = UserPost.fromMap(
      id,
      plainData((await ref.get()).data()),
    ).images;
    await ref.delete();
    await _files.delete(images.map((i) => i.path));
  });

  @override
  Future<Result<Uint8List>> downloadImage(ChatAttachment image) =>
      guard(() => _files.download(image));
}
