import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logging/logging.dart';

import '../../../domain/models/app_user.dart';
import '../../../domain/models/chat.dart';
import '../../../domain/models/invite_code.dart';
import '../../../domain/models/model_utils.dart';
import '../../../domain/models/roster_player.dart';
import '../../../domain/models/team.dart';
import '../../../domain/models/team_post.dart';
import '../../../domain/models/team_video.dart';
import '../../../utils/result.dart';
import '../../services/attachment_storage.dart';
import '../../services/firestore_utils.dart';
import '../../services/shared_streams.dart';
import '../chat/chat_repository_firebase.dart';
import 'team_repository.dart';

class InviteCodeNotFoundException implements Exception {
  const InviteCodeNotFoundException();

  @override
  String toString() => 'No team found for that invite code.';
}

class InviteCodeExpiredException implements Exception {
  const InviteCodeExpiredException();

  @override
  String toString() => 'That invite has expired. Ask for a new code or link.';
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
    SharedStreams? sharedStreams,
  }) : _files = attachments,
       _db = firestore ?? FirebaseFirestore.instance,
       _random = random ?? Random.secure(),
       _shared = sharedStreams ?? SharedStreams.instance;

  /// Chat attachments and post photos go with the team.
  final AttachmentStorage _files;
  final FirebaseFirestore _db;
  final Random _random;

  /// One listener per query, shared by every screen (see [SharedStreams]).
  final SharedStreams _shared;

  static final _log = Logger('TeamRepository');

  /// Teams whose legacy roster status is being moved, so it runs once.
  final _migrating = <String>{};

  // No 0/O/1/I to keep codes easy to read aloud.
  static const _codeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static const _codeLength = 6;
  // Link tokens are only ever tapped, never typed, so they're long.
  static const _tokenLength = 20;

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

  String _newCode(int length) => String.fromCharCodes(
    List.generate(
      length,
      (_) => _codeAlphabet.codeUnitAt(_random.nextInt(_codeAlphabet.length)),
    ),
  );

  static String normalizeCode(String code) =>
      code.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  @override
  Stream<List<Team>> watchMyTeams(String uid) => _shared.get(
    'myTeams/$uid',
    () =>
        countedSnapshots(
          _teams.where('memberIds', arrayContains: uid),
          'myTeams',
        ).map(
          (snap) =>
              snap.docs
                  .map((d) => Team.fromMap(d.id, plainData(d.data())))
                  .toList()
                ..sort(
                  (a, b) =>
                      a.name.toLowerCase().compareTo(b.name.toLowerCase()),
                ),
        ),
  );

  @override
  Stream<Team?> watchTeam(String teamId) => _shared.get(
    'team/$teamId',
    () => countedDocSnapshots(
      _teams.doc(teamId),
      'team',
    ).map((d) => d.exists ? Team.fromMap(d.id, plainData(d.data())) : null),
  );

  CollectionReference<Map<String, dynamic>> _requests(String teamId) =>
      _teams.doc(teamId).collection('joinRequests');

  CollectionReference<Map<String, dynamic>> _invites(String uid) =>
      _db.collection('users').doc(uid).collection('teamInvites');

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
      guard(() async {
        // No invite code: admins mint short-lived ones when they share.
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

  @override
  Future<Result<String>> resolveInviteCode(String inviteCode) =>
      guard(() => _teamIdForCode(normalizeCode(inviteCode)));

  Future<String> _teamIdForCode(String code) async {
    if (code.isEmpty) throw const InviteCodeNotFoundException();
    final data = (await _codes.doc(code).get()).data();
    final teamId = data?['teamId'] as String?;
    if (teamId == null) throw const InviteCodeNotFoundException();
    // The rules check createdAt + ttl on the server's clock; expiresAt is
    // the minter's estimate, close enough to explain a failure up front.
    // Codes from before rotation have neither and no longer work.
    final expiresAt = data?['expiresAt'];
    if (expiresAt is! Timestamp ||
        !DateTime.now().isBefore(expiresAt.toDate())) {
      throw const InviteCodeExpiredException();
    }
    return teamId;
  }

  @override
  Future<Result<String>> joinTeam(String inviteCode, AppUser user) =>
      guard(() async {
        final code = normalizeCode(inviteCode);
        final teamId = await _teamIdForCode(code);
        // joins/{uid} proves to the security rules that the caller knows
        // a live invite code, without putting it on the team.
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
  Future<Result<void>> inviteToTeam(Team team, String uid, AppUser from) =>
      guard(
        () => _invites(uid).doc(team.id).set({
          'teamName': team.name,
          'kind': team.kind.name,
          'invitedBy': from.uid,
          'invitedByName': from.label,
          'createdAt': FieldValue.serverTimestamp(),
        }),
      );

  @override
  Stream<List<TeamInvite>> watchMyInvites(String uid) => _invites(uid)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map(
        (snap) => [
          for (final d in snap.docs)
            TeamInvite.fromMap(d.id, plainData(d.data())),
        ],
      );

  // The invite is the proof the rules check, so it's deleted in the same
  // batch; so is any request to join the user had pending.
  @override
  Future<Result<void>> acceptInvite(TeamInvite invite, AppUser user) => guard(
    () =>
        (_db.batch()
              ..update(_teams.doc(invite.teamId), _newMember(user))
              ..delete(_invites(user.uid).doc(invite.teamId))
              ..delete(_requests(invite.teamId).doc(user.uid)))
            .commit(),
  );

  @override
  Future<Result<void>> declineInvite(String uid, String teamId) =>
      guard(() => _invites(uid).doc(teamId).delete());

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
  Stream<TeamListing?> watchListing(String teamId) => _shared.get(
    'listing/$teamId',
    () => countedDocSnapshots(_directory.doc(teamId), 'teamListing').map(
      (d) => d.exists ? TeamListing.fromMap(d.id, plainData(d.data())) : null,
    ),
  );

  @override
  Future<Result<void>> publishListing(Team team) =>
      guard(() => _directory.doc(team.id).set(TeamListing.of(team).toMap()));

  @override
  Future<Result<InviteCode>> createInviteCode(String teamId, String uid) =>
      guard(() => _mint(teamId, uid, InviteCode.codeLifetime, _codeLength));

  @override
  Future<Result<InviteCode>> createInviteLink(
    String teamId,
    String uid,
    InviteLinkExpiry expiry,
  ) => guard(() => _mint(teamId, uid, expiry.duration, _tokenLength));

  Future<InviteCode> _mint(
    String teamId,
    String uid,
    Duration ttl,
    int length,
  ) async {
    // Codes can't be overwritten, so a collision with an existing one
    // surfaces as permission-denied: try a fresh code.
    for (var attempt = 0; ; attempt++) {
      final code = _newCode(length);
      final expiresAt = DateTime.now().add(ttl);
      try {
        await _codes.doc(code).set({
          'teamId': teamId,
          'createdBy': uid,
          'createdAt': FieldValue.serverTimestamp(),
          'ttl': ttl.inSeconds,
          'expiresAt': Timestamp.fromDate(expiresAt),
        });
        return InviteCode(code: code, teamId: teamId, expiresAt: expiresAt);
      } on FirebaseException catch (e) {
        if (e.code != 'permission-denied' || attempt >= 2) rethrow;
      }
    }
  }

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
    // Tells the notification functions not to announce the cascade below
    // (every event "cancelled", and so on).
    await ref.update({'deletingAt': FieldValue.serverTimestamp()});
    try {
      // Firestore doesn't cascade deletes; clear subcollections first.
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
      // The tournaments' public listings, so Explore stops showing them.
      // Queried rather than named: rules refuse deleting one that doesn't
      // exist, and older tournaments may have none.
      final listings = await _db
          .collection('tournamentDirectory')
          .where('groupId', isEqualTo: team.id)
          .get();
      await deleteDocs(_db, [for (final d in listings.docs) d.reference]);
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
      ]) {
        final docs = await ref.collection(sub).get();
        await deleteDocs(_db, [for (final d in docs.docs) d.reference]);
      }
      // Older teams kept a permanent invite code in private/invite. Rules
      // don't let the owner list private, so delete it by name; deleting a
      // missing doc is fine. Invite codes expire on their own.
      await _invite(team.id).delete();
    } on Exception {
      // Half-deleted, but still a team: let it notify again.
      await ref.update({'deletingAt': FieldValue.delete()});
      rethrow;
    }
    await (_db.batch()
          ..delete(_directory.doc(team.id))
          ..delete(ref))
        .commit();
  });

  @override
  Stream<List<RosterPlayer>> watchRoster(
    String teamId, {
    bool withStatus = false,
  }) {
    if (!withStatus) {
      return _shared.get(
        'roster/$teamId',
        () => countedSnapshots(_roster(teamId), 'roster').map(
          (snap) => _sorted([
            for (final d in snap.docs)
              RosterPlayer.fromMap(d.id, plainData(d.data())),
          ]),
        ),
      );
    }
    final roster = countedSnapshots(_roster(teamId), 'roster');
    final status = countedSnapshots(_status(teamId), 'rosterStatus');
    return _combineLatest(roster, status, (r, s) {
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
  Future<Result<void>> linkPlayer(
    String teamId,
    String playerId,
    String? uid,
  ) => guard(() => _roster(teamId).doc(playerId).update({'userId': uid}));

  @override
  Future<Result<void>> deletePlayer(String teamId, String playerId) => guard(
    () =>
        (_db.batch()
              ..delete(_roster(teamId).doc(playerId))
              ..delete(_status(teamId).doc(playerId)))
            .commit(),
  );
}
