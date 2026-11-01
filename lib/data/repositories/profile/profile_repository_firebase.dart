import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../domain/models/app_user.dart';
import '../../../domain/models/direct_message.dart';
import '../../../domain/models/model_utils.dart';
import '../../../domain/models/player_profile.dart';
import '../../../utils/result.dart';
import '../../services/firestore_utils.dart';
import 'profile_repository.dart';

/// Profiles live beside the direct-message directory in `profiles/{uid}`;
/// `keywords` index the name and `tags` the school, hometown and teams.
/// Writes merge, so the directory fields and these never clobber each
/// other.
class ProfileRepositoryFirebase implements ProfileRepository {
  ProfileRepositoryFirebase({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static const _searchLimit = 20;

  CollectionReference<Map<String, dynamic>> get _profiles =>
      _db.collection('profiles');

  /// The directory fields every write carries, so the doc stays valid
  /// even if this write creates it.
  Map<String, dynamic> _base(AppUser user, List<String> tags) => {
    ...UserProfile(
      uid: user.uid,
      name: user.label,
      photoUrl: user.photoUrl,
    ).toMap(),
    'tags': tags,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  @override
  Stream<PlayerProfile?> watchProfile(String uid) => _profiles
      .doc(uid)
      .snapshots()
      .map(
        (d) =>
            d.exists ? PlayerProfile.fromMap(d.id, plainData(d.data()!)) : null,
      );

  @override
  Future<Result<void>> saveDetails(
    AppUser user,
    ProfileDetails details, {
    required List<String> tags,
  }) => guard(
    () => _profiles.doc(user.uid).set({
      ..._base(user, tags),
      ...details.toMap(),
    }, SetOptions(merge: true)),
  );

  @override
  Future<Result<void>> publishSummary(
    AppUser user,
    ProfileSummary summary, {
    required List<String> tags,
  }) => guard(
    () => _profiles.doc(user.uid).set({
      ..._base(user, tags),
      'teams': [for (final t in summary.teams) t.toMap()],
      // Replaced whole, so seasons that no longer have games go away.
      'stats': {
        for (final e in summary.seasons.entries) e.key: e.value.toMap(),
      },
      'games': [for (final g in summary.games) g.toMap()],
      'summaryUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(mergeFields: _summaryFields)),
  );

  static final _summaryFields = [
    'name',
    'keywords',
    'photoUrl',
    'tags',
    'updatedAt',
    'teams',
    'stats',
    'games',
    'summaryUpdatedAt',
  ];

  @override
  Future<Result<List<PlayerProfile>>> searchPlayers(String query) => guard(
    () async {
      final words = searchWords(query);
      if (words.isEmpty) return const [];
      // Match the longest word in Firestore, by name or by tag, then the
      // rest here.
      final key = (words.toList()..sort((a, b) => b.length - a.length)).first;
      final k = key.length > 20 ? key.substring(0, 20) : key;
      final snaps = await Future.wait([
        _profiles
            .where('keywords', arrayContains: k)
            .limit(_searchLimit * 2)
            .get(),
        _profiles.where('tags', arrayContains: k).limit(_searchLimit * 2).get(),
      ]);
      final byId = <String, PlayerProfile>{
        for (final s in snaps)
          for (final d in s.docs)
            d.id: PlayerProfile.fromMap(d.id, plainData(d.data())),
      };
      return byId.values
          .where((p) => p.matches(query))
          .take(_searchLimit)
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    },
  );
}
