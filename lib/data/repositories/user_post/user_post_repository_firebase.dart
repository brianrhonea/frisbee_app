import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../domain/models/app_user.dart';
import '../../../domain/models/chat.dart';
import '../../../domain/models/user_post.dart';
import '../../../utils/result.dart';
import '../../services/attachment_storage.dart';
import '../../services/firestore_utils.dart';
import 'user_post_repository.dart';

class UserPostRepositoryFirebase implements UserPostRepository {
  UserPostRepositoryFirebase({
    required AttachmentStorage attachments,
    FirebaseFirestore? firestore,
  }) : _files = attachments,
       _db = firestore ?? FirebaseFirestore.instance;

  final AttachmentStorage _files;
  final FirebaseFirestore _db;

  /// Firestore takes at most 30 values in an `in` filter.
  static const inLimit = 30;

  CollectionReference<Map<String, dynamic>> get _posts =>
      _db.collection('posts');

  static String imageFolder(String uid, String postId) =>
      'users/$uid/posts/$postId/${DateTime.now().millisecondsSinceEpoch}';

  List<UserPost> _list(QuerySnapshot<Map<String, dynamic>> snap) => [
    for (final d in snap.docs) UserPost.fromMap(d.id, plainData(d.data())),
  ];

  @override
  Stream<List<UserPost>> watchPostsBy(String authorId, {int limit = 50}) =>
      watchPostsByAuthors([authorId], limit: limit);

  @override
  Stream<List<UserPost>> watchPostsByAuthors(
    List<String> authorIds, {
    int limit = 50,
  }) => _watchIn('authorId', authorIds, limit);

  @override
  Stream<List<UserPost>> watchPostsForTournaments(
    List<String> tournamentKeys, {
    int limit = 50,
  }) => _watchIn('tournamentKey', tournamentKeys, limit);

  /// Newest [limit] posts whose [field] is one of [values], querying in
  /// chunks of [inLimit] and merging.
  Stream<List<UserPost>> _watchIn(
    String field,
    List<String> values,
    int limit,
  ) {
    final unique = values.toSet().toList();
    if (unique.isEmpty) return Stream.value(const []);
    final chunks = [
      for (var i = 0; i < unique.length; i += inLimit)
        unique.skip(i).take(inLimit).toList(),
    ];
    final queries = [
      for (final c in chunks)
        _posts
            .where(field, whereIn: c)
            .orderBy('createdAt', descending: true)
            .limit(limit)
            .snapshots()
            .map(_list),
    ];
    if (queries.length == 1) return queries.single;
    return _combine(queries, limit);
  }

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
      .map(
        (d) => d.exists ? UserPost.fromMap(d.id, plainData(d.data())) : null,
      );

  @override
  Future<Result<String>> savePost(
    UserPostDraft draft,
    AppUser author,
  ) => guard(() async {
    final post = draft.post;
    final ref = post.isNew ? _posts.doc() : _posts.doc(post.id);
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
