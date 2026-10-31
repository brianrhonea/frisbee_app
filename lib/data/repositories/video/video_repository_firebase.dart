import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../domain/models/app_user.dart';
import '../../../domain/models/team_video.dart';
import '../../../utils/result.dart';
import '../../services/firestore_utils.dart';
import 'video_repository.dart';

/// Videos live in `teams/{teamId}/videos`; firestore.rules lets members
/// read them and owners, coaches and captains write them.
class VideoRepositoryFirebase implements VideoRepository {
  VideoRepositoryFirebase({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _videos(String teamId) =>
      _db.collection('teams').doc(teamId).collection('videos');

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

  @override
  Future<Result<String>> saveVideo(
    String teamId,
    TeamVideo video,
    AppUser author,
  ) => guard(() async {
    if (video.isNew) {
      final ref = _videos(teamId).doc();
      await ref.set({
        ...video.toEditableMap(),
        'authorId': author.uid,
        'authorName': author.label,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return ref.id;
    }
    await _videos(teamId).doc(video.id).update({
      ...video.toEditableMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return video.id;
  });

  @override
  Future<Result<void>> deleteVideo(String teamId, String videoId) =>
      guard(() => _videos(teamId).doc(videoId).delete());
}
