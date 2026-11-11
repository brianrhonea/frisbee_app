import 'dart:async';

import 'package:frisbee_app/data/repositories/hosted_tournament/hosted_tournament_repository.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/group_tournament.dart';
import 'package:frisbee_app/domain/models/hosted_tournament.dart';
import 'package:frisbee_app/domain/models/live_draft.dart';
import 'package:frisbee_app/domain/models/team.dart' show Division;
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
        for (final t in teams) t.id: [?t.captainId],
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

  /// Captains' drafts by `tournament/division`, as the server keeps them.
  final Map<String, LiveDraft> drafts = {};

  @override
  Stream<LiveDraft?> watchDraft(String tournamentId, String divisionId) =>
      _watch(() => drafts[_key(tournamentId, divisionId)]);

  @override
  Stream<Map<String, DraftDetail>?> watchDraftDetails(
    String tournamentId,
    String divisionId,
  ) => _watch(() {
    if (drafts[_key(tournamentId, divisionId)] == null) return null;
    return {
      for (final s in signups[tournamentId]?.values ?? const <PlayerSignup>[])
        s.uid: (skill: s.skill, gender: s.gender),
    };
  });

  /// Set to make the draft calls fail, like the server refusing.
  Exception? draftError;

  Result<void> _draftChange(
    String tournamentId,
    String divisionId,
    LiveDraft Function(LiveDraft d) change,
  ) {
    final error = draftError;
    if (error != null) return Result.error(error);
    final key = _key(tournamentId, divisionId);
    final d = drafts[key];
    if (d == null) return Result.error(Exception('The draft has not started.'));
    try {
      drafts[key] = change(d);
    } on _Cancel {
      drafts.remove(key);
    } on Exception catch (e) {
      return Result.error(e);
    }
    _changed();
    return const Result.ok(null);
  }

  LiveDraft _with(LiveDraft d, {DraftStatus? status, List<DraftPick>? picks}) =>
      LiveDraft(
        divisionId: d.divisionId,
        status: status ?? d.status,
        captains: d.captains,
        picks: picks ?? d.picks,
        pool: d.pool,
        pickSeconds: d.pickSeconds,
        mixed: d.mixed,
        turnStartedAt: DateTime(2027),
      );

  @override
  Future<Result<void>> startDraft(
    String tournamentId,
    String divisionId,
    List<String> captainIds, {
    int pickSeconds = 0,
  }) async {
    log.add('start draft $divisionId');
    final error = draftError;
    if (error != null) return Result.error(error);
    if (drafts.containsKey(_key(tournamentId, divisionId))) {
      return Result.error(Exception('This division already has a draft.'));
    }
    final accepted = {
      for (final s in signups[tournamentId]?.values ?? const <PlayerSignup>[])
        if (s.divisionId == divisionId && s.status == SignupStatus.accepted)
          s.uid: s,
    };
    if (captainIds.length < 2 ||
        captainIds.any((c) => !accepted.containsKey(c))) {
      return Result.error(Exception('Pick at least 2 accepted captains.'));
    }
    drafts[_key(tournamentId, divisionId)] = LiveDraft(
      divisionId: divisionId,
      status: DraftStatus.live,
      captains: [
        for (final c in captainIds)
          DraftCaptain(uid: c, name: accepted[c]!.name),
      ],
      pool: {
        for (final s in accepted.values)
          if (!captainIds.contains(s.uid)) s.uid: s.name,
      },
      pickSeconds: pickSeconds,
      mixed: divisions[tournamentId]?[divisionId]?.division == Division.mixed,
      turnStartedAt: DateTime(2027),
    );
    _changed();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> draftPick(
    String tournamentId,
    String divisionId,
    String uid,
  ) async {
    log.add('pick $uid');
    return _draftChange(tournamentId, divisionId, (d) {
      if (d.status != DraftStatus.live) {
        throw Exception('The draft is not running.');
      }
      if (!d.pool.containsKey(uid) || d.pickedIds.contains(uid)) {
        throw Exception('That player cannot be picked.');
      }
      final picks = [...d.picks, DraftPick(uid: uid, captainId: d.onTheClock!)];
      return _with(
        d,
        picks: picks,
        status: picks.length >= d.pool.length
            ? DraftStatus.done
            : DraftStatus.live,
      );
    });
  }

  @override
  Future<Result<void>> draftControl(
    String tournamentId,
    String divisionId,
    DraftControl action,
  ) async {
    log.add('draft ${action.name}');
    return _draftChange(tournamentId, divisionId, (d) {
      switch (action) {
        case DraftControl.pause:
          return _with(d, status: DraftStatus.paused);
        case DraftControl.cancel:
          throw const _Cancel();
        case DraftControl.resume:
          return _with(d, status: DraftStatus.live);
        case DraftControl.undo:
          if (d.picks.isEmpty) throw Exception('Nothing to undo.');
          return _with(
            d,
            picks: d.picks.sublist(0, d.picks.length - 1),
            status: d.status == DraftStatus.paused
                ? DraftStatus.paused
                : DraftStatus.live,
          );
        case DraftControl.autopick:
          final next = d.available.firstOrNull;
          if (next == null || d.onTheClock == null) {
            throw Exception('Nobody is left to pick.');
          }
          final picks = [
            ...d.picks,
            DraftPick(uid: next.key, captainId: d.onTheClock!),
          ];
          return _with(
            d,
            picks: picks,
            status: picks.length >= d.pool.length
                ? DraftStatus.done
                : DraftStatus.live,
          );
      }
    });
  }

  @override
  Future<Result<void>> finishDraft(
    String tournamentId,
    String divisionId,
  ) async {
    log.add('finish draft $divisionId');
    final d = drafts[_key(tournamentId, divisionId)];
    final division = divisions[tournamentId]?[divisionId];
    if (d == null || division == null) {
      return Result.error(Exception('The draft has not started.'));
    }
    final teams = [
      for (final (i, c) in d.captains.indexed)
        TournamentTeam(
          id: 'team${i + 1}',
          name: 'Team ${c.name}',
          captainId: c.uid,
          playerIds: d.teamOf(c.uid),
          playerNames: {for (final id in d.teamOf(c.uid)) id: d.nameOf(id)},
        ),
    ];
    divisions[tournamentId]![divisionId] = division.copyWith(
      teams: teams,
      seeds: [for (final t in teams) t.id],
      captains: {
        for (final t in teams) t.id: [?t.captainId],
      },
    );
    drafts[_key(tournamentId, divisionId)] = _with(
      d,
      status: DraftStatus.finished,
    );
    _changed();
    return const Result.ok(null);
  }

  /// Set to make [createLeagueTeams] fail, like the server refusing.
  Exception? createTeamsError;

  @override
  Future<Result<void>> createLeagueTeams(
    String tournamentId,
    String divisionId,
  ) async {
    log.add('create teams $divisionId');
    final error = createTeamsError;
    if (error != null) return Result.error(error);
    final d = divisions[tournamentId]?[divisionId];
    if (d == null) return Result.error(Exception('No division.'));
    if (d.teamsCreated) return const Result.ok(null);
    if (games[_key(tournamentId, divisionId)]?.isNotEmpty ?? false) {
      return Result.error(Exception('The schedule is published.'));
    }
    // What the server does: real ids, accepted entries, captains reporting.
    final made = [
      for (final t in d.teams)
        TournamentTeam(
          id: '${TournamentDivision.leagueTeamPrefix}${tournamentId}_${t.id}',
          name: t.name,
          captainId: t.captainId,
          playerIds: t.playerIds,
          playerNames: t.playerNames,
        ),
    ];
    divisions[tournamentId]![divisionId] = d.copyWith(
      teams: made,
      seeds: [for (final t in made) t.id],
      captains: {
        for (final t in made) t.id: [?t.captainId],
      },
    );
    for (final t in made) {
      entries.putIfAbsent(tournamentId, () => {})[t.id] = TournamentEntry(
        teamId: t.id,
        teamName: t.name,
        divisionId: divisionId,
        status: EntryStatus.accepted,
        captainIds: [?t.captainId],
      );
    }
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

/// Thrown inside a draft change to delete the draft (cancel).
class _Cancel implements Exception {
  const _Cancel();
}
