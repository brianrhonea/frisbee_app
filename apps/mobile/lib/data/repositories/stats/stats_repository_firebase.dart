import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../domain/models/roster_player.dart';
import '../../../domain/models/stats.dart';
import '../../../utils/result.dart';
import '../../services/firestore_utils.dart';
import '../../services/shared_streams.dart';
import '../team/team_repository.dart';
import 'stats_repository.dart';

/// Stats in Firestore under `teams/{teamId}/statsTournaments` and
/// `teams/{teamId}/statsGames`. A game's points live in its document, so a
/// live game is one document rewritten as stats are tracked; Firestore's
/// offline cache keeps tracking working without signal.
class StatsRepositoryFirebase implements StatsRepository {
  StatsRepositoryFirebase({
    required TeamRepository teamRepository,
    FirebaseFirestore? firestore,
    SharedStreams? sharedStreams,
  }) : _teams = teamRepository,
       _db = firestore ?? FirebaseFirestore.instance,
       _shared = sharedStreams ?? SharedStreams.instance;

  final TeamRepository _teams;
  final FirebaseFirestore _db;

  /// One listener per query, shared by every screen (see [SharedStreams]).
  final SharedStreams _shared;

  DocumentReference<Map<String, dynamic>> _team(String teamId) =>
      _db.collection('teams').doc(teamId);

  CollectionReference<Map<String, dynamic>> _tournaments(String teamId) =>
      _team(teamId).collection('statsTournaments');

  CollectionReference<Map<String, dynamic>> _games(String teamId) =>
      _team(teamId).collection('statsGames');

  @override
  Stream<List<RosterPlayer>> watchPlayers(String teamId) =>
      _teams.watchRoster(teamId);

  @override
  Stream<List<StatsTournament>> watchTournaments(String teamId) => _shared.get(
    'statsTournaments/$teamId',
    () =>
        countedSnapshots(
          _tournaments(teamId).orderBy('startDate', descending: true),
          'statsTournaments',
        ).map(
          (snap) => [
            for (final d in snap.docs)
              StatsTournament.fromMap(d.id, plainData(d.data())),
          ],
        ),
  );

  @override
  Stream<List<StatsGame>> watchGames(String teamId) => _shared.get(
    'statsGames/$teamId',
    () =>
        countedSnapshots(
          _games(teamId).orderBy('date', descending: true),
          'statsGames',
        ).map(
          (snap) => [
            for (final d in snap.docs)
              StatsGame.fromMap(d.id, plainData(d.data())),
          ],
        ),
  );

  @override
  Future<Result<String>> saveTournament(String teamId, StatsTournament t) =>
      guard(() async {
        final col = _tournaments(teamId);
        final ref = t.id.isEmpty ? col.doc() : col.doc(t.id);
        await _write(ref, t.toMap());
        return ref.id;
      });

  @override
  Future<Result<String>> saveGame(String teamId, StatsGame game) =>
      guard(() async {
        final col = _games(teamId);
        final ref = game.id.isEmpty ? col.doc() : col.doc(game.id);
        await _write(ref, game.toMap());
        return ref.id;
      });

  /// Writes [data]. The local cache updates at once; waits briefly for the
  /// server so a rejected write is reported, but doesn't hang offline.
  Future<void> _write(
    DocumentReference<Map<String, dynamic>> ref,
    Map<String, dynamic> data,
  ) => ref
      .set({...data, 'updatedAt': FieldValue.serverTimestamp()})
      .timeout(_serverWait, onTimeout: () {});

  static const _serverWait = Duration(seconds: 5);

  @override
  Future<Result<void>> deleteGame(String teamId, String gameId) =>
      guard(() => _games(teamId).doc(gameId).delete());

  @override
  Future<Result<void>> deleteTournament(String teamId, String tournamentId) =>
      guard(() async {
        final games = await _games(
          teamId,
        ).where('tournamentId', isEqualTo: tournamentId).get();
        // Firestore batches cap at 500 writes; a tournament has far fewer
        // games, but chunk anyway.
        final refs = [
          for (final d in games.docs) d.reference,
          _tournaments(teamId).doc(tournamentId),
        ];
        for (var i = 0; i < refs.length; i += 450) {
          final batch = _db.batch();
          for (final r in refs.skip(i).take(450)) {
            batch.delete(r);
          }
          await batch.commit();
        }
      });
}
