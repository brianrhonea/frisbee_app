import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/group_tournament.dart';
import 'package:frisbee_app/domain/models/hosted_tournament.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/tournament_engine/generator.dart';
import 'package:frisbee_app/domain/tournament_engine/progress.dart';
import 'package:frisbee_app/utils/result.dart';

import '../testing/hosted_tournament_fakes.dart';

void main() {
  final settings = TournamentSettings(startsAt: DateTime(2027, 5, 1, 9));

  HostedTournament tournament() => HostedTournament(
    id: 'x1',
    hostId: 'g1',
    hostName: 'Denver Ultimate',
    name: 'Spring Fling',
    startsOn: DateTime(2027, 5, 1),
    endsOn: DateTime(2027, 5, 2),
    visibility: TournamentVisibility.inviteOnly,
    bidFee: BidFee(
      amountCents: 25050,
      instructions: 'Venmo @dua',
      dueAt: DateTime(2027, 4, 1),
    ),
    divisions: const [
      DivisionSummary(
        id: 'd1',
        division: Division.mixed,
        level: CompetitionLevel.club,
      ),
    ],
  );

  group('HostedTournament', () {
    test('round-trips through Firestore maps', () {
      final t = tournament();
      final back = HostedTournament.fromMap('x1', t.toMap());
      expect(back.toMap(), t.toMap());
      expect(back.bidFee, t.bidFee);
      expect(back.divisions.single.label, 'Club Mixed');
    });

    test('follows and tags like group tournaments', () {
      expect(tournament().followKey, 'tournament_g1_x1');
    });

    test('bid fee labels', () {
      expect(const BidFee(amountCents: 25000).label, r'$250');
      expect(const BidFee(amountCents: 25050).label, r'$250.50');
      expect(const BidFee(amountCents: 900, currency: 'CAD').label, 'CAD 9');
    });

    test('only drafts are hidden; only registration takes entries', () {
      expect(HostedStatus.draft.isPublished, isFalse);
      expect(HostedStatus.registration.isPublished, isTrue);
      expect(HostedStatus.registration.acceptsEntries, isTrue);
      expect(HostedStatus.scheduled.acceptsEntries, isFalse);
    });
  });

  group('leagues and player entry', () {
    test('a plain tournament has no kind, season or draft settings stored', () {
      final t = HostedTournament.fromMap('x1', tournament().toMap());
      expect(t.kind, HostedKind.tournament);
      expect(t.isLeague, isFalse);
      expect(t.season, isNull);
      expect(t.draftMode, DraftMode.balanced);
      // Older docs have none of the new fields.
      final old = HostedTournament.fromMap('x1', {
        ...tournament().toMap()
          ..remove('kind')
          ..remove('season')
          ..remove('draftMode'),
      });
      expect(old.kind, HostedKind.tournament);
      expect(old.draftMode, DraftMode.balanced);
    });

    test('a league round-trips its season, kind and draft mode', () {
      final league = tournament().copyWith(
        season: () => LeagueSeason(
          weeks: 10,
          playoffWeeks: 2,
          playoffTeams: 8,
          gamesPerNight: 2,
          skipDates: [DateTime(2027, 7, 4)],
        ),
        draftMode: DraftMode.captains,
      );
      final leagueMap = {...league.toMap(), 'kind': 'league'};
      final back = HostedTournament.fromMap('x1', leagueMap);
      expect(back.isLeague, isTrue);
      expect(back.season, league.season);
      expect(back.season!.regularWeeks, 8);
      expect(back.draftMode, DraftMode.captains);
    });

    test('a season without playoffs is all regular season', () {
      const s = LeagueSeason(weeks: 6, playoffWeeks: 2, playoffTeams: 0);
      expect(s.hasPlayoffs, isFalse);
      expect(s.regularWeeks, 6);
    });

    test('a stored season is clamped to what the rules allow', () {
      final s = LeagueSeason.fromMap({
        'weeks': 99,
        'playoffWeeks': 9,
        'playoffTeams': 4,
        'gamesPerNight': 7,
      })!;
      expect(s.weeks, LeagueSeason.maxWeeks);
      expect(s.playoffWeeks, LeagueSeason.maxPlayoffWeeks);
      expect(s.gamesPerNight, LeagueSeason.maxGamesPerNight);
    });

    test('player entry takes an entry fee per player', () {
      final hat = HostedTournament(
        id: 'h1',
        hostId: 'g1',
        hostName: 'Denver Ultimate',
        name: 'Hat Day',
        startsOn: DateTime(2027, 6, 1),
        entryType: TournamentEntryType.players,
        bidFee: const EntryFee(amountCents: 2000),
      );
      expect(hat.takesPlayers, isTrue);
      expect(hat.isHat, isTrue);
      expect(hat.entryFee?.label, r'$20');
      expect(hat.copyWith(season: () => const LeagueSeason()).isHat, isTrue);
    });

    test('min roster falls back to the old full-roster default', () {
      final d = TournamentDivision(
        id: 'd1',
        division: Division.mixed,
        level: CompetitionLevel.league,
        settings: settings,
      );
      expect(d.effectiveMinRoster, TournamentDivision.defaultMinRoster);
      expect(d.copyWith(minRoster: () => 4).effectiveMinRoster, 4);
      final back = TournamentDivision.fromMap(
        'd1',
        d.copyWith(minRoster: () => 4).toMap(),
      );
      expect(back.minRoster, 4);
      expect(TournamentDivision.fromMap('d1', d.toMap()).minRoster, isNull);
    });

    test('a division keeps its drafted teams', () {
      const team = TournamentTeam(
        id: 'a',
        name: 'Red',
        captainId: 'p1',
        playerIds: ['p1', 'p2'],
        playerNames: {'p1': 'Pat', 'p2': 'Sam'},
      );
      final d = TournamentDivision(
        id: 'd1',
        division: Division.mixed,
        level: CompetitionLevel.league,
        settings: settings,
      ).copyWith(teams: [team]);
      final back = TournamentDivision.fromMap('d1', d.toMap());
      expect(back.teams.single.playerIds, ['p1', 'p2']);
      expect(back.teams.single.captainId, 'p1');
    });

    test('a signup round-trips; skill is clamped and gender is optional', () {
      const s = PlayerSignup(
        uid: 'u1',
        name: 'Pat',
        divisionId: 'd1',
        skill: 4,
        gender: GenderMatch.wmp,
      );
      final back = PlayerSignup.fromMap('u1', s.toMap());
      expect(back.skill, 4);
      expect(back.gender, GenderMatch.wmp);
      expect(back.status, SignupStatus.applied);
      expect(back.copyWith(gender: () => null).gender, isNull);
      final wild = PlayerSignup.fromMap('u1', {'skill': 99, 'gender': '?'});
      expect(wild.skill, PlayerSignup.maxSkill);
      expect(wild.gender, isNull);
    });
  });

  group('TournamentDivision', () {
    final div = TournamentDivision(
      id: 'd1',
      division: Division.women,
      level: CompetitionLevel.college,
      settings: settings,
      maxTeams: 4,
      seeds: const ['a', 'b', 'c'],
      captains: const {
        'a': ['u1', 'u2'],
        'b': ['u3'],
      },
    );

    test('round-trips through Firestore maps', () {
      final back = TournamentDivision.fromMap('d1', div.toMap());
      expect(back.toMap(), div.toMap());
      expect(back.captainIds, {'u1', 'u2', 'u3'});
    });

    test('reseeding moves a team and keeps the rest in order', () {
      expect(div.reseed(2, 0).seeds, ['c', 'a', 'b']);
      expect(div.reseed(0, 2).seeds, ['b', 'c', 'a']);
      expect(div.seedOf('b'), 2);
      expect(div.seedOf('z'), isNull);
    });

    test('is full at its cap', () {
      expect(div.isFull, isFalse);
      expect(div.copyWith(seeds: ['a', 'b', 'c', 'd']).isFull, isTrue);
    });

    test('the engine schedules a division from its seeds', () {
      final plan = scheduleFor([
        'a',
        'b',
        'c',
        'd',
      ], settings.copyWith(format: TournamentFormat.singleElim));
      expect(plan.games, hasLength(3));
      final first = [
        for (final g in plan.games)
          if (g.hasTeams) {g.teamA, g.teamB},
      ];
      // Seed 1 plays seed 4, and 2 plays 3.
      expect(
        first,
        containsAll([
          {'a', 'd'},
          {'b', 'c'},
        ]),
      );
    });
  });

  test('entries and payments round-trip through Firestore maps', () {
    const e = TournamentEntry(
      teamId: 't1',
      teamName: 'Hawks',
      divisionId: 'd1',
      status: EntryStatus.waitlisted,
      captainIds: ['u1'],
    );
    expect(TournamentEntry.fromMap('t1', e.toMap()).toMap(), e.toMap());
    expect(EntryStatus.waitlisted.isActive, isTrue);
    expect(EntryStatus.declined.isActive, isFalse);

    final p = EntryPayment(
      teamId: 't1',
      paid: true,
      paidAt: DateTime(2027, 3, 2),
      note: 'Venmo',
    );
    expect(EntryPayment.fromMap('t1', p.toMap()).toMap(), p.toMap());
  });

  test('fake repository: accept seeds last, withdraw unseeds, scores '
      'finish games', () async {
    final repo = FakeHostedTournamentRepository();
    final saved = await repo.saveTournament(
      tournament().copyWith(id: '', divisions: const []),
      const AppUser(uid: 'u0', displayName: 'Host'),
    );
    final id = (saved as Ok<String>).value;
    final added = await repo.saveDivision(
      repo.tournaments[id]!,
      TournamentDivision(
        id: '',
        division: Division.mixed,
        level: CompetitionLevel.club,
        settings: settings,
      ),
    );
    final divId = (added as Ok<String>).value;
    expect(repo.tournaments[id]!.divisions.single.id, divId);

    for (final team in ['t1', 't2', 't3']) {
      await repo.acceptEntry(
        id,
        repo.divisions[id]![divId]!,
        TournamentEntry(
          teamId: team,
          teamName: team,
          divisionId: divId,
          captainIds: ['c$team'],
        ),
      );
    }
    expect(repo.divisions[id]![divId]!.seeds, ['t1', 't2', 't3']);
    expect(repo.divisions[id]![divId]!.captains['t2'], ['ct2']);

    await repo.setEntryStatus(
      id,
      repo.entries[id]!['t1']!,
      EntryStatus.withdrawn,
      division: repo.divisions[id]![divId],
    );
    expect(repo.divisions[id]![divId]!.seeds, ['t2', 't3']);
    expect(repo.divisions[id]![divId]!.captains.containsKey('t1'), isFalse);
    expect(repo.entries[id]!['t1']!.status, EntryStatus.withdrawn);

    final division = repo.divisions[id]![divId]!;
    final games = scheduleFor(division.seeds, settings).games;
    await repo.publishSchedule(id, division, games);
    final g = games.first;
    await repo.setFinalScore(
      id,
      divId,
      g.id,
      scoreA: 15,
      scoreB: 9,
      fills: fillsAfter(
        g.copyWith(status: GameStatus.done, scoreA: () => 15, scoreB: () => 9),
        games,
      ),
    );
    final played = await repo.watchGames(id, divId).first;
    expect(played.firstWhere((x) => x.id == g.id).isDone, isTrue);
  });
}
