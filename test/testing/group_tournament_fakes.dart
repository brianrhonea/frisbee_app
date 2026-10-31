import 'dart:async';

import 'package:frisbee_app/data/repositories/group_tournament/group_tournament_repository.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/group_tournament.dart';
import 'package:frisbee_app/domain/tournament_engine/progress.dart';
import 'package:frisbee_app/utils/result.dart';

/// In memory, keyed by group. It doesn't enforce who may write: the
/// Firestore rules do that, and their tests cover it.
class FakeGroupTournamentRepository implements GroupTournamentRepository {
  /// groupId → tournaments.
  final tournaments = <String, List<GroupTournament>>{};

  /// tournamentId → games.
  final games = <String, List<GroupGame>>{};
  final _changes = StreamController<void>.broadcast();
  var _next = 0;

  /// Calls, for asserting what was written.
  final log = <String>[];

  void _changed() => _changes.add(null);

  GroupTournament? _find(String groupId, String id) =>
      tournaments[groupId]?.where((t) => t.id == id).firstOrNull;

  List<GroupGame> _games(String id) =>
      [...?games[id]]..sort((a, b) => a.order.compareTo(b.order));

  void _update(String tournamentId, GroupGame Function(GroupGame) change) {
    final list = games[tournamentId];
    if (list == null) return;
    for (var i = 0; i < list.length; i++) {
      list[i] = change(list[i]);
    }
  }

  void _fill(String tournamentId, List<SlotFill> fills) {
    for (final f in fills) {
      _update(
        tournamentId,
        (g) => g.id != f.gameId
            ? g
            : g.copyWith(
                teamA: f.teamA == null ? null : () => f.teamA,
                teamB: f.teamB == null ? null : () => f.teamB,
              ),
      );
    }
  }

  @override
  Stream<List<GroupTournament>> watchTournaments(
    String groupId, {
    required String uid,
    required bool organizer,
  }) async* {
    List<GroupTournament> visible() => [
      for (final t
          in (tournaments[groupId] ?? const <GroupTournament>[]).reversed)
        if (organizer || t.participantIds.contains(uid)) t,
    ];
    yield visible();
    yield* _changes.stream.map((_) => visible());
  }

  @override
  Stream<GroupTournament?> watchTournament(String groupId, String id) async* {
    yield _find(groupId, id);
    yield* _changes.stream.map((_) => _find(groupId, id));
  }

  @override
  Stream<List<GroupGame>> watchGames(
    String groupId,
    String tournamentId,
  ) async* {
    yield _games(tournamentId);
    yield* _changes.stream.map((_) => _games(tournamentId));
  }

  @override
  Future<Result<String>> saveTournament(
    String groupId,
    GroupTournament tournament,
    AppUser by,
  ) async {
    log.add('save');
    final list = tournaments.putIfAbsent(groupId, () => []);
    if (tournament.isNew) {
      final id = 't${++_next}';
      list.add(
        GroupTournament(
          id: id,
          name: tournament.name,
          eventId: tournament.eventId,
          settings: tournament.settings,
          status: tournament.status,
          teams: tournament.teams,
          createdBy: by.uid,
          createdAt: DateTime(2026, 11, 1),
        ),
      );
      _changed();
      return Result.ok(id);
    }
    final i = list.indexWhere((t) => t.id == tournament.id);
    if (i < 0) return Result.error(Exception('Tournament not found.'));
    // Firestore merges the update, so who made it stays.
    list[i] = GroupTournament(
      id: tournament.id,
      name: tournament.name,
      eventId: tournament.eventId,
      settings: tournament.settings,
      status: tournament.status,
      teams: tournament.teams,
      createdBy: list[i].createdBy,
      createdAt: list[i].createdAt,
    );
    _changed();
    return Result.ok(tournament.id);
  }

  @override
  Future<Result<void>> publishSchedule(
    String groupId,
    GroupTournament tournament,
    List<GroupGame> games,
  ) async {
    log.add('publish');
    this.games[tournament.id] = [...games];
    final list = tournaments[groupId]!;
    final i = list.indexWhere((t) => t.id == tournament.id);
    list[i] = list[i].copyWith(status: TournamentStatus.scheduled);
    _changed();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> reportScore(
    String groupId,
    String tournamentId,
    String gameId,
    ScoreReport report,
  ) async {
    log.add('report $gameId');
    _update(
      tournamentId,
      (g) => g.id != gameId
          ? g
          : g.copyWith(status: GameStatus.reported, report: () => report),
    );
    _changed();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> confirmScore(
    String groupId,
    String tournamentId,
    GroupGame game,
    List<SlotFill> fills,
  ) async {
    log.add('confirm ${game.id}');
    final r = game.report!;
    _update(
      tournamentId,
      (g) => g.id != game.id
          ? g
          : g.copyWith(
              status: GameStatus.done,
              scoreA: () => r.scoreA,
              scoreB: () => r.scoreB,
              report: () => null,
            ),
    );
    _fill(tournamentId, fills);
    _changed();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> setFinalScore(
    String groupId,
    String tournamentId,
    String gameId, {
    required int scoreA,
    required int scoreB,
    required List<SlotFill> fills,
  }) async {
    log.add('set $gameId');
    _update(
      tournamentId,
      (g) => g.id != gameId
          ? g
          : g.copyWith(
              status: GameStatus.done,
              scoreA: () => scoreA,
              scoreB: () => scoreB,
              report: () => null,
            ),
    );
    _fill(tournamentId, fills);
    _changed();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> applyFills(
    String groupId,
    String tournamentId,
    List<SlotFill> fills,
  ) async {
    log.add('fill ${fills.length}');
    _fill(tournamentId, fills);
    _changed();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> setStatus(
    String groupId,
    String tournamentId,
    TournamentStatus status,
  ) async {
    final list = tournaments[groupId]!;
    final i = list.indexWhere((t) => t.id == tournamentId);
    list[i] = list[i].copyWith(status: status);
    _changed();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> deleteTournament(
    String groupId,
    String tournamentId,
  ) async {
    log.add('delete');
    tournaments[groupId]?.removeWhere((t) => t.id == tournamentId);
    games.remove(tournamentId);
    _changed();
    return const Result.ok(null);
  }
}
