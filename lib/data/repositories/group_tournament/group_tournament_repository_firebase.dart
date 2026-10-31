import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../domain/models/app_user.dart';
import '../../../domain/models/group_tournament.dart';
import '../../../domain/tournament_engine/progress.dart';
import '../../../utils/result.dart';
import '../../services/firestore_utils.dart';
import 'group_tournament_repository.dart';

/// Tournaments live in `teams/{groupId}/groupTournaments/{id}` with a
/// `games` subcollection. firestore.rules lets organizers write
/// everything, captains report and confirm their own games, and anyone on
/// a team move winners and losers on to the games waiting for them.
class GroupTournamentRepositoryFirebase implements GroupTournamentRepository {
  GroupTournamentRepositoryFirebase({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _tournaments(String groupId) =>
      _db.collection('teams').doc(groupId).collection('groupTournaments');

  CollectionReference<Map<String, dynamic>> _games(
    String groupId,
    String tournamentId,
  ) => _tournaments(groupId).doc(tournamentId).collection('games');

  @override
  Stream<List<GroupTournament>> watchTournaments(
    String groupId, {
    required String uid,
    required bool organizer,
  }) {
    final col = _tournaments(groupId);
    // Rules only let non-organizers read tournaments they play in, so
    // their query must ask for exactly those.
    final query = organizer
        ? col
        : col.where('participantIds', arrayContains: uid);
    return query.snapshots().map(
      (snap) => [
        for (final d in snap.docs)
          GroupTournament.fromMap(d.id, plainData(d.data())),
      ]..sort((a, b) => b.settings.startsAt.compareTo(a.settings.startsAt)),
    );
  }

  @override
  Stream<GroupTournament?> watchTournament(String groupId, String id) =>
      _tournaments(groupId)
          .doc(id)
          .snapshots()
          .map(
            (d) => d.exists
                ? GroupTournament.fromMap(d.id, plainData(d.data()))
                : null,
          );

  @override
  Stream<List<GroupGame>> watchGames(String groupId, String tournamentId) =>
      _games(groupId, tournamentId)
          .orderBy('order')
          .snapshots()
          .map(
            (snap) => [
              for (final d in snap.docs)
                GroupGame.fromMap(d.id, plainData(d.data())),
            ],
          );

  @override
  Future<Result<String>> saveTournament(
    String groupId,
    GroupTournament tournament,
    AppUser by,
  ) => guard(() async {
    final col = _tournaments(groupId);
    if (tournament.isNew) {
      final ref = col.doc();
      await ref.set({
        ...tournament.toMap(),
        'createdBy': by.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return ref.id;
    }
    await col.doc(tournament.id).update(tournament.toMap());
    return tournament.id;
  });

  @override
  Future<Result<void>> publishSchedule(
    String groupId,
    GroupTournament tournament,
    List<GroupGame> games,
  ) => guard(() async {
    final col = _games(groupId, tournament.id);
    final old = await col.get();
    await deleteDocs(_db, [for (final d in old.docs) d.reference]);
    // A batch takes 500 writes; the tournament update rides in the last.
    for (var i = 0; i < games.length || i == 0; i += 450) {
      final batch = _db.batch();
      for (final g in games.skip(i).take(450)) {
        batch.set(col.doc(g.id), g.toMap());
      }
      if (i + 450 >= games.length) {
        batch.update(_tournaments(groupId).doc(tournament.id), {
          ...tournament.toMap(),
          'status': TournamentStatus.scheduled.name,
        });
      }
      await batch.commit();
    }
  });

  @override
  Future<Result<void>> reportScore(
    String groupId,
    String tournamentId,
    String gameId,
    ScoreReport report,
  ) => guard(
    () => _games(groupId, tournamentId).doc(gameId).update({
      'report': report.toMap(),
      'status': GameStatus.reported.name,
    }),
  );

  void _fill(
    WriteBatch batch,
    String groupId,
    String tournamentId,
    List<SlotFill> fills,
  ) {
    for (final f in fills) {
      batch.update(_games(groupId, tournamentId).doc(f.gameId), {
        if (f.teamA != null) 'teamA': f.teamA,
        if (f.teamB != null) 'teamB': f.teamB,
      });
    }
  }

  @override
  Future<Result<void>> confirmScore(
    String groupId,
    String tournamentId,
    GroupGame game,
    List<SlotFill> fills,
  ) => guard(() async {
    final report = game.report;
    if (report == null) throw Exception('No score to confirm');
    final batch = _db.batch()
      ..update(_games(groupId, tournamentId).doc(game.id), {
        'status': GameStatus.done.name,
        'scoreA': report.scoreA,
        'scoreB': report.scoreB,
        'report': null,
      });
    _fill(batch, groupId, tournamentId, fills);
    await batch.commit();
  });

  @override
  Future<Result<void>> setFinalScore(
    String groupId,
    String tournamentId,
    String gameId, {
    required int scoreA,
    required int scoreB,
    required List<SlotFill> fills,
  }) => guard(() async {
    final batch = _db.batch()
      ..update(_games(groupId, tournamentId).doc(gameId), {
        'status': GameStatus.done.name,
        'scoreA': scoreA,
        'scoreB': scoreB,
        'report': null,
      });
    _fill(batch, groupId, tournamentId, fills);
    await batch.commit();
  });

  @override
  Future<Result<void>> applyFills(
    String groupId,
    String tournamentId,
    List<SlotFill> fills,
  ) => guard(() async {
    if (fills.isEmpty) return;
    final batch = _db.batch();
    _fill(batch, groupId, tournamentId, fills);
    await batch.commit();
  });

  @override
  Future<Result<void>> setStatus(
    String groupId,
    String tournamentId,
    TournamentStatus status,
  ) => guard(
    () =>
        _tournaments(groupId).doc(tournamentId).update({'status': status.name}),
  );

  @override
  Future<Result<void>> deleteTournament(String groupId, String tournamentId) =>
      guard(() async {
        final games = await _games(groupId, tournamentId).get();
        await deleteDocs(_db, [
          for (final d in games.docs) d.reference,
          _tournaments(groupId).doc(tournamentId),
        ]);
      });
}
