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
import '../../../domain/models/team_name.dart';
import '../../../domain/models/team_post.dart';
import '../../../domain/models/team_video.dart';
import '../../../utils/result.dart';
import '../../services/api_client.dart';
import '../../services/api_search.dart';
import '../../services/attachment_storage.dart';
import '../../services/feature_flags.dart';
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
/// Writes are validated by `firestore.rules`, except creating a team,
/// which goes through the Stall 10 API ([ApiClient], `POST /v1/teams`) when
/// the build has one and the `use_api_teams` flag is on, and membership and
/// management (joining, invites, roles, details, invite codes and
/// communities), which go through it when `use_api_membership` is on. The
/// API checks what the rules did; the direct writes stay as the fallback.
class TeamRepositoryFirebase implements TeamRepository {
  TeamRepositoryFirebase({
    required AttachmentStorage attachments,
    FirebaseFirestore? firestore,
    Random? random,
    SharedStreams? sharedStreams,
    ApiSearch? search,
    ApiClient? api,
    FeatureFlags? flags,
  }) : _api = api,
       _flags = flags,
       _files = attachments,
       _db = firestore ?? FirebaseFirestore.instance,
       _random = random ?? Random.secure(),
       _shared = sharedStreams ?? SharedStreams.instance,
       _search = search;

  /// Searches through the rate-limited Cloud Function when it's turned on.
  final ApiSearch? _search;

  /// The Stall 10 API, when this build has one ([ApiClient.fromEnvironment]).
  final ApiClient? _api;
  final FeatureFlags? _flags;

  /// The API to create teams through, or null to write Firestore directly.
  ApiClient? get _teamsApi => (_flags?.useApiTeams ?? true) ? _api : null;

  /// The API for membership and management, or null to write Firestore.
  ApiClient? get _membersApi =>
      (_flags?.useApiMembership ?? true) ? _api : null;

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

  /// Older roster entries kept paid (and the retired USA Ultimate onUsau
  /// flag) on the entry itself.
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

  @override
  Future<Result<String>> createTeam(NewTeam team, AppUser owner) =>
      guard(() async {
        // The API checks the name and writes the same documents
        // (newTeamDocs), as the signed-in user, whoever [owner] says.
        if (_teamsApi case final api? when team.orgId == null) {
          final res = await api.post('/v1/teams', team.toRequest());
          return res['id']! as String;
        }
        await _ensureNameFree(team.name, team.kind, team.division);
        final ref = _teams.doc();
        await _newTeamBatch(ref, team, owner).commit();
        return ref.id;
      });

  /// Throws [TeamNameTakenException] if another of [kind] (in [division],
  /// for teams) already has [name] or one that reads the same (see
  /// [teamNameKey]). Checked against the public directory, which every
  /// team, group and community is listed in.
  Future<void> _ensureNameFree(
    String name,
    TeamKind kind,
    Division division, {
    String? excludeId,
  }) async {
    final probe = teamNameProbe(name);
    if (probe.isEmpty) return;
    final snap = await _directory
        .where('keywords', arrayContainsAny: probe)
        .limit(200)
        .get();
    for (final d in snap.docs) {
      final listing = TeamListing.fromMap(d.id, plainData(d.data()));
      if (teamNameClashes(
        listing,
        name: name,
        kind: kind,
        division: division,
        excludeId: excludeId,
      )) {
        throw TeamNameTakenException(listing.name, kind, division);
      }
    }
  }

  @override
  Future<Result<String>> createTeamInCommunity(
    NewTeam team,
    AppUser owner,
    Team org,
    Set<String> roles,
  ) => guard(() async {
    if (_membersApi case final api?) {
      final res = await api.post('/v1/teams/${org.id}/linked-teams', {
        'name': team.name,
        'division': team.division.name,
        'level': team.level.name,
        'city': team.city,
        'roles': roles.toList()..sort(),
      });
      return res['id']! as String;
    }
    await _ensureNameFree(team.name, team.kind, team.division);
    final ref = _teams.doc();
    final linked = LinkedTeam(
      id: ref.id,
      name: team.name,
      division: team.division,
      roles: roles,
    );
    await (_newTeamBatch(ref, team.inCommunity(org), owner)..update(
          _teams.doc(org.id),
          {'linkedTeams.${ref.id}': linked.toMap()},
        ))
        .commit();
    return ref.id;
  });

  @override
  Future<Result<void>> requestCommunityLink(
    Team team,
    TeamListing org,
    AppUser by,
  ) => guard(
    () async => switch (_membersApi) {
      final api? => api.put('/v1/teams/${team.id}/community', {
        'orgId': org.id,
      }),
      null =>
        (_db.batch()
              ..update(_teams.doc(team.id), {
                'orgId': org.id,
                'orgName': org.name,
              })
              ..set(_linkRequests(org.id).doc(team.id), {
                'teamName': team.name,
                'division': team.division.name,
                'requestedBy': by.uid,
                'requestedByName': by.label,
                'createdAt': FieldValue.serverTimestamp(),
              }))
            .commit(),
    },
  );

  @override
  Future<Result<void>> leaveCommunity(Team team) => guard(() async {
    if (_membersApi case final api?) {
      await api.delete('/v1/teams/${team.id}/community');
      return;
    }
    final orgId = team.orgId;
    final batch = _db.batch()
      ..update(_teams.doc(team.id), {'orgId': null, 'orgName': ''});
    if (orgId != null && !team.orgLinked) {
      batch.delete(_linkRequests(orgId).doc(team.id));
    }
    await batch.commit();
  });

  @override
  Stream<bool> watchLinkRequested(String orgId, String teamId) =>
      _linkRequests(orgId).doc(teamId).snapshots().map((d) => d.exists);

  @override
  Stream<List<TeamLinkRequest>> watchLinkRequests(String orgId) =>
      _linkRequests(orgId)
          .orderBy('createdAt')
          .snapshots()
          .map(
            (snap) => [
              for (final d in snap.docs)
                TeamLinkRequest.fromMap(d.id, plainData(d.data())),
            ],
          );

  @override
  Future<Result<void>> acceptLinkRequest(
    Team org,
    TeamLinkRequest request,
    Set<String> roles,
  ) => guard(
    () async => switch (_membersApi) {
      final api? => api.post(
        '/v1/teams/${org.id}/link-requests/${request.teamId}/accept',
        {'roles': roles.toList()..sort()},
      ),
      null =>
        (_db.batch()
              ..update(_teams.doc(org.id), {
                'linkedTeams.${request.teamId}': LinkedTeam(
                  id: request.teamId,
                  name: request.teamName,
                  division: request.division,
                  roles: roles,
                ).toMap(),
              })
              ..delete(_linkRequests(org.id).doc(request.teamId)))
            .commit(),
    },
  );

  @override
  Future<Result<void>> declineLinkRequest(String orgId, String teamId) => guard(
    () async => switch (_membersApi) {
      final api? => api.delete('/v1/teams/$orgId/link-requests/$teamId'),
      null => _linkRequests(orgId).doc(teamId).delete(),
    },
  );

  @override
  Future<Result<void>> saveLinkedTeam(String orgId, LinkedTeam team) => guard(
    () async => switch (_membersApi) {
      final api? => api.put('/v1/teams/$orgId/linked-teams/${team.id}', {
        'roles': team.roles.toList()..sort(),
      }),
      null => _teams.doc(orgId).update({
        'linkedTeams.${team.id}': team.toMap(),
      }),
    },
  );

  @override
  Future<Result<void>> unlinkTeam(String orgId, String teamId) => guard(
    () async => switch (_membersApi) {
      final api? => api.delete('/v1/teams/$orgId/linked-teams/$teamId'),
      null => _teams.doc(orgId).update({
        'linkedTeams.$teamId': FieldValue.delete(),
      }),
    },
  );

  CollectionReference<Map<String, dynamic>> _linkRequests(String orgId) =>
      _teams.doc(orgId).collection('linkRequests');

  /// A new team's doc, directory listing and starting chat rooms. No
  /// invite code: admins mint short-lived ones when they share.
  WriteBatch _newTeamBatch(
    DocumentReference<Map<String, dynamic>> ref,
    NewTeam team,
    AppUser owner,
  ) {
    final batch = _db.batch();
    final docs = newTeamDocs(
      ref.id,
      team,
      owner,
      createdAt: FieldValue.serverTimestamp(),
    );
    for (final MapEntry(:key, :value) in docs.entries) {
      batch.set(_db.doc(key), value);
    }
    return batch;
  }

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
        // The API checks the code is live and adds the signed-in user.
        if (_membersApi case final api?) {
          final res = await api.post('/v1/teams/join', {'code': inviteCode});
          return res['teamId']! as String;
        }
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
  Future<Result<void>> joinGroup(String teamId, AppUser user) => guard(
    () async => switch (_membersApi) {
      final api? => api.post('/v1/teams/$teamId/members', {}),
      null => _teams.doc(teamId).update(_newMember(user)),
    },
  );

  @override
  Future<Result<void>> requestToJoin(String teamId, AppUser user) => guard(
    () async => switch (_membersApi) {
      final api? => api.post('/v1/teams/$teamId/join-requests', {}),
      null => _requests(teamId).doc(user.uid).set({
        'name': user.label,
        'createdAt': FieldValue.serverTimestamp(),
      }),
    },
  );

  @override
  Future<Result<void>> cancelJoinRequest(String teamId, String uid) =>
      _deleteRequest(teamId, uid);

  Future<Result<void>> _deleteRequest(String teamId, String uid) => guard(
    () async => switch (_membersApi) {
      final api? => api.delete('/v1/teams/$teamId/join-requests/$uid'),
      null => _requests(teamId).doc(uid).delete(),
    },
  );

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
    () async => switch (_membersApi) {
      final api? => api.post(
        '/v1/teams/$teamId/join-requests/${request.uid}/approve',
        {},
      ),
      null =>
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
    },
  );

  @override
  Future<Result<void>> declineJoinRequest(String teamId, String uid) =>
      _deleteRequest(teamId, uid);

  @override
  Future<Result<void>> inviteToTeam(Team team, String uid, AppUser from) =>
      guard(
        () async => switch (_membersApi) {
          final api? => api.post('/v1/teams/${team.id}/invites', {'uid': uid}),
          null => _invites(uid).doc(team.id).set({
            'teamName': team.name,
            'kind': team.kind.name,
            'invitedBy': from.uid,
            'invitedByName': from.label,
            'createdAt': FieldValue.serverTimestamp(),
          }),
        },
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
    () async => switch (_membersApi) {
      final api? => api.post('/v1/me/team-invites/${invite.teamId}/accept', {}),
      null =>
        (_db.batch()
              ..update(_teams.doc(invite.teamId), _newMember(user))
              ..delete(_invites(user.uid).doc(invite.teamId))
              ..delete(_requests(invite.teamId).doc(user.uid)))
            .commit(),
    },
  );

  @override
  Future<Result<void>> declineInvite(String uid, String teamId) => guard(
    () async => switch (_membersApi) {
      final api? => api.delete('/v1/me/team-invites/$teamId'),
      null => _invites(uid).doc(teamId).delete(),
    },
  );

  @override
  Future<Result<void>> updateTeam(Team team) => guard(() async {
    // The API checks the name and rewrites the listing with the team.
    if (_membersApi case final api?) {
      await api.patch('/v1/teams/${team.id}', team.toEditableMap());
      return;
    }
    final listed = await _directory.doc(team.id).get();
    final before = listed.exists
        ? TeamListing.fromMap(listed.id, plainData(listed.data()))
        : null;
    // Renamed, or moved to another division: the new one must be free.
    if (before == null ||
        teamNameKey(before.name) != teamNameKey(team.name) ||
        before.division != team.division ||
        before.kind != team.kind) {
      await _ensureNameFree(
        team.name,
        team.kind,
        team.division,
        excludeId: team.id,
      );
    }
    await (_db.batch()
          ..update(_teams.doc(team.id), team.toEditableMap())
          ..set(_directory.doc(team.id), TeamListing.of(team).toMap()))
        .commit();
  });

  @override
  Future<Result<List<TeamListing>>> searchTeams(
    String query,
  ) => guard(() async {
    final words = searchWords(query);
    if (words.isEmpty) return const [];
    // Match the longest word in Firestore, then the rest here.
    final key = (words.toList()..sort((a, b) => b.length - a.length)).first;
    final k = key.length > 20 ? key.substring(0, 20) : key;
    final List<SearchHit> hits;
    if (_search case final s? when s.enabled) {
      hits = await s.search(SearchKind.teams, k);
    } else {
      final snap = await _directory
          .where('keywords', arrayContains: k)
          .limit(_searchLimit * 2)
          .get();
      hits = [for (final d in snap.docs) (id: d.id, data: plainData(d.data()))];
    }
    return [
        for (final h in hits) TeamListing.fromMap(h.id, h.data),
      ].where((t) => t.matches(query)).take(_searchLimit).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  });

  @override
  Stream<TeamListing?> watchListing(String teamId) => _shared.get(
    'listing/$teamId',
    () => countedDocSnapshots(_directory.doc(teamId), 'teamListing').map(
      (d) => d.exists ? TeamListing.fromMap(d.id, plainData(d.data())) : null,
    ),
  );

  @override
  Future<Result<void>> publishListing(Team team) => guard(
    () async => switch (_membersApi) {
      final api? => api.put('/v1/teams/${team.id}/listing', {}),
      null => _directory.doc(team.id).set(TeamListing.of(team).toMap()),
    },
  );

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
    // The API makes the code and checks who may.
    if (_membersApi case final api?) {
      final res = await api.post('/v1/invite-codes', {
        'teamId': teamId,
        'ttl': ttl.inSeconds,
      });
      return InviteCode(
        code: res['code']! as String,
        teamId: res['teamId']! as String,
        expiresAt: DateTime.parse(res['expiresAt']! as String).toLocal(),
      );
    }
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
  ) => guard(
    () async => switch (_membersApi) {
      final api? => api.put('/v1/teams/$teamId/members/$uid/role', {
        'role': role.name,
      }),
      null => _teams.doc(teamId).update({'members.$uid': role.name}),
    },
  );

  @override
  Future<Result<void>> setStatKeeper(
    String teamId,
    String uid, {
    required bool on,
  }) => guard(
    () async => switch (_membersApi) {
      final api? => api.put('/v1/teams/$teamId/members/$uid/stat-keeper', {
        'on': on,
      }),
      null => _teams.doc(teamId).update({
        'statKeepers': on
            ? FieldValue.arrayUnion([uid])
            : FieldValue.arrayRemove([uid]),
      }),
    },
  );

  @override
  Future<Result<void>> transferOwnership(
    String teamId, {
    required String ownerUid,
    required String newOwnerUid,
  }) => guard(
    () async => switch (_membersApi) {
      final api? => api.post('/v1/teams/$teamId/owner', {'uid': newOwnerUid}),
      null => _teams.doc(teamId).update({
        'ownerId': newOwnerUid,
        'members.$newOwnerUid': TeamRole.owner.name,
        'members.$ownerUid': TeamRole.player.name,
      }),
    },
  );

  @override
  Future<Result<void>> removeMember(String teamId, String uid) => guard(
    () async => switch (_membersApi) {
      final api? => api.delete('/v1/teams/$teamId/members/$uid'),
      null => _teams.doc(teamId).update({
        'members.$uid': FieldValue.delete(),
        'memberNames.$uid': FieldValue.delete(),
        'memberIds': FieldValue.arrayRemove([uid]),
        'statKeepers': FieldValue.arrayRemove([uid]),
        'memberRoles.$uid': FieldValue.delete(),
        'memberPerms.$uid': FieldValue.delete(),
      }),
    },
  );

  @override
  Future<Result<void>> saveRoles(
    Team team, {
    required Map<String, CustomRole> roles,
    required Map<String, Set<String>> memberRoles,
  }) => guard(
    () async => switch (_membersApi) {
      // The API cleans who has which and works out memberPerms itself.
      final api? => api.put('/v1/teams/${team.id}/roles', {
        'roles': {for (final r in roles.values) r.id: r.toMap()},
        'memberRoles': {
          for (final e in memberRoles.entries) e.key: e.value.toList()..sort(),
        },
      }),
      null => _teams.doc(team.id).update({
        ...rolesData(
          roles,
          cleanMemberRoles(memberRoles, roles, team.members.keys),
        ),
      }),
    },
  );

  @override
  Future<Result<void>> migrateTiersToRoles(Team team) => guard(() async {
    final tierRoles = team.legacyTierRoles();
    if (tierRoles.isEmpty) return;
    final legacy = {
      for (final e in team.members.entries)
        if (tierRoles[e.value] case final role?) e.key: role.id,
    };
    final roles = {...team.roles, for (final r in tierRoles.values) r.id: r};
    final memberRoles = {
      ...team.memberRoles,
      for (final e in legacy.entries)
        e.key: {...?team.memberRoles[e.key], e.value},
    };
    final ref = _teams.doc(team.id);
    // 1. The roles, while they're still on their tiers.
    await ref.update(
      rolesData(roles, cleanMemberRoles(memberRoles, roles, team.members.keys)),
    );
    // 2. Rooms and folders open to a tier open to its role too.
    for (final collection in [
      chatRooms(_db, team.id),
      chatFolders(_db, team.id),
    ]) {
      final batch = _db.batch();
      var updates = 0;
      for (final d in (await collection.get()).docs) {
        final update = <String, Object>{};
        for (final field in ['readRoles', 'writeRoles']) {
          final ids = {for (final x in (d.data()[field] as List?) ?? []) '$x'};
          final add = [
            for (final e in tierRoles.entries)
              if (ids.contains(e.key.name) && !ids.contains(e.value.id))
                e.value.id,
          ];
          if (add.isNotEmpty) update[field] = FieldValue.arrayUnion(add);
        }
        if (update.isEmpty) continue;
        batch.update(d.reference, update);
        updates++;
      }
      if (updates > 0) await batch.commit();
    }
    // 3. Off the old tiers, all at once (firestore.rules wants that).
    await ref.update({
      for (final uid in legacy.keys) 'members.$uid': TeamRole.player.name,
    });
  });

  @override
  Future<Result<void>> deleteTeam(
    Team team, {
    void Function(DeleteProgress progress)? onProgress,
  }) => guard(() async {
    final ref = _teams.doc(team.id);
    const subs = [
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
      'tournamentEntries',
    ];
    // Chat, meetings, tournaments, videos' files, posts' photos, each
    // collection, then the team itself.
    final total = 5 + subs.length + 1;
    var done = 0;
    void step(String label) =>
        onProgress?.call((done: done++, total: total, step: label));
    step('Getting ready');
    // Tells the notification functions not to announce the cascade below
    // (every event "cancelled", and so on).
    await ref.update({'deletingAt': FieldValue.serverTimestamp()});
    try {
      // Firestore doesn't cascade deletes; clear subcollections first.
      step('Deleting chat');
      for (final room in (await chatRooms(_db, team.id).get()).docs) {
        await deleteChatRoom(_db, _files, room.reference);
      }
      await deleteDocs(_db, [
        for (final d in (await chatFolders(_db, team.id).get()).docs)
          d.reference,
      ]);
      step('Deleting meetings');
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
      step('Deleting tournaments');
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
      step('Deleting videos');
      for (final video in (await ref.collection('videos').get()).docs) {
        final path = TeamVideo.fromMap(
          video.id,
          plainData(video.data()),
        ).file?.path;
        if (path != null) await _files.delete([path]);
      }
      // Post photos go before their posts, which list them.
      step('Deleting photos');
      for (final post in (await ref.collection('posts').get()).docs) {
        await _files.delete(
          TeamPost.fromMap(
            post.id,
            plainData(post.data()),
          ).images.map((i) => i.path),
        );
      }
      for (final sub in subs) {
        step(_deleteStepLabel(sub));
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
    step('Finishing up');
    await (_db.batch()
          ..delete(_directory.doc(team.id))
          ..delete(ref))
        .commit();
    onProgress?.call((done: total, total: total, step: 'Deleted'));
  });

  static String _deleteStepLabel(String collection) => switch (collection) {
    'roster' || 'rosterStatus' => 'Deleting the roster',
    'joins' || 'joinRequests' => 'Deleting join requests',
    'plays' => 'Deleting the playbook',
    'tournamentEntries' => 'Deleting tournament entries',
    'events' || 'publicEvents' => 'Deleting events',
    'posts' => 'Deleting posts',
    'videos' || 'videoFolders' => 'Deleting videos',
    _ => 'Deleting stats',
  };

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
    return combineLatest(roster, status, (r, s) {
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

/// Every document a new team starts with, by path: the team (its creator
/// the sole owner), its directory listing, General and the default voice
/// channels. [createdAt] is each timestamp (the server's time when
/// writing). The API writes the same documents (apps/api/src/teams/
/// documents.ts); test/data/new_team_docs_test.dart and the API's tests
/// check both against packages/shared/fixtures/team_create.json.
Map<String, Map<String, dynamic>> newTeamDocs(
  String teamId,
  NewTeam team,
  AppUser owner, {
  required Object createdAt,
}) => {
  'teams/$teamId': {
    ...team.toMap(),
    'ownerId': owner.uid,
    'members': {owner.uid: TeamRole.owner.name},
    'memberIds': [owner.uid],
    'memberNames': {owner.uid: owner.label},
    'createdAt': createdAt,
  },
  'teamDirectory/$teamId': team.listing(teamId).toMap(),
  'teams/$teamId/chats/${ChatRoom.generalId}': newRoomData(
    ChatRoom.general(),
    owner.uid,
    createdAt: createdAt,
  ),
  'teams/$teamId/chatFolders/${ChatRoom.voiceFolderId}': newFolderData(
    ChatRoom.defaultVoiceFolder(),
    owner.uid,
    createdAt: createdAt,
  ),
  for (final r in ChatRoom.defaultVoiceRooms())
    'teams/$teamId/chats/${r.id}': newRoomData(
      r,
      owner.uid,
      createdAt: createdAt,
    ),
};
