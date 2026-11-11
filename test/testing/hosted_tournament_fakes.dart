import 'dart:async';

import 'package:frisbee_app/data/repositories/hosted_tournament/hosted_tournament_repository.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/group_tournament.dart';
import 'package:frisbee_app/domain/models/hosted_tournament.dart';
import 'package:frisbee_app/domain/tournament_engine/progress.dart';
import 'package:frisbee_app/utils/result.dart';

/// In memory. Like the group tournament fake, it doesn't enforce who may
/// write: firestore.rules does, and the rules tests cover it.
class FakeHostedTournamentRepository implements HostedTournamentRepository {
  final tournaments = <String, HostedTournament>{};

  /// tournamentId → divisionId → division.
  final divisions = <String, Map<String, TournamentDivision>>{};

  /// tournamentId → teamId → entry.
  final entries = <String, Map<String, TournamentEntry>>{};

  /// tournamentId → teamId → payment.
  final payments = <String, Map<String, EntryPayment>>{};

  /// tournamentId → uid → player signup.
  final signups = <String, Map<String, PlayerSignup>>{};

  /// `tournamentId/divisionId` → games.
  final games = <String, List<GroupGame>>{};

  /// Calls, for asserting what was written.
  final log = <String>[];

  final _changes = StreamController<void>.broadcast();
  var _next = 0;

  void _changed() => _changes.add(null);

  Stream<T> _watch<T>(T Function() read) async* {
    yield read();
    yield* _changes.stream.map((_) => read());
  }

  String _key(String t, String d) => '$t/$d';

  void _update(String key, GroupGame Function(GroupGame) change) {
    final list = games[key];
    if (list == null) return;
    for (var i = 0; i < list.length; i++) {
      list[i] = change(list[i]);
    }
  }

  void _fill(String key, List<SlotFill> fills) {
    for (final f in fills) {
      _update(
        key,
        (g) => g.id != f.gameId
            ? g
            : g.copyWith(
                teamA: f.teamA == null ? null : () => f.teamA,
                teamB: f.teamB == null ? null : () => f.teamB,
              ),
      );
    }
  }

  void _finish(String key, String gameId, int a, int b, List<SlotFill> fills) {
    _update(
      key,
      (g) => g.id != gameId
          ? g
          : g.copyWith(
              status: GameStatus.done,
              scoreA: () => a,
              scoreB: () => b,
              report: () => null,
            ),
    );
    _fill(key, fills);
    _changed();
  }

  @override
  Stream<HostedTournament?> watchTournament(String id) =>
      _watch(() => tournaments[id]);

  /// teamId → its records of the tournaments it entered (the server
  /// keeps these; tests set them).
  final entered = <String, List<EnteredTournament>>{};

  @override
  Stream<List<EnteredTournament>> watchEnteredBy(String teamId) =>
      _watch(() => sortEntered([...?entered[teamId]]));

  @override
  Stream<List<HostedTournament>> watchHostedBy(
    String hostId, {
    required bool manager,
  }) => _watch(
    () => [
      for (final t in tournaments.values)
        if (t.hostId == hostId && (manager || t.status.isPublished)) t,
    ]..sort((a, b) => b.startsOn.compareTo(a.startsOn)),
  );

  @override
  Stream<List<HostedTournament>> watchUpcoming({int limit = 50}) => _watch(() {
    final list = [
      for (final t in tournaments.values)
        if (t.status.isPublished && t.status != HostedStatus.finished) t,
    ]..sort((a, b) => a.startsOn.compareTo(b.startsOn));
    return list.take(limit).toList();
  });

  @override
  Stream<List<TournamentDivision>> watchDivisions(String tournamentId) =>
      _watch(() => [...?divisions[tournamentId]?.values]);

  @override
  Stream<List<TournamentEntry>> watchEntries(String tournamentId) => _watch(
    () =>
        [...?entries[tournamentId]?.values]
          ..sort((a, b) => a.teamName.compareTo(b.teamName)),
  );

  @override
  Stream<List<EntryPayment>> watchPayments(String tournamentId) =>
      _watch(() => [...?payments[tournamentId]?.values]);

  @override
  Stream<EntryPayment?> watchPayment(String tournamentId, String teamId) =>
      _watch(() => payments[tournamentId]?[teamId]);

  @override
  Stream<List<PlayerSignup>> watchSignups(String tournamentId) => _watch(
    () =>
        [...?signups[tournamentId]?.values]
          ..sort((a, b) => a.name.compareTo(b.name)),
  );

  @override
  Stream<PlayerSignup?> watchSignup(String tournamentId, String uid) =>
      _watch(() => signups[tournamentId]?[uid]);

  @override
  Stream<List<GroupGame>> watchGames(String tournamentId, String divisionId) =>
      _watch(
        () =>
            [...?games[_key(tournamentId, divisionId)]]
              ..sort((a, b) => a.order.compareTo(b.order)),
      );

  @override
  Future<Result<String>> saveTournament(
    HostedTournament tournament,
    AppUser by,
  ) async {
    log.add('save');
    final id = tournament.isNew ? 'h${++_next}' : tournament.id;
    final old = tournaments[id];
    tournaments[id] = HostedTournament.fromMap(id, {
      ...tournament.toMap(),
      'createdBy': old?.createdBy ?? by.uid,
      'createdAt': old?.createdAt ?? DateTime(2026, 11, 1),
    });
    _changed();
    return Result.ok(id);
  }

  @override
  Future<Result<String>> saveDivision(
    HostedTournament tournament,
    TournamentDivision division,
  ) async {
    log.add('division');
    final id = division.isNew ? 'd${++_next}' : division.id;
    final saved = division.copyWith(id: id);
    divisions.putIfAbsent(tournament.id, () => {})[id] = saved;
    final t = tournaments[tournament.id] ?? tournament;
    tournaments[tournament.id] = t.copyWith(
      divisions: [
        for (final d in t.divisions) d.id == id ? saved.summary : d,
        if (!t.divisions.any((d) => d.id == id)) saved.summary,
      ],
    );
    _changed();
    return Result.ok(id);
  }

  @override
  Future<Result<void>> deleteDivision(
    HostedTournament tournament,
    String divisionId,
  ) async {
    divisions[tournament.id]?.remove(divisionId);
    games.remove(_key(tournament.id, divisionId));
    final t = tournaments[tournament.id];
    if (t != null) {
      tournaments[t.id] = t.copyWith(
        divisions: [
          for (final d in t.divisions)
            if (d.id != divisionId) d,
        ],
      );
    }
    _changed();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> setStatus(
    String tournamentId,
    HostedStatus status,
  ) async {
    final t = tournaments[tournamentId];
    if (t == null) return Result.error(Exception('Tournament not found.'));
    tournaments[tournamentId] = t.copyWith(status: status);
    _changed();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> saveEntry(
    String tournamentId,
    TournamentEntry entry,
  ) async {
    log.add('entry ${entry.teamId} ${entry.status.name}');
    entries.putIfAbsent(tournamentId, () => {})[entry.teamId] = entry;
    _changed();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> acceptEntry(
    String tournamentId,
    TournamentDivision division,
    TournamentEntry entry,
  ) async {
    log.add('accept ${entry.teamId}');
    entries.putIfAbsent(tournamentId, () => {})[entry.teamId] = entry.copyWith(
      status: EntryStatus.accepted,
    );
    final map = divisions.putIfAbsent(tournamentId, () => {});
    final d = map[division.id] ?? division;
    map[division.id] = d.copyWith(
      seeds: [...d.seeds.where((s) => s != entry.teamId), entry.teamId],
      captains: {...d.captains, entry.teamId: entry.captainIds},
    );
    _changed();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> setEntryStatus(
    String tournamentId,
    TournamentEntry entry,
    EntryStatus status, {
    TournamentDivision? division,
  }) async {
    log.add('entry ${entry.teamId} ${status.name}');
    entries.putIfAbsent(tournamentId, () => {})[entry.teamId] = entry.copyWith(
      status: status,
    );
    final d = division == null ? null : divisions[tournamentId]?[division.id];
    if (d != null) {
      divisions[tournamentId]![d.id] = d.copyWith(
        seeds: [...d.seeds.where((s) => s != entry.teamId)],
        captains: {...d.captains}..remove(entry.teamId),
      );
    }
    _changed();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> savePayment(
    String tournamentId,
    EntryPayment payment,
  ) async {
    log.add('paid ${payment.teamId} ${payment.paid}');
    payments.putIfAbsent(tournamentId, () => {})[payment.teamId] = payment;
    _changed();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> saveSignup(
    String tournamentId,
    PlayerSignup signup,
  ) async {
    log.add('signup ${signup.uid} ${signup.status.name}');
    signups.putIfAbsent(tournamentId, () => {})[signup.uid] = signup;
    _changed();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> setSignupStatus(
    String tournamentId,
    String uid,
    SignupStatus status,
  ) async {
    log.add('signup $uid ${status.name}');
    final s = signups[tournamentId]?[uid];
    if (s == null) return Result.error(Exception('No signup.'));
    signups[tournamentId]![uid] = s.copyWith(status: status);
    _changed();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> saveDraftTeams(
    String tournamentId,
    TournamentDivision division,
    List<TournamentTeam> teams,
  ) async {
    log.add('draft ${division.id} ${teams.length}');
    final map = divisions.putIfAbsent(tournamentId, () => {});
    final d = map[division.id] ?? division;
    map[division.id] = d.copyWith(
      teams: teams,
      seeds: [for (final t in teams) t.id],
      captains: {
        for (final t in teams)
          t.id: [?t.captainId],
      },
    );
    _changed();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> publishSchedule(
    String tournamentId,
    TournamentDivision division,
    List<GroupGame> games,
  ) async {
    log.add('publish ${division.id}');
    this.games[_key(tournamentId, division.id)] = [...games];
    divisions.putIfAbsent(tournamentId, () => {})[division.id] = division
        .copyWith(placements: const []);
    _changed();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> reportScore(
    String tournamentId,
    String divisionId,
    String gameId,
    ScoreReport report,
  ) async {
    log.add('report $gameId');
    _update(
      _key(tournamentId, divisionId),
      (g) => g.id != gameId
          ? g
          : g.copyWith(status: GameStatus.reported, report: () => report),
    );
    _changed();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> confirmScore(
    String tournamentId,
    String divisionId,
    GroupGame game,
    List<SlotFill> fills,
  ) async {
    log.add('confirm ${game.id}');
    final r = game.report!;
    _finish(_key(tournamentId, divisionId), game.id, r.scoreA, r.scoreB, fills);
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> setFinalScore(
    String tournamentId,
    String divisionId,
    String gameId, {
    required int scoreA,
    required int scoreB,
    required List<SlotFill> fills,
  }) async {
    log.add('set $gameId');
    _finish(_key(tournamentId, divisionId), gameId, scoreA, scoreB, fills);
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> applyFills(
    String tournamentId,
    String divisionId,
    List<SlotFill> fills,
  ) async {
    log.add('fill ${fills.length}');
    _fill(_key(tournamentId, divisionId), fills);
    _changed();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> deleteTournament(String tournamentId) async {
    log.add('delete');
    tournaments.remove(tournamentId);
    divisions.remove(tournamentId);
    entries.remove(tournamentId);
    payments.remove(tournamentId);
    signups.remove(tournamentId);
    games.removeWhere((k, _) => k.startsWith('$tournamentId/'));
    _changed();
    return const Result.ok(null);
  }
}
