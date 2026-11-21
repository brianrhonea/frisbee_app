import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../../domain/models/app_user.dart';
import '../../../domain/models/team_video.dart';
import '../../../domain/models/video_comment.dart';
import '../../../domain/models/video_folder.dart';
import '../../../utils/result.dart';
import '../../services/api_client.dart';
import '../../services/firestore_utils.dart';
import 'video_repository.dart';

/// Videos live in `teams/{teamId}/videos`; uploaded video files in Cloud Storage
/// under `teams/{teamId}/videos/{videoId}/`. firestore.rules and
/// storage.rules let members watch and owners, coaches and captains write.
/// Notes, comments and event tags (F4-F6) are written through the API
/// ([api]); without one they're read-only.
class VideoRepositoryFirebase implements VideoRepository {
  VideoRepositoryFirebase({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    ApiClient? api,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _storage = storage ?? FirebaseStorage.instance,
       _api = api;

  final FirebaseFirestore _db;
  final FirebaseStorage _storage;
  final ApiClient? _api;

  CollectionReference<Map<String, dynamic>> _videos(String teamId) =>
      _db.collection('teams').doc(teamId).collection('videos');

  CollectionReference<Map<String, dynamic>> _folders(String teamId) =>
      _db.collection('teams').doc(teamId).collection('videoFolders');

  @override
  Stream<List<TeamVideo>> watchVideos(String teamId) =>
      _videos(teamId).snapshots().map(
        (snap) => [
          for (final d in snap.docs)
            TeamVideo.fromMap(d.id, plainData(d.data())),
        ]..sort(TeamVideo.newestFirst),
      );

  @override
  Stream<TeamVideo?> watchVideo(String teamId, String videoId) =>
      _videos(teamId)
          .doc(videoId)
          .snapshots()
          .map(
            (d) =>
                d.exists ? TeamVideo.fromMap(d.id, plainData(d.data())) : null,
          );

  Map<String, dynamic> _created(TeamVideo video, AppUser author) => {
    ...video.toCreateMap(),
    'authorId': author.uid,
    'authorName': author.label,
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  };

  @override
  Future<Result<String>> saveVideo(
    String teamId,
    TeamVideo video,
    AppUser author,
  ) => guard(() async {
    if (video.isNew) {
      final ref = _videos(teamId).doc();
      await ref.set(_created(video, author));
      return ref.id;
    }
    await _videos(teamId).doc(video.id).update({
      ...video.toEditableMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return video.id;
  });

  /// Keeps names readable while dropping characters that would add path
  /// segments or trip up URLs.
  static String _safeName(String name) =>
      name.replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_');

  @override
  Future<Result<String>> uploadVideo(
    String teamId,
    TeamVideo video,
    VideoUpload upload,
    AppUser author, {
    void Function(double progress)? onProgress,
  }) => guard(() async {
    final doc = _videos(teamId).doc();
    final file = VideoFile(
      path: 'teams/$teamId/videos/${doc.id}/${_safeName(upload.name)}',
      name: upload.name,
      size: upload.size,
      contentType: VideoFile.contentTypeFor(upload.name) ?? 'video/mp4',
    );
    final task = _storage
        .ref(file.path)
        .putFile(
          File(upload.path),
          SettableMetadata(contentType: file.contentType),
        );
    final progress = task.snapshotEvents.listen((s) {
      if (s.totalBytes > 0) onProgress?.call(s.bytesTransferred / s.totalBytes);
    }, onError: (_) {});
    try {
      await task;
    } finally {
      await progress.cancel();
    }
    try {
      await doc.set(
        _created(video.copyWith(youtubeId: '', file: file), author),
      );
    } catch (_) {
      await _storage.ref(file.path).delete().catchError((_) {});
      rethrow;
    }
    return doc.id;
  });

  @override
  Future<Result<String>> fileUrl(VideoFile file) =>
      guard(() => _storage.ref(file.path).getDownloadURL());

  @override
  Future<Result<void>> deleteVideo(String teamId, String videoId) =>
      guard(() async {
        final ref = _videos(teamId).doc(videoId);
        final path = TeamVideo.fromMap(
          videoId,
          plainData((await ref.get()).data()),
        ).file?.path;
        // Its notes and comments first: once the video's gone nobody can
        // see them. firestore.rules lets editors delete them for this; if
        // that fails (say, rules not yet deployed) the video still goes.
        await _clearComments(teamId, videoId).catchError((Object _) {});
        await ref.delete();
        // The listing goes first so a failed file delete never leaves a
        // video pointing at nothing.
        if (path != null) {
          await _storage.ref(path).delete().catchError((_) {});
        }
      });

  @override
  Future<Result<void>> moveVideo(
    String teamId,
    String videoId,
    String folderId,
  ) => guard(
    () => _videos(teamId).doc(videoId).update({
      'folderId': folderId,
      'updatedAt': FieldValue.serverTimestamp(),
    }),
  );

  @override
  Stream<List<VideoFolder>> watchFolders(String teamId) =>
      _folders(teamId).snapshots().map(
        (snap) => [
          for (final d in snap.docs)
            VideoFolder.fromMap(d.id, plainData(d.data())),
        ]..sort(VideoFolder.byName),
      );

  @override
  Future<Result<String>> saveFolder(String teamId, VideoFolder folder) =>
      guard(() async {
        final name = folder.name.trim();
        if (folder.isNew) {
          final ref = _folders(teamId).doc();
          await ref.set({
            'name': name,
            'createdAt': FieldValue.serverTimestamp(),
          });
          return ref.id;
        }
        await _folders(teamId).doc(folder.id).update({'name': name});
        return folder.id;
      });

  @override
  Future<Result<void>> deleteFolder(String teamId, String folderId) =>
      guard(() async {
        final filed = await _videos(
          teamId,
        ).where('folderId', isEqualTo: folderId).get();
        // Unsort its videos first, so none is left in a missing folder.
        const chunk = 400;
        for (var i = 0; i < filed.docs.length; i += chunk) {
          final batch = _db.batch();
          for (final d in filed.docs.skip(i).take(chunk)) {
            batch.update(d.reference, {
              'folderId': '',
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }
          await batch.commit();
        }
        await _folders(teamId).doc(folderId).delete();
      });

  CollectionReference<Map<String, dynamic>> _comments(
    String teamId,
    String videoId,
  ) => _videos(teamId).doc(videoId).collection('comments');

  Future<void> _clearComments(String teamId, String videoId) async {
    const chunk = 400;
    for (;;) {
      final snap = await _comments(teamId, videoId).limit(chunk).get();
      if (snap.docs.isEmpty) return;
      final batch = _db.batch();
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
      if (snap.docs.length < chunk) return;
    }
  }

  static const _noApi =
      "Video notes and comments aren't available in this version of the "
      'app. Update the app, or use stall10.app.';

  ApiClient get _client =>
      _api ?? (throw const ApiException('unavailable', _noApi));

  static String _videoPath(String teamId, String videoId) =>
      '/v1/teams/${Uri.encodeComponent(teamId)}/videos/'
      '${Uri.encodeComponent(videoId)}';

  /// `videoCommentLimits.list` in packages/shared.
  static const _commentsMax = 500;

  @override
  bool get canUseVideoExtras => _api != null;

  @override
  Stream<List<VideoComment>> watchComments(String teamId, String videoId) =>
      _comments(teamId, videoId)
          .orderBy('createdAt', descending: true)
          .limit(_commentsMax)
          .snapshots()
          .map(
            (snap) => [
              for (final d in snap.docs)
                VideoComment.fromMap(d.id, plainData(d.data())),
            ],
          );

  @override
  Future<Result<void>> addComment(
    String teamId,
    String videoId, {
    required String body,
    int? atMs,
    int? endMs,
  }) => guard(
    () => _client.post('${_videoPath(teamId, videoId)}/comments', {
      'body': body,
      'atMs': ?atMs,
      'endMs': ?endMs,
    }),
  );

  @override
  Future<Result<void>> deleteComment(
    String teamId,
    String videoId,
    String commentId,
  ) => guard(
    () => _client.delete(
      '${_videoPath(teamId, videoId)}/comments/'
      '${Uri.encodeComponent(commentId)}',
    ),
  );

  @override
  Future<Result<void>> tagEvent(
    String teamId,
    String videoId,
    String? eventId,
  ) => guard(
    () => _client.put('${_videoPath(teamId, videoId)}/event', {
      'eventId': eventId,
    }),
  );

  @override
  Stream<List<TeamVideo>> watchEventVideos(String teamId, String eventId) =>
      _videos(teamId)
          .where('eventId', isEqualTo: eventId)
          .snapshots()
          .map(
            (snap) => [
              for (final d in snap.docs)
                TeamVideo.fromMap(d.id, plainData(d.data())),
            ]..sort(TeamVideo.newestFirst),
          );
}
