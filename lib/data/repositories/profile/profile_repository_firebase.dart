import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../domain/models/app_user.dart';
import '../../../domain/models/direct_message.dart';
import '../../../domain/models/model_utils.dart';
import '../../../domain/models/player_profile.dart';
import '../../../domain/models/username.dart';
import '../../../utils/result.dart';
import '../../services/firestore_utils.dart';
import 'profile_repository.dart';

/// Profiles live beside the direct-message directory in `profiles/{uid}`;
/// `keywords` index the name and `tags` the school, hometown and teams.
/// Writes merge, so the directory fields and these never clobber each
/// other.
///
/// A private profile (`private: true`) keeps only the directory fields
/// there; the details, summary and tags go to `profiles/{uid}/private/
/// details`, which firestore.rules opens only to the player and to people
/// who follow them (a follow of a private profile needs the player's OK).
class ProfileRepositoryFirebase implements ProfileRepository {
  ProfileRepositoryFirebase({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static const _searchLimit = 20;

  CollectionReference<Map<String, dynamic>> get _profiles =>
      _db.collection('profiles');

  DocumentReference<Map<String, dynamic>> _hidden(String uid) =>
      _profiles.doc(uid).collection('private').doc('details');

  Future<bool> _isPrivate(String uid) async =>
      (await _profiles.doc(uid).get()).data()?['private'] == true;

  /// The directory fields every write carries, so the doc stays valid
  /// even if this write creates it.
  Map<String, dynamic> _base(AppUser user, List<String> tags) => {
    ...UserProfile(
      uid: user.uid,
      name: user.label,
      photoUrl: user.photoUrl,
      username: user.username,
    ).toMap(),
    'tags': tags,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  /// The public doc, joined with the private one when the profile is
  /// private. Refused (not an accepted follower) means locked.
  @override
  Stream<PlayerProfile?> watchProfile(String uid) {
    late final StreamController<PlayerProfile?> out;
    StreamSubscription<Object?>? mainSub;
    StreamSubscription<Object?>? hiddenSub;
    Map<String, dynamic>? main;
    Map<String, dynamic>? hidden;
    var hiddenLoaded = false;

    void emit() {
      final m = main;
      if (m == null) return out.add(null);
      if (m['private'] != true) return out.add(PlayerProfile.fromMap(uid, m));
      if (!hiddenLoaded) return;
      final h = hidden;
      out.add(
        PlayerProfile.fromMap(uid, {
          ...m,
          ...?h,
          'private': true,
        }, locked: h == null),
      );
    }

    void watchHidden() {
      if (hiddenSub != null) return;
      hiddenSub = _hidden(uid).snapshots().listen(
        (d) {
          hidden = d.exists ? plainData(d.data()!) : const {};
          hiddenLoaded = true;
          emit();
        },
        onError: (Object e) {
          if (e is! FirebaseException || e.code != 'permission-denied') {
            out.addError(e);
          }
          hidden = null;
          hiddenLoaded = true;
          emit();
        },
      );
    }

    out = StreamController<PlayerProfile?>(
      onListen: () {
        mainSub = _profiles.doc(uid).snapshots().listen((d) {
          final data = d.exists ? plainData(d.data()!) : null;
          main = data;
          if (data?['private'] == true) {
            watchHidden();
          } else {
            hiddenSub?.cancel();
            hiddenSub = null;
            hidden = null;
            hiddenLoaded = false;
          }
          emit();
        }, onError: out.addError);
      },
      onCancel: () async {
        await mainSub?.cancel();
        await hiddenSub?.cancel();
      },
    );
    return out.stream;
  }

  @override
  Future<Result<void>> setPrivate(AppUser user, bool private) =>
      guard(() async {
        final main = _profiles.doc(user.uid);
        final hidden = _hidden(user.uid);
        final batch = _db.batch();
        if (private) {
          final data = (await main.get()).data() ?? const <String, dynamic>{};
          batch
            ..set(hidden, {
              for (final f in PlayerProfile.privateFields)
                if (data.containsKey(f)) f: data[f],
              'updatedAt': FieldValue.serverTimestamp(),
            })
            ..set(main, {
              ..._base(user, const []),
              'private': true,
              for (final f in PlayerProfile.privateFields)
                if (f != 'tags') f: FieldValue.delete(),
            }, SetOptions(merge: true));
        } else {
          final data = Map<String, dynamic>.of(
            (await hidden.get()).data() ?? const <String, dynamic>{},
          )..remove('updatedAt');
          final tags = [
            for (final t in (data.remove('tags') as List?) ?? const [])
              if (t is String) t,
          ];
          batch
            ..set(main, {
              ..._base(user, tags),
              ...data,
              'private': false,
            }, SetOptions(merge: true))
            ..delete(hidden);
        }
        await batch.commit();
      });

  @override
  Future<Result<void>> saveVisibility(AppUser user, ProfileVisibility v) =>
      guard(() async {
        final main = _profiles.doc(user.uid);
        final mainData = (await main.get()).data() ?? const <String, dynamic>{};
        final private = mainData['private'] == true;
        final data = private
            ? (await _hidden(user.uid).get()).data() ??
                  const <String, dynamic>{}
            : mainData;
        final current = PlayerProfile.fromMap(user.uid, data);
        // Not findable by a team they hide.
        final tags = v.teams
            ? current.searchTags
            : PlayerProfile(
                uid: user.uid,
                name: user.label,
                details: current.details,
              ).searchTags;
        final fields = <String, dynamic>{
          'visibility': v.toMap(),
          'tags': tags,
          if (!v.stats) 'stats': const <String, dynamic>{},
          if (!v.games) 'games': const <Object>[],
          if (!v.teams) 'teams': const <Object>[],
        };
        if (private) {
          await _hidden(user.uid).set({
            ...fields,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } else {
          await main.set({
            ..._base(user, tags),
            ...fields,
          }, SetOptions(merge: true));
        }
      });

  @override
  Future<Result<void>> saveDetails(
    AppUser user,
    ProfileDetails details, {
    required List<String> tags,
  }) => guard(() async {
    if (await _isPrivate(user.uid)) {
      final batch = _db.batch()
        ..set(
          _profiles.doc(user.uid),
          _base(user, const []),
          SetOptions(merge: true),
        )
        ..set(_hidden(user.uid), {
          ...details.toMap(),
          'tags': tags,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      return batch.commit();
    }
    return _profiles.doc(user.uid).set({
      ..._base(user, tags),
      ...details.toMap(),
    }, SetOptions(merge: true));
  });

  @override
  Future<Result<void>> publishSummary(
    AppUser user,
    ProfileSummary summary, {
    required List<String> tags,
  }) => guard(() async {
    final fields = {
      'teams': [for (final t in summary.teams) t.toMap()],
      // Replaced whole, so seasons that no longer have games go away.
      'stats': {
        for (final e in summary.seasons.entries) e.key: e.value.toMap(),
      },
      'games': [for (final g in summary.games) g.toMap()],
      'summaryUpdatedAt': FieldValue.serverTimestamp(),
    };
    if (await _isPrivate(user.uid)) {
      final batch = _db.batch()
        ..set(
          _profiles.doc(user.uid),
          _base(user, const []),
          SetOptions(mergeFields: _baseFields),
        )
        ..set(_hidden(user.uid), {
          ...fields,
          'tags': tags,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      return batch.commit();
    }
    return _profiles.doc(user.uid).set({
      ..._base(user, tags),
      ...fields,
    }, SetOptions(mergeFields: _summaryFields));
  });

  static const _baseFields = [
    'name',
    'keywords',
    'photoUrl',
    'tags',
    'updatedAt',
  ];

  static final _summaryFields = [
    ..._baseFields,
    'teams',
    'stats',
    'games',
    'summaryUpdatedAt',
  ];

  @override
  Future<Result<List<PlayerProfile>>> searchPlayers(String query) => guard(
    () async {
      final words = searchWords(Username.normalize(query));
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
