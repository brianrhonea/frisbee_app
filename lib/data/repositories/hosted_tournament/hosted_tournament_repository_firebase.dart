import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../domain/models/app_user.dart';
import '../../../domain/models/group_tournament.dart';
import '../../../domain/models/hosted_tournament.dart';
import '../../../domain/models/live_draft.dart';
import '../../../domain/tournament_engine/progress.dart';
import '../../../utils/result.dart';
import '../../services/callable_client.dart';
import '../../services/firestore_utils.dart';
import 'hosted_tournament_repository.dart';

/// `tournaments/{id}` with `divisions/{divisionId}/games`, `entries` and
/// `payments` subcollections. firestore.rules checks who writes what.
class HostedTournamentRepositoryFirebase implements HostedTournamentRepository {
  HostedTournamentRepositoryFirebase({
    FirebaseFirestore? firestore,
    CallableClient? functions,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _functions = functions;

  final FirebaseFirestore _db;
  final CallableClient? _functions;

  CollectionReference<Map<String, dynamic>> get _tournaments =>
      _db.collection('tournaments');

  DocumentReference<Map<String, dynamic>> _doc(String id) =>
      _tournaments.doc(id);

  CollectionReference<Map<String, dynamic>> _divisions(String id) =>
      _doc(id).collection('divisions');

  CollectionReference<Map<String, dynamic>> _entries(String id) =>
      _doc(id).collection('entries');

  CollectionReference<Map<String, dynamic>> _payments(String id) =>
      _doc(id).collection('payments');

  CollectionReference<Map<String, dynamic>> _signups(String id) =>
      _doc(id).collection('signups');

  CollectionReference<Map<String, dynamic>> _drafts(String id) =>
      _doc(id).collection('drafts');

  CollectionReference<Map<String, dynamic>> _games(String id, String div) =>
      _divisions(id).doc(div).collection('games');

  List<HostedTournament> _list(QuerySnapshot<Map<String, dynamic>> snap) => [
    for (final d in snap.docs)
      HostedTournament.fromMap(d.id, plainData(d.data())),
  ];

  @override
  Stream<HostedTournament?> watchTournament(String id) =>
      _doc(id).snapshots().map(
        (d) => d.exists
            ? HostedTournament.fromMap(d.id, plainData(d.data()))
            : null,
      );

  @override
  Stream<List<HostedTournament>> watchHostedBy(
    String hostId, {
    required bool manager,
  }) {
    // Rules hide drafts from everyone but managers, so others must ask
    // for published ones only.
    var query = _tournaments.where('hostId', isEqualTo: hostId);
    if (!manager) {
      query = query.where(
        'status',
        whereIn: [
          for (final s in HostedStatus.values)
            if (s.isPublished) s.name,
        ],
      );
    }
    return query.snapshots().map(
      (snap) => _list(snap)..sort((a, b) => b.startsOn.compareTo(a.startsOn)),
    );
  }

  @override
  Stream<List<EnteredTournament>> watchEnteredBy(String teamId) => _db
      .collection('teams')
      .doc(teamId)
      .collection('tournamentEntries')
      .snapshots()
      .map(
        (snap) => sortEntered([
          for (final d in snap.docs)
            EnteredTournament.fromMap(d.id, plainData(d.data())),
        ]),
      );

  @override
  Stream<List<HostedTournament>> watchUpcoming({int limit = 50}) {
    final today = DateTime.now();
    final midnight = DateTime(today.year, today.month, today.day);
    final open = [
      HostedStatus.registration.name,
      HostedStatus.seeding.name,
      HostedStatus.scheduled.name,
      HostedStatus.live.name,
    ];
    // Ones that start soon or just started.
    final starting = _tournaments
        .where('status', whereIn: open)
        .where(
          'startsOn',
          isGreaterThanOrEqualTo: midnight.subtract(const Duration(days: 7)),
        )
        .orderBy('startsOn')
        .limit(limit);
    // A league that began weeks ago still runs until its last night.
    final running = _tournaments
        .where('status', whereIn: open)
        .where('endsOn', isGreaterThanOrEqualTo: midnight)
        .orderBy('endsOn')
        .limit(limit);
    return _merged(
      starting.snapshots().map(_list),
      // Without its index yet, the first query still lists everything else.
      running.snapshots().map(_list).handleError((Object _) {}),
      limit,
    );
  }

  /// [a] and [b] combined as each updates: tournaments once each, soonest
  /// first, at most [limit].
  Stream<List<HostedTournament>> _merged(
    Stream<List<HostedTournament>> a,
    Stream<List<HostedTournament>> b,
    int limit,
  ) {
    late final StreamController<List<HostedTournament>> out;
    StreamSubscription<List<HostedTournament>>? subA;
    StreamSubscription<List<HostedTournament>>? subB;
    var latestA = const <HostedTournament>[];
    var latestB = const <HostedTournament>[];
    var gotA = false;
    void emit() {
      if (!gotA) return;
      final byId = {
        for (final t in [...latestA, ...latestB]) t.id: t,
      };
      out.add(
        (byId.values.toList()..sort((x, y) => x.startsOn.compareTo(y.startsOn)))
            .take(limit)
            .toList(),
      );
    }

    out = StreamController<List<HostedTournament>>(
      onListen: () {
        subA = a.listen((v) {
          latestA = v;
          gotA = true;
          emit();
        }, onError: out.addError);
        subB = b.listen((v) {
          latestB = v;
          emit();
        }, onError: (Object _) {});
      },
      onCancel: () async {
        await subA?.cancel();
        await subB?.cancel();
      },
    );
    return out.stream;
  }

  @override
  Stream<List<TournamentDivision>> watchDivisions(String tournamentId) =>
      _divisions(tournamentId).snapshots().map(
        (snap) => [
          for (final d in snap.docs)
            TournamentDivision.fromMap(d.id, plainData(d.data())),
        ],
      );

  @override
  Stream<List<TournamentEntry>> watchEntries(String tournamentId) =>
      _entries(tournamentId).snapshots().map(
        (snap) => [
          for (final d in snap.docs)
            TournamentEntry.fromMap(d.id, plainData(d.data())),
        ]..sort((a, b) => a.teamName.compareTo(b.teamName)),
      );

  @override
  Stream<List<EntryPayment>> watchPayments(String tournamentId) =>
      _payments(tournamentId).snapshots().map(
        (snap) => [
          for (final d in snap.docs)
            EntryPayment.fromMap(d.id, plainData(d.data())),
        ],
      );

  @override
  Stream<EntryPayment?> watchPayment(String tournamentId, String teamId) =>
      _payments(tournamentId)
          .doc(teamId)
          .snapshots()
          .map(
            (d) => d.exists
                ? EntryPayment.fromMap(d.id, plainData(d.data()))
                : null,
          );

  @override
  Stream<List<PlayerSignup>> watchSignups(String tournamentId) =>
      _signups(tournamentId).snapshots().map(
        (snap) => [
          for (final d in snap.docs)
            PlayerSignup.fromMap(d.id, plainData(d.data())),
        ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
      );

  @override
  Stream<PlayerSignup?> watchSignup(String tournamentId, String uid) =>
      _signups(tournamentId)
          .doc(uid)
          .snapshots()
          .map(
            (d) => d.exists
                ? PlayerSignup.fromMap(d.id, plainData(d.data()))
                : null,
          );

  @override
  Stream<LiveDraft?> watchDraft(String tournamentId, String divisionId) =>
      _drafts(tournamentId)
          .doc(divisionId)
          .snapshots()
          .map(
            (d) =>
                d.exists ? LiveDraft.fromMap(d.id, plainData(d.data())) : null,
          );

  @override
  Stream<Map<String, DraftDetail>?> watchDraftDetails(
    String tournamentId,
    String divisionId,
  ) => _drafts(tournamentId)
      .doc(divisionId)
      .collection('details')
      .doc('pool')
      .snapshots()
      .map<Map<String, DraftDetail>?>(
        (d) => d.exists
            ? LiveDraft.detailsFromMap(plainData(d.data()))
            : <String, DraftDetail>{},
      )
      // Players who aren't captains can't read it; that's fine.
      .transform(
        StreamTransformer<
          Map<String, DraftDetail>?,
          Map<String, DraftDetail>?
        >.fromHandlers(handleError: (e, s, sink) => sink.add(null)),
      );

  @override
  Stream<List<GroupGame>> watchGames(String tournamentId, String divisionId) =>
      _games(tournamentId, divisionId)
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
    HostedTournament tournament,
    AppUser by,
  ) => guard(() async {
    if (tournament.isNew) {
      final ref = _tournaments.doc();
      await ref.set({
        ...tournament.toMap(),
        'createdBy': by.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return ref.id;
    }
    await _doc(tournament.id).update(tournament.toMap());
    return tournament.id;
  });

  @override
  Future<Result<String>> saveDivision(
    HostedTournament tournament,
    TournamentDivision division,
  ) => guard(() async {
    final col = _divisions(tournament.id);
    final ref = division.isNew ? col.doc() : col.doc(division.id);
    final summary = division.copyWith(id: ref.id).summary;
    // Keep the division's place in the list; new ones go last.
    final ordered = [
      for (final d in tournament.divisions) d.id == ref.id ? summary : d,
      if (!tournament.divisions.any((d) => d.id == ref.id)) summary,
    ];
    await (_db.batch()
          ..set(ref, division.toMap())
          ..update(_doc(tournament.id), {
            'divisions': [for (final d in ordered) d.toMap()],
          }))
        .commit();
    return ref.id;
  });

  @override
  Future<Result<void>> deleteDivision(
    HostedTournament tournament,
    String divisionId,
  ) => guard(() async {
    final games = await _games(tournament.id, divisionId).get();
    await deleteDocs(_db, [for (final d in games.docs) d.reference]);
    await (_db.batch()
          ..delete(_divisions(tournament.id).doc(divisionId))
          ..update(_doc(tournament.id), {
            'divisions': [
              for (final d in tournament.divisions)
                if (d.id != divisionId) d.toMap(),
            ],
          }))
        .commit();
  });

  @override
  Future<Result<void>> setStatus(String tournamentId, HostedStatus status) =>
      guard(() => _doc(tournamentId).update({'status': status.name}));

  @override
  Future<Result<void>> saveEntry(String tournamentId, TournamentEntry entry) =>
      guard(
        () => _entries(tournamentId).doc(entry.teamId).set({
          ...entry.toMap(),
          'updatedAt': FieldValue.serverTimestamp(),
        }),
      );

  @override
  Future<Result<void>> acceptEntry(
    String tournamentId,
    TournamentDivision division,
    TournamentEntry entry,
  ) => guard(
    () =>
        (_db.batch()
              ..set(_entries(tournamentId).doc(entry.teamId), {
                ...entry.copyWith(status: EntryStatus.accepted).toMap(),
                'updatedAt': FieldValue.serverTimestamp(),
              })
              ..update(_divisions(tournamentId).doc(division.id), {
                'seeds': FieldValue.arrayUnion([entry.teamId]),
                'captains.${entry.teamId}': entry.captainIds,
              }))
            .commit(),
  );

  @override
  Future<Result<void>> setEntryStatus(
    String tournamentId,
    TournamentEntry entry,
    EntryStatus status, {
    TournamentDivision? division,
  }) => guard(() {
    final batch = _db.batch()
      ..set(_entries(tournamentId).doc(entry.teamId), {
        ...entry.copyWith(status: status).toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    if (division != null && division.seeds.contains(entry.teamId)) {
      batch.update(_divisions(tournamentId).doc(division.id), {
        'seeds': FieldValue.arrayRemove([entry.teamId]),
        'captains.${entry.teamId}': FieldValue.delete(),
      });
    }
    return batch.commit();
  });

  @override
  Future<Result<void>> savePayment(String tournamentId, EntryPayment payment) =>
      guard(
        () => _payments(tournamentId).doc(payment.teamId).set(payment.toMap()),
      );

  @override
  Future<Result<void>> saveSignup(String tournamentId, PlayerSignup signup) =>
      guard(() async {
        final ref = _signups(tournamentId).doc(signup.uid);
        // createdAt is set once: rules allow it on create only.
        final exists = (await ref.get()).exists;
        if (exists) {
          await ref.update({
            ...signup.toMap(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          await ref.set({
            ...signup.toMap(),
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      });

  @override
  Future<Result<void>> setSignupStatus(
    String tournamentId,
    String uid,
    SignupStatus status,
  ) => guard(
    () => _signups(tournamentId).doc(uid).update({
      'status': status.name,
      'updatedAt': FieldValue.serverTimestamp(),
    }),
  );

  @override
  Future<Result<void>> saveDraftTeams(
    String tournamentId,
    TournamentDivision division,
    List<TournamentTeam> teams,
  ) => guard(
    () => _divisions(tournamentId).doc(division.id).update({
      'teams': [for (final t in teams) t.toMap()],
      'seeds': [for (final t in teams) t.id],
      'captains': {
        for (final t in teams) t.id: [?t.captainId],
      },
    }),
  );

  @override
  Future<Result<void>> publishSchedule(
    String tournamentId,
    TournamentDivision division,
    List<GroupGame> games,
  ) => guard(() async {
    final col = _games(tournamentId, division.id);
    final old = await col.get();
    await deleteDocs(_db, [for (final d in old.docs) d.reference]);
    // A batch takes 500 writes; the division update rides in the last.
    for (var i = 0; i < games.length || i == 0; i += 450) {
      final batch = _db.batch();
      for (final g in games.skip(i).take(450)) {
        batch.set(col.doc(g.id), g.toMap());
      }
      if (i + 450 >= games.length) {
        batch.set(
          _divisions(tournamentId).doc(division.id),
          division.copyWith(placements: const []).toMap(),
        );
      }
      await batch.commit();
    }
  });

  @override
  Future<Result<void>> createLeagueTeams(
    String tournamentId,
    String divisionId,
  ) => guard(() async {
    final functions = _functions;
    if (functions == null) throw const CallableException('Not available.');
    await functions.call('tournaments-createLeagueTeams', {
      'tournamentId': tournamentId,
      'divisionId': divisionId,
    });
  });

  Future<void> _call(String name, Map<String, Object?> data) async {
    final functions = _functions;
    if (functions == null) throw const CallableException('Not available.');
    await functions.call('tournaments-$name', data);
  }

  @override
  Future<Result<void>> startDraft(
    String tournamentId,
    String divisionId,
    List<String> captainIds, {
    int pickSeconds = 0,
  }) => guard(
    () => _call('startDraft', {
      'tournamentId': tournamentId,
      'divisionId': divisionId,
      'captainIds': captainIds,
      'pickSeconds': pickSeconds,
    }),
  );

  @override
  Future<Result<void>> draftPick(
    String tournamentId,
    String divisionId,
    String uid,
  ) => guard(
    () => _call('draftPick', {
      'tournamentId': tournamentId,
      'divisionId': divisionId,
      'uid': uid,
    }),
  );

  @override
  Future<Result<void>> draftControl(
    String tournamentId,
    String divisionId,
    DraftControl action,
  ) => guard(
    () => _call('draftControl', {
      'tournamentId': tournamentId,
      'divisionId': divisionId,
      'action': action.name,
    }),
  );

  @override
  Future<Result<void>> finishDraft(String tournamentId, String divisionId) =>
      guard(
        () => _call('finishDraft', {
          'tournamentId': tournamentId,
          'divisionId': divisionId,
        }),
      );

  @override
  Future<Result<void>> reportScore(
    String tournamentId,
    String divisionId,
    String gameId,
    ScoreReport report,
  ) => guard(
    () => _games(tournamentId, divisionId).doc(gameId).update({
      'report': report.toMap(),
      'status': GameStatus.reported.name,
    }),
  );

  void _fill(
    WriteBatch batch,
    String tournamentId,
    String divisionId,
    List<SlotFill> fills,
  ) {
    for (final f in fills) {
      batch.update(_games(tournamentId, divisionId).doc(f.gameId), {
        if (f.teamA != null) 'teamA': f.teamA,
        if (f.teamB != null) 'teamB': f.teamB,
      });
    }
  }

  Future<void> _final(
    String tournamentId,
    String divisionId,
    String gameId,
    int scoreA,
    int scoreB,
    List<SlotFill> fills,
  ) {
    final batch = _db.batch()
      ..update(_games(tournamentId, divisionId).doc(gameId), {
        'status': GameStatus.done.name,
        'scoreA': scoreA,
        'scoreB': scoreB,
        'report': null,
      });
    _fill(batch, tournamentId, divisionId, fills);
    return batch.commit();
  }

  @override
  Future<Result<void>> confirmScore(
    String tournamentId,
    String divisionId,
    GroupGame game,
    List<SlotFill> fills,
  ) => guard(() {
    final report = game.report;
    if (report == null) throw Exception('No score to confirm');
    return _final(
      tournamentId,
      divisionId,
      game.id,
      report.scoreA,
      report.scoreB,
      fills,
    );
  });

  @override
  Future<Result<void>> setFinalScore(
    String tournamentId,
    String divisionId,
    String gameId, {
    required int scoreA,
    required int scoreB,
    required List<SlotFill> fills,
  }) => guard(
    () => _final(tournamentId, divisionId, gameId, scoreA, scoreB, fills),
  );

  @override
  Future<Result<void>> applyFills(
    String tournamentId,
    String divisionId,
    List<SlotFill> fills,
  ) => guard(() async {
    if (fills.isEmpty) return;
    final batch = _db.batch();
    _fill(batch, tournamentId, divisionId, fills);
    await batch.commit();
  });

  @override
  Future<Result<void>> deleteTournament(String tournamentId) => guard(() async {
    final divisions = await _divisions(tournamentId).get();
    final refs = <DocumentReference<Map<String, dynamic>>>[];
    for (final d in divisions.docs) {
      final games = await d.reference.collection('games').get();
      refs.addAll([for (final g in games.docs) g.reference]);
      refs.add(d.reference);
    }
    final entries = await _entries(tournamentId).get();
    final payments = await _payments(tournamentId).get();
    final signups = await _signups(tournamentId).get();
    final drafts = await _drafts(tournamentId).get();
    await deleteDocs(_db, [
      ...refs,
      for (final d in entries.docs) d.reference,
      for (final d in payments.docs) d.reference,
      for (final d in signups.docs) d.reference,
      for (final d in drafts.docs) d.reference,
      _doc(tournamentId),
    ]);
  });
}
