import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../domain/models/app_user.dart';
import '../../../domain/models/roster_player.dart';
import '../../../domain/models/team.dart';
import '../../../utils/result.dart';
import '../../services/firestore_utils.dart';
import 'team_repository.dart';

class InviteCodeNotFoundException implements Exception {
  const InviteCodeNotFoundException();

  @override
  String toString() => 'No team found for that invite code.';
}

/// Team data lives in `teams/{teamId}` with `roster` and `plays`
/// subcollections. `inviteCodes/{code}` maps a code to its team.
/// All writes are validated by `firestore.rules`.
class TeamRepositoryFirebase implements TeamRepository {
  TeamRepositoryFirebase({FirebaseFirestore? firestore, Random? random})
    : _db = firestore ?? FirebaseFirestore.instance,
      _random = random ?? Random.secure();

  final FirebaseFirestore _db;
  final Random _random;

  // No 0/O/1/I to keep codes easy to read aloud.
  static const _codeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static const _codeLength = 6;

  CollectionReference<Map<String, dynamic>> get _teams =>
      _db.collection('teams');

  CollectionReference<Map<String, dynamic>> get _codes =>
      _db.collection('inviteCodes');

  CollectionReference<Map<String, dynamic>> _roster(String teamId) =>
      _teams.doc(teamId).collection('roster');

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

  @override
  Future<Result<String>> createTeam(NewTeam team, AppUser owner) =>
      guard(() async {
        // Retry on the (unlikely) event of an invite code collision, which
        // surfaces as permission-denied because codes can't be overwritten.
        for (var attempt = 0; ; attempt++) {
          final ref = _teams.doc();
          final code = _newCode();
          final batch = _db.batch()
            ..set(ref, {
              ...team.toMap(),
              'ownerId': owner.uid,
              'members': {owner.uid: TeamRole.owner.name},
              'memberIds': [owner.uid],
              'memberNames': {owner.uid: owner.label},
              'inviteCode': code,
              'createdAt': FieldValue.serverTimestamp(),
            })
            ..set(_codes.doc(code), {'teamId': ref.id});
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
        // joinCode proves to the security rules that the caller knows the
        // team's current invite code.
        await _teams.doc(teamId).update({
          'members.${user.uid}': TeamRole.player.name,
          'memberNames.${user.uid}': user.label,
          'memberIds': FieldValue.arrayUnion([user.uid]),
          'joinCode': code,
        });
        return teamId;
      });

  @override
  Future<Result<void>> updateTeam(Team team) =>
      guard(() => _teams.doc(team.id).update(team.toEditableMap()));

  @override
  Future<Result<void>> regenerateInviteCode(Team team) => guard(() async {
    final code = _newCode();
    final batch = _db.batch()
      ..update(_teams.doc(team.id), {'inviteCode': code})
      ..set(_codes.doc(code), {'teamId': team.id});
    if (team.inviteCode != null) batch.delete(_codes.doc(team.inviteCode));
    await batch.commit();
  });

  @override
  Future<Result<void>> setMemberRole(
    String teamId,
    String uid,
    TeamRole role,
  ) => guard(() => _teams.doc(teamId).update({'members.$uid': role.name}));

  @override
  Future<Result<void>> removeMember(String teamId, String uid) => guard(
    () => _teams.doc(teamId).update({
      'members.$uid': FieldValue.delete(),
      'memberNames.$uid': FieldValue.delete(),
      'memberIds': FieldValue.arrayRemove([uid]),
    }),
  );

  @override
  Future<Result<void>> deleteTeam(Team team) => guard(() async {
    final ref = _teams.doc(team.id);
    // Firestore doesn't cascade deletes; clear subcollections first.
    for (final sub in ['roster', 'plays']) {
      final docs = await ref.collection(sub).get();
      final batch = _db.batch();
      for (final d in docs.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
    }
    final batch = _db.batch();
    if (team.inviteCode != null) batch.delete(_codes.doc(team.inviteCode));
    batch.delete(ref);
    await batch.commit();
  });

  @override
  Stream<List<RosterPlayer>> watchRoster(String teamId) =>
      _roster(teamId).snapshots().map(
        (snap) =>
            snap.docs
                .map((d) => RosterPlayer.fromMap(d.id, plainData(d.data())))
                .toList()
              ..sort((a, b) {
                final byNumber = (a.number ?? 1000).compareTo(b.number ?? 1000);
                return byNumber != 0 ? byNumber : a.name.compareTo(b.name);
              }),
      );

  @override
  Future<Result<void>> savePlayer(String teamId, RosterPlayer player) =>
      guard(() async {
        final col = _roster(teamId);
        final ref = player.id.isEmpty ? col.doc() : col.doc(player.id);
        await ref.set(player.toMap());
      });

  @override
  Future<Result<void>> deletePlayer(String teamId, String playerId) =>
      guard(() => _roster(teamId).doc(playerId).delete());
}
