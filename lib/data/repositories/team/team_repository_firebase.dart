import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logging/logging.dart';

import '../../../domain/models/app_user.dart';
import '../../../domain/models/chat.dart';
import '../../../domain/models/model_utils.dart';
import '../../../domain/models/roster_player.dart';
import '../../../domain/models/team.dart';
import '../../../domain/models/team_post.dart';
import '../../../domain/models/team_video.dart';
import '../../../utils/result.dart';
import '../../services/attachment_storage.dart';
import '../../services/firestore_utils.dart';
import '../chat/chat_repository_firebase.dart';
import 'team_repository.dart';

class InviteCodeNotFoundException implements Exception {
  const InviteCodeNotFoundException();

  @override
  String toString() => 'No team found for that invite code.';
}

/// Team data lives in `teams/{teamId}` with `roster` and `plays`
/// subcollections. Each roster entry's admin-only status (paid, on USA
/// Ultimate) is in `rosterStatus/{playerId}`, which players can't read.
/// The invite code is in `private/invite` (admins only) and
/// `inviteCodes/{code}` maps it back to the team; joiners prove they know
/// it via `joins/{uid}`. Chat rooms are in `chats` (see
/// [ChatRepositoryFirebase]). `teamDirectory/{teamId}` is the public
/// listing anyone signed in can search; it mirrors the team's details.
/// All writes are validated by `firestore.rules`.
class TeamRepositoryFirebase implements TeamRepository {
  TeamRepositoryFirebase({
    required AttachmentStorage attachments,
    FirebaseFirestore? firestore,
    Random? random,
  }) : _files = attachments,
       _db = firestore ?? FirebaseFirestore.instance,
       _random = random ?? Random.secure();

  /// Chat attachments and post photos go with the team.
  final AttachmentStorage _files;
  final FirebaseFirestore _db;
  final Random _random;

  static final _log = Logger('TeamRepository');

  /// Teams whose legacy roster status is being moved, so it runs once.
  final _migrating = <String>{};

  // No 0/O/1/I to keep codes easy to read aloud.
  static const _codeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static const _codeLength = 6;

  CollectionReference<Map<String, dynamic>> get _teams =>
      _db.collection('teams');

  CollectionReference<Map<String, dynamic>> get _directory =>
      _db.collection('teamDirectory');

  static const _searchLimit = 25;

  CollectionReference<Map<String, dynamic>> get _codes =>
      _db.collection('inviteCodes');

  CollectionReference<Map<String, dynamic>> _roster(String teamId) =>
      _teams.doc(teamId).collection('roster');

  CollectionReference<Map<String, dynamic>> _status(String teamId) =>
      _teams.doc(teamId).collection('rosterStatus');

  DocumentReference<Map<String, dynamic>> _invite(String teamId) =>
      _teams.doc(teamId).collection('private').doc('invite');

  DocumentReference<Map<String, dynamic>> _join(String teamId, String uid) =>
      _teams.doc(teamId).collection('joins').doc(uid);

  /// Older roster entries kept paid/onUsau on the entry itself.
  static const _legacyStatusKeys = ['onUsau', 'paid'];

  String _newCode() => String.fromCharCodes(
    List.generate(
      _codeLength,
      (_) => _codeAlphabet.codeUnitAt(_random.nextInt(_codeAlphabet.length)),
    ),
  );

  static String normalizeCode(String code) =>
      code.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  @override
  Stream<List<Team>> watchMyTeams(String uid) => _teams
      .where('memberIds', arrayContains: uid)
      .snapshots()
      .map(
        (snap) =>
            snap.docs
                .map((d) => Team.fromMap(d.id, plainData(d.data())))
                .toList()
              ..sort(
                (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
              ),
      );

  @override
  Stream<Team?> watchTeam(String teamId) => _teams
      .doc(teamId)
      .snapshots()
      .map((d) => d.exists ? Team.fromMap(d.id, plainData(d.data())) : null);

  CollectionReference<Map<String, dynamic>> _requests(String teamId) =>
      _teams.doc(teamId).collection('joinRequests');

  Map<String, dynamic> _teamDoc(NewTeam team, AppUser owner) => {
    ...team.toMap(),
    'ownerId': owner.uid,
    'members': {owner.uid: TeamRole.owner.name},
    'memberIds': [owner.uid],
    'memberNames': {owner.uid: owner.label},
    'createdAt': FieldValue.serverTimestamp(),
  };

  @override
  Future<Result<String>> createTeam(NewTeam team, AppUser owner) =>
      team.kind == TeamKind.community
      ? _createGroup(team, owner)
      : _createTeam(team, owner);

  /// Groups are joined from the directory, so they get no invite code.
  Future<Result<String>> _createGroup(NewTeam team, AppUser owner) =>
      guard(() async {
        final ref = _teams.doc();
        await (_db.batch()
              ..set(ref, _teamDoc(team, owner))
              ..set(_directory.doc(ref.id), team.listing(ref.id).toMap())
              ..set(
                chatRooms(_db, ref.id).doc(ChatRoom.generalId),
                newRoomData(ChatRoom.general(), owner.uid),
              ))
            .commit();
        return ref.id;
      });

  Future<Result<String>> _createTeam(NewTeam team, AppUser owner) =>
      guard(() async {
        // Retry on the (unlikely) event of an invite code collision, which
        // surfaces as permission-denied because codes can't be overwritten.
        for (var attempt = 0; ; attempt++) {
          final ref = _teams.doc();
          final code = _newCode();
          final batch = _db.batch()
            ..set(ref, _teamDoc(team, owner))
            ..set(_directory.doc(ref.id), team.listing(ref.id).toMap())
            ..set(_invite(ref.id), {'code': code})
            ..set(_codes.doc(code), {'teamId': ref.id})
            ..set(
              chatRooms(_db, ref.id).doc(ChatRoom.generalId),
              newRoomData(ChatRoom.general(), owner.uid),
            );
          try {
            await batch.commit();
            return ref.id;
          } on FirebaseException catch (e) {
            if (e.code != 'permission-denied' || attempt >= 2) rethrow;
          }
        }
      });

  @override
  Future<Result<String>> joinTeam(String inviteCode, AppUser user) =>
      guard(() async {
        final code = normalizeCode(inviteCode);
        if (code.isEmpty) throw const InviteCodeNotFoundException();
        final codeDoc = await _codes.doc(code).get();
        final teamId = codeDoc.data()?['teamId'] as String?;
        if (teamId == null) throw const InviteCodeNotFoundException();
        // joins/{uid} proves to the security rules that the caller knows
        // the team's current invite code, without putting it on the team.
        await (_db.batch()
              ..set(_join(teamId, user.uid), {'code': code})
              ..update(_teams.doc(teamId), _newMember(user)))
            .commit();
        return teamId;
      });

  Map<String, dynamic> _newMember(AppUser user) => {
    'members.${user.uid}': TeamRole.player.name,
    'memberNames.${user.uid}': user.label,
    'memberIds': FieldValue.arrayUnion([user.uid]),
  };

  @override
  Future<Result<void>> joinGroup(String teamId, AppUser user) =>
      guard(() => _teams.doc(teamId).update(_newMember(user)));

  @override
  Future<Result<void>> requestToJoin(String teamId, AppUser user) => guard(
    () => _requests(teamId).doc(user.uid).set({
      'name': user.label,
      'createdAt': FieldValue.serverTimestamp(),
    }),
  );

  @override
  Future<Result<void>> cancelJoinRequest(String teamId, String uid) =>
      guard(() => _requests(teamId).doc(uid).delete());

  @override
  Stream<bool> watchMyJoinRequest(String teamId, String uid) =>
      _requests(teamId).doc(uid).snapshots().map((d) => d.exists);

  @override
  Stream<List<GroupJoinRequest>> watchJoinRequests(String teamId) =>
      _requests(teamId)
          .orderBy('createdAt')
          .snapshots()
          .map(
            (snap) => [
              for (final d in snap.docs)
                GroupJoinRequest.fromMap(d.id, plainData(d.data())),
            ],
          );

  @override
  Future<Result<void>> approveJoinRequest(
    String teamId,
    GroupJoinRequest request,
  ) => guard(
    () =>
        (_db.batch()
              ..update(_teams.doc(teamId), {
                'members.${request.uid}': TeamRole.player.name,
                'memberNames.${request.uid}': request.name.isEmpty
                    ? 'Member'
                    : request.name,
                'memberIds': FieldValue.arrayUnion([request.uid]),
              })
              ..delete(_requests(teamId).doc(request.uid)))
            .commit(),
  );

  @override
  Future<Result<void>> declineJoinRequest(String teamId, String uid) =>
      guard(() => _requests(teamId).doc(uid).delete());

  @override
  Future<Result<void>> updateTeam(Team team) => guard(
    () =>
        (_db.batch()
              ..update(_teams.doc(team.id), team.toEditableMap())
              ..set(_directory.doc(team.id), TeamListing.of(team).toMap()))
            .commit(),
  );

  @override
  Future<Result<List<TeamListing>>> searchTeams(String query) => guard(
    () async {
      final words = searchWords(query);
      if (words.isEmpty) return const [];
      // Match the longest word in Firestore, then the rest here.
      final key = (words.toList()..sort((a, b) => b.length - a.length)).first;
      final snap = await _directory
          .where(
            'keywords',
            arrayContains: key.length > 20 ? key.substring(0, 20) : key,
          )
          .limit(_searchLimit * 2)
          .get();
      return [
          for (final d in snap.docs)
            TeamListing.fromMap(d.id, plainData(d.data())),
        ].where((t) => t.matches(query)).take(_searchLimit).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    },
  );

  @override
  Stream<TeamListing?> watchListing(String teamId) => _directory
      .doc(teamId)
      .snapshots()
      .map(
        (d) => d.exists ? TeamListing.fromMap(d.id, plainData(d.data())) : null,
      );

  @override
  Future<Result<void>> publishListing(Team team) =>
      guard(() => _directory.doc(team.id).set(TeamListing.of(team).toMap()));

  @override
  Stream<String?> watchInviteCode(String teamId) =>
      _invite(teamId).snapshots().asyncMap(
        (d) async =>
            d.data()?['code'] as String? ?? await _moveLegacyCode(teamId),
      );

  /// Older teams kept the code on the team doc, readable by every member.
  /// Moves it to private/invite and clears it (and the old join proof).
  /// Runs when an admin first watches the code.
  Future<String?> _moveLegacyCode(String teamId) async {
    final team = (await _teams.doc(teamId).get()).data() ?? const {};
    final code = team['inviteCode'] as String?;
    if (code == null) return null;
    try {
      await (_db.batch()
            ..set(_invite(teamId), {'code': code})
            ..update(_teams.doc(teamId), {
              'inviteCode': FieldValue.delete(),
              'joinCode': FieldValue.delete(),
            }))
          .commit();
    } on FirebaseException catch (e) {
      _log.warning('Invite code move failed', e);
    }
    return code;
  }

  /// The current code, from private/invite or an older team doc.
  Future<String?> _currentCode(String teamId) async {
    final invite = (await _invite(teamId).get()).data();
    if (invite != null) return invite['code'] as String?;
    return (await _teams.doc(teamId).get()).data()?['inviteCode'] as String?;
  }

  @override
  Future<Result<void>> regenerateInviteCode(String teamId) => guard(() async {
    final old = await _currentCode(teamId);
    final legacy = (await _teams.doc(teamId).get()).data()?.containsKey(
      'inviteCode',
    );
    final code = _newCode();
    final batch = _db.batch()
      ..set(_invite(teamId), {'code': code})
      ..set(_codes.doc(code), {'teamId': teamId});
    if (old != null) batch.delete(_codes.doc(old));
    if (legacy ?? false) {
      batch.update(_teams.doc(teamId), {
        'inviteCode': FieldValue.delete(),
        'joinCode': FieldValue.delete(),
      });
    }
    await batch.commit();
  });

  @override
  Future<Result<void>> setMemberRole(
    String teamId,
    String uid,
    TeamRole role,
  ) => guard(() => _teams.doc(teamId).update({'members.$uid': role.name}));

  @override
  Future<Result<void>> setStatKeeper(
    String teamId,
    String uid, {
    required bool on,
  }) => guard(
    () => _teams.doc(teamId).update({
      'statKeepers': on
          ? FieldValue.arrayUnion([uid])
          : FieldValue.arrayRemove([uid]),
    }),
  );

  @override
  Future<Result<void>> transferOwnership(
    String teamId, {
    required String ownerUid,
    required String newOwnerUid,
  }) => guard(
    () => _teams.doc(teamId).update({
      'ownerId': newOwnerUid,
      'members.$newOwnerUid': TeamRole.owner.name,
      'members.$ownerUid': TeamRole.player.name,
    }),
  );

  @override
  Future<Result<void>> removeMember(String teamId, String uid) => guard(
    () => _teams.doc(teamId).update({
      'members.$uid': FieldValue.delete(),
      'memberNames.$uid': FieldValue.delete(),
      'memberIds': FieldValue.arrayRemove([uid]),
      'statKeepers': FieldValue.arrayRemove([uid]),
    }),
  );

  @override
  Future<Result<void>> deleteTeam(Team team) => guard(() async {
    final ref = _teams.doc(team.id);
    final code = await _currentCode(team.id);
    // Tells the notification functions not to announce the cascade below
    // (every event "cancelled", and so on).
    await ref.update({'deletingAt': FieldValue.serverTimestamp()});
    try {
      // Firestore doesn't cascade deletes; clear subcollections first.
      // private (the invite code) goes last: code deletes check the owner.
      for (final room in (await chatRooms(_db, team.id).get()).docs) {
        await deleteChatRoom(_db, _files, room.reference);
      }
      for (final meeting in (await ref.collection('meetings').get()).docs) {
        final m = meeting.reference;
        final messages = await m.collection('messages').get();
        final requests = await m.collection('requests').get();
        await deleteDocs(_db, [
          for (final d in messages.docs) d.reference,
          for (final d in requests.docs) d.reference,
          m,
        ]);
      }
      final tournaments = await ref.collection('groupTournaments').get();
      for (final t in tournaments.docs) {
        final games = await t.reference.collection('games').get();
        await deleteDocs(_db, [
          for (final d in games.docs) d.reference,
          t.reference,
        ]);
      }
      // Uploaded videos go before the videos that list them.
      for (final video in (await ref.collection('videos').get()).docs) {
        final path = TeamVideo.fromMap(
          video.id,
          plainData(video.data()),
        ).file?.path;
        if (path != null) await _files.delete([path]);
      }
      // Post photos go before their posts, which list them.
      for (final post in (await ref.collection('posts').get()).docs) {
        await _files.delete(
          TeamPost.fromMap(
            post.id,
            plainData(post.data()),
          ).images.map((i) => i.path),
        );
      }
      for (final sub in [
        'roster',
        'rosterStatus',
        'joins',
        'plays',
        'events',
        'publicEvents',
        'posts',
        'videos',
        'videoFolders',
        'statsTournaments',
        'statsGames',
        'joinRequests',
        'private',
      ]) {
        final docs = await ref.collection(sub).get();
        final batch = _db.batch();
        for (final d in docs.docs) {
          batch.delete(d.reference);
        }
        await batch.commit();
      }
    } on Exception {
      // Half-deleted, but still a team: let it notify again.
      await ref.update({'deletingAt': FieldValue.delete()});
      rethrow;
    }
    final batch = _db.batch();
    if (code != null) batch.delete(_codes.doc(code));
    batch
      ..delete(_directory.doc(team.id))
      ..delete(ref);
    await batch.commit();
  });

  @override
  Stream<List<RosterPlayer>> watchRoster(
    String teamId, {
    bool withStatus = false,
  }) {
    final roster = _roster(teamId).snapshots();
    if (!withStatus) {
      return roster.map(
        (snap) => _sorted([
          for (final d in snap.docs)
            RosterPlayer.fromMap(d.id, plainData(d.data())),
        ]),
      );
    }
    return _combineLatest(roster, _status(teamId).snapshots(), (r, s) {
      final status = {for (final d in s.docs) d.id: plainData(d.data())};
      _moveLegacyStatus(teamId, r.docs, status.keys.toSet());
      return _sorted([
        for (final d in r.docs)
          RosterPlayer.fromMap(
            d.id,
            plainData(d.data()),
            status: status[d.id] ?? _legacyStatus(d.data()),
          ),
      ]);
    });
  }

  static List<RosterPlayer> _sorted(List<RosterPlayer> players) =>
      players..sort((a, b) {
        final byNumber = (a.number ?? 1000).compareTo(b.number ?? 1000);
        return byNumber != 0 ? byNumber : a.name.compareTo(b.name);
      });

  static Map<String, dynamic>? _legacyStatus(Map<String, dynamic> data) =>
      _legacyStatusKeys.any(data.containsKey)
      ? {for (final k in _legacyStatusKeys) k: data[k]}
      : null;

  /// Moves status still stored on roster entries (readable by every member)
  /// into rosterStatus, then strips it from the entry. Runs when an admin
  /// views the roster, since only admins may write either collection.
  void _moveLegacyStatus(
    String teamId,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> roster,
    Set<String> hasStatus,
  ) {
    final legacy = [
      for (final d in roster)
        if (_legacyStatus(d.data()) != null) d,
    ];
    if (legacy.isEmpty || !_migrating.add(teamId)) return;
    final batch = _db.batch();
    for (final d in legacy) {
      if (!hasStatus.contains(d.id)) {
        batch.set(_status(teamId).doc(d.id), {
          'onUsau': d.data()['onUsau'] as bool?,
          'paid': d.data()['paid'] as bool? ?? false,
        });
      }
      batch.update(d.reference, {
        for (final k in _legacyStatusKeys) k: FieldValue.delete(),
      });
    }
    batch
        .commit()
        .catchError((Object e) => _log.warning('Roster status move failed', e))
        .whenComplete(() => _migrating.remove(teamId));
  }

  /// Emits [combine] of the latest value of each stream once both have one.
  static Stream<T> _combineLatest<A, B, T>(
    Stream<A> a,
    Stream<B> b,
    T Function(A, B) combine,
  ) {
    late final StreamController<T> controller;
    StreamSubscription<A>? subA;
    StreamSubscription<B>? subB;
    late A lastA;
    late B lastB;
    var hasA = false;
    var hasB = false;
    void emit() {
      if (hasA && hasB) controller.add(combine(lastA, lastB));
    }

    controller = StreamController<T>(
      onListen: () {
        subA = a.listen((v) {
          lastA = v;
          hasA = true;
          emit();
        }, onError: controller.addError);
        subB = b.listen((v) {
          lastB = v;
          hasB = true;
          emit();
        }, onError: controller.addError);
      },
      onCancel: () => Future.wait([
        if (subA != null) subA!.cancel(),
        if (subB != null) subB!.cancel(),
      ]),
    );
    return controller.stream;
  }

  @override
  Future<Result<void>> linkUsauTeam(
    String teamId, {
    String? url,
    String? name,
  }) => guard(
    () => _teams.doc(teamId).update({
      'usauUrl': url,
      'usauName': url == null ? null : name,
      if (url == null) 'usauSyncedAt': null,
    }),
  );

  @override
  Future<Result<void>> applyRosterSync(
    String teamId,
    List<RosterPlayer> players,
  ) => guard(() async {
    final col = _roster(teamId);
    // Firestore batches cap at 500 writes; rosters are far smaller.
    final batch = _db.batch()
      ..update(_teams.doc(teamId), {
        'usauSyncedAt': FieldValue.serverTimestamp(),
      });
    for (final p in players) {
      final ref = p.id.isEmpty ? col.doc() : col.doc(p.id);
      batch
        ..set(ref, p.toMap())
        ..set(_status(teamId).doc(ref.id), p.toStatusMap());
    }
    await batch.commit();
  });

  @override
  Future<Result<void>> savePlayer(String teamId, RosterPlayer player) =>
      guard(() async {
        final col = _roster(teamId);
        final ref = player.id.isEmpty ? col.doc() : col.doc(player.id);
        await (_db.batch()
              ..set(ref, player.toMap())
              ..set(_status(teamId).doc(ref.id), player.toStatusMap()))
            .commit();
      });

  @override
  Future<Result<void>> deletePlayer(String teamId, String playerId) => guard(
    () =>
        (_db.batch()
              ..delete(_roster(teamId).doc(playerId))
              ..delete(_status(teamId).doc(playerId)))
            .commit(),
  );
}
