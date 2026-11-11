import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/group_tournament.dart';
import 'package:frisbee_app/domain/models/hosted_tournament.dart';
import 'package:frisbee_app/domain/models/roster_player.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/tournaments/view_models/hosted_tournament_form_viewmodel.dart';
import 'package:frisbee_app/ui/tournaments/view_models/hosted_tournament_viewmodel.dart';
import 'package:frisbee_app/ui/tournaments/view_models/player_signups_viewmodel.dart';
import 'package:frisbee_app/ui/tournaments/view_models/team_draft_viewmodel.dart';
import 'package:frisbee_app/ui/tournaments/widgets/hosted_tournament_screen.dart';
import 'package:frisbee_app/utils/result.dart';

import '../testing/fakes.dart';
import '../testing/hosted_tournament_fakes.dart';

void main() {
  late FakeTeamRepository teams;
  late FakeHostedTournamentRepository repo;

  Team team(String id, String owner, {Map<String, TeamRole> more = const {}}) {
    final members = {owner: TeamRole.owner, ...more};
    return Team(
      id: id,
      name: 'Team $id',
      division: Division.mixed,
      level: CompetitionLevel.club,
      ownerId: owner,
      members: members,
      memberNames: {for (final m in members.keys) m: 'Name $m'},
      kind: TeamKind.community,
    );
  }

  setUp(() {
    teams = FakeTeamRepository();
    repo = FakeHostedTournamentRepository();
    teams.teams['host'] = team('host', 'director');
  });

  FakeAuthRepository as(String uid) => FakeAuthRepository(
    user: AppUser(uid: uid, email: '$uid@x.com', displayName: 'Player $uid'),
  );

  Future<HostedTournamentFormViewModel> form({
    String? hostId = 'host',
    String? tournamentId,
  }) async {
    final f = HostedTournamentFormViewModel(
      hostId: tournamentId == null ? hostId : null,
      tournamentId: tournamentId,
      tournamentRepository: repo,
      teamRepository: teams,
      authRepository: as('director'),
      now: () => DateTime(2027, 3, 1),
    );
    await pumpEventQueue();
    return f;
  }

  Future<HostedTournamentViewModel> page(String uid, String id) async {
    final vm = HostedTournamentViewModel(
      tournamentId: id,
      tournamentRepository: repo,
      teamRepository: teams,
      authRepository: as(uid),
      now: () => DateTime(2027, 4, 10),
    );
    await pumpEventQueue();
    return vm;
  }

  Future<PlayerSignupsViewModel> signups(
    String uid,
    String id, {
    bool manager = false,
  }) async {
    final vm = PlayerSignupsViewModel(
      tournamentId: id,
      tournamentRepository: repo,
      authRepository: as(uid),
      manager: manager,
    );
    await pumpEventQueue();
    return vm;
  }

  /// A hat tournament with a $20 entry fee and one 4v4 mixed division,
  /// open for signups.
  Future<String> hostHat() async {
    final f = await form();
    f.setEntryType(TournamentEntryType.players);
    f.name = 'Hat Day';
    f.setHasFee(true);
    f.feeAmount = '20';
    f.feeInstructions = 'Venmo @host';
    f.setFeeDue(DateTime(2027, 4, 1));
    f.setFieldSize(4);
    f.setFormat(f.format.copyWith(maxTeams: 8));
    await f.save.execute();
    final id = (f.save.result as Ok<String>).value;
    f.dispose();
    final vm = await page('director', id);
    await vm.setStatus.execute(HostedStatus.registration);
    await pumpEventQueue();
    vm.dispose();
    return id;
  }

  group('the form', () {
    test('a hat tournament is a tournament where players sign up', () async {
      final id = await hostHat();
      final t = repo.tournaments[id]!;
      expect(t.kind, HostedKind.tournament);
      expect(t.takesPlayers, isTrue);
      expect(t.isHat, isTrue);
      expect(t.season, isNull);
      expect(t.entryFee!.label, r'$20');
      final d = repo.divisions[id]!.values.single;
      expect(d.settings.playersOnField, 4);
    });

    test('a league keeps its season and works out its last night', () async {
      final f = await form();
      expect(f.feeName, 'Bid fee');
      f.setKind(HostedKind.league);
      f.name = 'Thursday Night';
      f.setFirstNight(DateTime(2027, 6, 3));
      f.setSeason(
        const LeagueSeason(weeks: 8, playoffWeeks: 2, playoffTeams: 4),
      );
      expect(f.endsOn, DateTime(2027, 7, 22));
      expect(f.problem, isNull);
      await f.save.execute();
      final t = repo.tournaments[(f.save.result as Ok<String>).value]!;
      expect(t.isLeague, isTrue);
      expect(t.takesPlayers, isFalse);
      expect(t.season!.weeks, 8);
      expect(t.season!.playoffTeams, 4);
      expect(t.startsOn, DateTime(2027, 6, 3));
      expect(t.endsOn, DateTime(2027, 7, 22));
      f.dispose();
    });

    test('skipped weeks push the last night out', () async {
      final f = await form();
      f.setKind(HostedKind.league);
      f.setFirstNight(DateTime(2027, 6, 3));
      f.setSeason(
        LeagueSeason(
          weeks: 4,
          playoffWeeks: 0,
          playoffTeams: 0,
          skipDates: [DateTime(2027, 6, 17)],
        ),
      );
      expect(f.endsOn, DateTime(2027, 7, 1));
      f.dispose();
    });

    test(
      'the playoffs need a week and the regular season needs one too',
      () async {
        final f = await form();
        f.setKind(HostedKind.league);
        f.name = 'League';
        f.setSeason(
          const LeagueSeason(weeks: 3, playoffWeeks: 0, playoffTeams: 4),
        );
        expect(f.problem, contains('playoffs'));
        f.setSeason(
          const LeagueSeason(weeks: 3, playoffWeeks: 3, playoffTeams: 4),
        );
        expect(f.problem, contains('regular season'));
        f.setSeason(
          const LeagueSeason(weeks: 3, playoffWeeks: 1, playoffTeams: 4),
        );
        expect(f.problem, isNull);
        f.dispose();
      },
    );

    test(
      'the type is fixed once it exists, and a tournament has no season',
      () async {
        final id = await hostHat();
        final f = await form(tournamentId: id);
        expect(f.isNew, isFalse);
        f.setKind(HostedKind.league);
        f.setEntryType(TournamentEntryType.teams);
        expect(f.kind, HostedKind.tournament);
        expect(f.takesPlayers, isTrue);
        f.name = 'Hat Day 2';
        await f.save.execute();
        expect(repo.tournaments[id]!.name, 'Hat Day 2');
        expect(repo.tournaments[id]!.season, isNull);
        f.dispose();
      },
    );

    test(
      'a league that switches back to a tournament gets weekend dates',
      () async {
        final f = await form();
        f.setKind(HostedKind.league);
        f.setFirstNight(DateTime(2027, 6, 3));
        f.setKind(HostedKind.tournament);
        expect(f.endsOn, DateTime(2027, 6, 4));
        f.dispose();
      },
    );
  });

  group('player signups', () {
    test('a player signs up; the host accepts and marks them paid', () async {
      final id = await hostHat();
      final pat = await signups('pat', id);
      final host = await signups('director', id, manager: true);
      final division = repo.divisions[id]!.keys.single;

      expect(pat.isSignedUp, isFalse);
      await pat.signUp.execute((
        divisionId: division,
        skill: 4,
        gender: GenderMatch.wmp,
      ));
      await pumpEventQueue();
      expect(pat.isSignedUp, isTrue);
      expect(pat.mine!.status, SignupStatus.applied);
      expect(pat.mine!.name, 'Player pat');
      expect(host.signups.single.skill, 4);
      expect(host.signups.single.gender, GenderMatch.wmp);
      // Players only see their own.
      expect(pat.signups, isEmpty);

      await host.decide.execute((uid: 'pat', status: SignupStatus.accepted));
      await pumpEventQueue();
      expect(pat.mine!.status, SignupStatus.accepted);
      expect(host.acceptedIn(division), hasLength(1));

      expect(host.unpaidCount(repo.tournaments[id]!.entryFee), 1);
      expect(pat.isPaid('pat'), isFalse);
      await host.setPaid.execute((uid: 'pat', paid: true));
      await pumpEventQueue();
      expect(host.isPaid('pat'), isTrue);
      expect(pat.isPaid('pat'), isTrue);
      expect(host.unpaidCount(repo.tournaments[id]!.entryFee), 0);
      pat.dispose();
      host.dispose();
    });

    test('unpaid players past the due date are overdue', () async {
      final id = await hostHat();
      final host = await signups('director', id, manager: true);
      final fee = repo.tournaments[id]!.entryFee;
      expect(host.isOverdue('pat', fee, DateTime(2027, 3, 20)), isFalse);
      expect(host.isOverdue('pat', fee, DateTime(2027, 4, 5)), isTrue);
      await host.setPaid.execute((uid: 'pat', paid: true));
      await pumpEventQueue();
      expect(host.isOverdue('pat', fee, DateTime(2027, 4, 5)), isFalse);
      expect(host.isOverdue('pat', null, DateTime(2027, 4, 5)), isFalse);
      host.dispose();
    });

    test(
      'editing keeps the status; withdrawing and signing up again starts over',
      () async {
        final id = await hostHat();
        final pat = await signups('pat', id);
        final host = await signups('director', id, manager: true);
        final division = repo.divisions[id]!.keys.single;
        await pat.signUp.execute((
          divisionId: division,
          skill: 3,
          gender: null,
        ));
        await host.decide.execute((uid: 'pat', status: SignupStatus.accepted));
        await pumpEventQueue();

        await pat.signUp.execute((
          divisionId: division,
          skill: 5,
          gender: null,
        ));
        await pumpEventQueue();
        expect(pat.mine!.skill, 5);
        expect(pat.mine!.status, SignupStatus.accepted);

        await pat.withdraw.execute();
        await pumpEventQueue();
        expect(pat.isSignedUp, isFalse);
        expect(pat.mine!.status, SignupStatus.withdrawn);

        await pat.signUp.execute((
          divisionId: division,
          skill: 5,
          gender: null,
        ));
        await pumpEventQueue();
        expect(pat.mine!.status, SignupStatus.applied);
        pat.dispose();
        host.dispose();
      },
    );

    test('only the host decides and marks paid', () async {
      final id = await hostHat();
      final pat = await signups('pat', id);
      final division = repo.divisions[id]!.keys.single;
      await pat.signUp.execute((divisionId: division, skill: 3, gender: null));
      await pat.decide.execute((uid: 'pat', status: SignupStatus.accepted));
      expect(pat.decide.error, isTrue);
      await pat.setPaid.execute((uid: 'pat', paid: true));
      expect(pat.setPaid.error, isTrue);
      expect(repo.signups[id]!['pat']!.status, SignupStatus.applied);
      pat.dispose();
    });

    test('the answers are checked', () async {
      final id = await hostHat();
      final pat = await signups('pat', id);
      await pat.signUp.execute((divisionId: '', skill: 3, gender: null));
      expect(pat.signUp.error, isTrue);
      await pat.signUp.execute((divisionId: 'd', skill: 9, gender: null));
      expect(pat.signUp.error, isTrue);
      expect(repo.signups[id], isNull);
      pat.dispose();
    });

    test('a manager who loads late starts reading everyone', () async {
      final id = await hostHat();
      final pat = await signups('pat', id);
      final host = await signups('director', id);
      final division = repo.divisions[id]!.keys.single;
      await pat.signUp.execute((divisionId: division, skill: 3, gender: null));
      await pumpEventQueue();
      expect(host.signups, isEmpty);
      host.setManager(true);
      await pumpEventQueue();
      expect(host.signups, hasLength(1));
      host.setManager(false);
      expect(host.signups, isEmpty);
      pat.dispose();
      host.dispose();
    });

    test("a signup's name is never their email", () async {
      final id = await hostHat();
      final division = repo.divisions[id]!.keys.single;
      final bare = PlayerSignupsViewModel(
        tournamentId: id,
        tournamentRepository: repo,
        authRepository: FakeAuthRepository(
          user: const AppUser(uid: 'e1', email: 'secret@example.com'),
        ),
      );
      await pumpEventQueue();
      await bare.signUp.execute((divisionId: division, skill: 3, gender: null));
      expect(repo.signups[id]!['e1']!.name, 'Player');
      final named = PlayerSignupsViewModel(
        tournamentId: id,
        tournamentRepository: repo,
        authRepository: FakeAuthRepository(
          user: const AppUser(
            uid: 'e2',
            email: 'x@example.com',
            username: 'frisbee_fan',
          ),
        ),
      );
      await pumpEventQueue();
      await named.signUp.execute((
        divisionId: division,
        skill: 3,
        gender: null,
      ));
      expect(repo.signups[id]!['e2']!.name, 'frisbee_fan');
      bare.dispose();
      named.dispose();
    });

    test('team applications are refused for player entry', () async {
      final id = await hostHat();
      teams.teams['t1'] = Team(
        id: 't1',
        name: 'Team t1',
        division: Division.mixed,
        level: CompetitionLevel.club,
        ownerId: 'cap1',
        members: {'cap1': TeamRole.owner},
      );
      final vm = await page('cap1', id);
      expect(vm.canApply, isFalse);
      await vm.apply.execute((
        teamId: 't1',
        divisionId: vm.divisions.single.id,
        captainIds: ['cap1'],
      ));
      expect(vm.apply.error, isTrue);
      expect(repo.entries[id], isNull);
      vm.dispose();
    });
  });

  group('the draft', () {
    /// Twelve accepted players: six MMP and six WMP, skill 1-5 around.
    Future<String> withPlayers({int count = 12}) async {
      final id = await hostHat();
      final division = repo.divisions[id]!.keys.single;
      for (var i = 0; i < count; i++) {
        repo.signups.putIfAbsent(id, () => {})['p$i'] = PlayerSignup(
          uid: 'p$i',
          name: 'Player $i',
          divisionId: division,
          skill: 1 + i % 5,
          gender: i.isEven ? GenderMatch.mmp : GenderMatch.wmp,
          status: SignupStatus.accepted,
        );
      }
      return id;
    }

    Future<TeamDraftViewModel> draftPage(String id) async {
      final division = repo.divisions[id]!.keys.single;
      final vm = TeamDraftViewModel(
        tournamentId: id,
        divisionId: division,
        tournamentRepository: repo,
        seed: 1,
      );
      await pumpEventQueue();
      return vm;
    }

    test('deals even teams from the accepted players', () async {
      final id = await withPlayers();
      repo.signups[id]!['late'] = const PlayerSignup(
        uid: 'late',
        name: 'Late',
        divisionId: 'x',
        status: SignupStatus.applied,
      );
      final vm = await draftPage(id);
      expect(vm.loaded, isTrue);
      expect(vm.mixed, isTrue);
      expect(vm.players, hasLength(12));
      expect(vm.suggestedTeamCount, 2);
      expect(vm.teams, isEmpty);

      vm.setTeamCount(3);
      expect(vm.teams, hasLength(3));
      await vm.draft.execute();
      expect(vm.teams.map((t) => t.playerIds.length), [4, 4, 4]);
      expect(vm.unassigned, isEmpty);
      expect(vm.dirty, isTrue);
      for (final t in vm.teams) {
        expect(t.captainId, isNotNull);
        expect(t.playerIds, contains(t.captainId));
      }
      // Each team gets two of each gender match.
      for (final t in vm.teams) {
        final mmp = t.playerIds.where(
          (id) => vm.signupOf(id)!.gender == GenderMatch.mmp,
        );
        expect(mmp, hasLength(2));
      }
      vm.dispose();
    });

    test('shuffling deals again with a different mix', () async {
      final id = await withPlayers(count: 20);
      final vm = await draftPage(id);
      vm.setTeamCount(2);
      await vm.draft.execute();
      final first = [for (final t in vm.teams) t.playerIds.toList()];
      var changed = false;
      for (var i = 0; i < 8 && !changed; i++) {
        await vm.reshuffle.execute();
        changed =
            first.toString() !=
            [for (final t in vm.teams) t.playerIds.toList()].toString();
      }
      expect(changed, isTrue);
      vm.dispose();
    });

    test('the host moves players, renames teams and picks captains', () async {
      final id = await withPlayers(count: 8);
      final vm = await draftPage(id);
      vm.setTeamCount(2);
      await vm.draft.execute();
      final red = vm.teams.first;
      final blue = vm.teams.last;
      final mover = red.playerIds.last;

      vm.movePlayer(mover, teamId: blue.id);
      expect(vm.teams.last.playerIds, contains(mover));
      expect(vm.teams.first.playerIds, isNot(contains(mover)));

      vm.movePlayer(mover, teamId: null);
      expect(vm.unassigned.map((p) => p.uid), [mover]);

      vm.rename(red.id, 'Reds');
      expect(vm.teams.first.name, 'Reds');
      final other = vm.teams.first.playerIds.last;
      vm.setCaptain(red.id, other);
      expect(vm.teams.first.captainId, other);
      // A captain has to be on the team.
      vm.setCaptain(red.id, 'nobody');
      expect(vm.teams.first.captainId, other);

      vm.setTeamCount(3);
      expect(vm.teams, hasLength(3));
      vm.setTeamCount(2);
      expect(vm.teams, hasLength(2));
      vm.dispose();
    });

    test('saving writes the teams, seeds and captains', () async {
      final id = await withPlayers();
      final vm = await draftPage(id);
      vm.setTeamCount(3);
      await vm.draft.execute();
      vm.rename(vm.teams.first.id, 'Reds');
      await vm.save.execute();
      expect(vm.save.completed, isTrue);
      expect(vm.dirty, isFalse);
      final d = repo.divisions[id]!.values.single;
      expect(d.teams, hasLength(3));
      expect(d.seeds, [for (final t in d.teams) t.id]);
      expect(d.captains.keys, d.seeds);
      expect(d.captains[d.teams.first.id], [d.teams.first.captainId]);
      expect(d.teams.first.name, 'Reds');
      // Coming back to it shows the saved teams.
      final again = await draftPage(id);
      expect(again.teams.map((t) => t.name), contains('Reds'));
      expect(again.teamCount, 3);
      again.dispose();
      vm.dispose();
    });

    test('saving checks the teams', () async {
      final id = await withPlayers(count: 6);
      final vm = await draftPage(id);
      await vm.save.execute();
      expect(vm.save.error, isTrue);

      vm.setTeamCount(2);
      await vm.save.execute();
      expect(
        (vm.save.result as Error).error.toString(),
        contains('no players'),
      );

      await vm.draft.execute();
      vm.rename(vm.teams.first.id, 'Same');
      vm.rename(vm.teams.last.id, 'same');
      await vm.save.execute();
      expect((vm.save.result as Error).error.toString(), contains('different'));

      vm.rename(vm.teams.last.id, 'Other');
      await vm.save.execute();
      expect(vm.save.completed, isTrue);
      vm.dispose();
    });

    test('too few players to deal', () async {
      final id = await withPlayers(count: 1);
      final vm = await draftPage(id);
      await vm.draft.execute();
      expect(vm.draft.error, isTrue);
      vm.dispose();
    });

    test('people who are no longer accepted are flagged and dropped', () async {
      final id = await withPlayers(count: 6);
      final vm = await draftPage(id);
      vm.setTeamCount(2);
      await vm.draft.execute();
      await vm.save.execute();
      repo.signups[id]!['p0'] = repo.signups[id]!['p0']!.copyWith(
        status: SignupStatus.withdrawn,
      );
      await repo.setSignupStatus(id, 'p1', SignupStatus.declined);
      await pumpEventQueue();
      expect(vm.staleIds, unorderedEquals(['p0', 'p1']));
      vm.removeStale();
      expect(vm.staleIds, isEmpty);
      expect([for (final t in vm.teams) ...t.playerIds], hasLength(4));
      vm.dispose();
    });

    test(
      'once the schedule is out teams can be adjusted, not added or removed',
      () async {
        final id = await withPlayers(count: 12);
        final first = await draftPage(id);
        first.setTeamCount(4);
        await first.draft.execute();
        await first.save.execute();
        first.dispose();
        final host = await page('director', id);
        await host.publish.execute();
        await pumpEventQueue();
        expect(host.isPublished, isTrue);
        host.dispose();

        final vm = await draftPage(id);
        expect(vm.locked, isTrue);
        final ids = [for (final t in vm.teams) t.id];
        vm.setTeamCount(2);
        expect(vm.teams, hasLength(4));
        await vm.draft.execute();
        expect(vm.draft.error, isTrue);
        await vm.reshuffle.execute();
        expect(vm.reshuffle.error, isTrue);
        expect(vm.teams.map((t) => t.id), ids);

        // Moving a player, renaming and a new captain still save.
        final from = vm.teams.first;
        final to = vm.teams.last;
        final moved = from.playerIds.last;
        vm.movePlayer(moved, teamId: to.id);
        vm.rename(from.id, 'Renamed');
        vm.setCaptain(to.id, moved);
        await vm.save.execute();
        expect(vm.save.completed, isTrue);
        final d = repo.divisions[id]!.values.single;
        expect(d.seeds, ids);
        expect(d.teams.last.playerIds, contains(moved));
        expect(d.teams.first.name, 'Renamed');
        expect(d.captains[to.id], [moved]);
        expect(repo.games.values.single, isNotEmpty);
        vm.dispose();
      },
    );

    test(
      'drafted teams play: the schedule uses them and captains report',
      () async {
        final id = await withPlayers(count: 12);
        final draft = await draftPage(id);
        draft.setTeamCount(4);
        await draft.draft.execute();
        await draft.save.execute();
        final names = [for (final t in draft.teams) t.name];
        final captains = {for (final t in draft.teams) t.id: t.captainId!};
        draft.dispose();

        final host = await page('director', id);
        expect(host.division!.seeds, hasLength(4));
        expect(host.teamName(host.division!.seeds.first), names.first);
        final (:plan, :problem) = host.preview();
        expect(problem, isNull);
        await host.publish.execute();
        await pumpEventQueue();
        expect(host.publish.completed, isTrue);
        expect(host.games, isNotEmpty);
        final game = host.games.firstWhere((g) => g.hasTeams);

        final cap = await page(captains[game.teamA]!, id);
        expect(cap.actionFor(game), HostedGameAction.report);
        final outsider = await page('nobody', id);
        expect(outsider.actionFor(game), isNull);
        expect(plan!.games, isNotEmpty);
        cap.dispose();
        outsider.dispose();
        host.dispose();
      },
    );
  });

  group('leagues', () {
    Future<String> hostLeague({LeagueSeason? season}) async {
      final f = await form();
      f.setKind(HostedKind.league);
      f.name = 'Thursday Night';
      f.setFirstNight(DateTime(2027, 6, 3));
      f.setSeason(
        season ??
            const LeagueSeason(weeks: 5, playoffWeeks: 1, playoffTeams: 4),
      );
      f.setFieldSize(4);
      f.setFirstGame(18, 30);
      f.setFormat(f.format.copyWith(maxTeams: 8, minRoster: () => 4));
      await f.save.execute();
      final id = (f.save.result as Ok<String>).value;
      f.dispose();
      return id;
    }

    test("a league division's format follows the season", () async {
      final id = await hostLeague();
      expect(
        repo.divisions[id]!.values.single.settings.format,
        TournamentFormat.singleElim,
      );
      final id2 = await hostLeague(
        season: const LeagueSeason(weeks: 4, playoffWeeks: 0, playoffTeams: 0),
      );
      expect(
        repo.divisions[id2]!.values.single.settings.format,
        TournamentFormat.roundRobin,
      );
    });

    test('team-entry leagues check the division minimum roster', () async {
      final id = await hostLeague();
      expect(repo.divisions[id]!.values.single.effectiveMinRoster, 4);
      teams.teams['t1'] = Team(
        id: 't1',
        name: 'Team t1',
        division: Division.mixed,
        level: CompetitionLevel.club,
        ownerId: 'cap1',
        members: {'cap1': TeamRole.owner},
      );
      await repo.setStatus(id, HostedStatus.registration);
      final vm = await page('cap1', id);
      final application = (
        teamId: 't1',
        divisionId: vm.divisions.single.id,
        captainIds: ['cap1'],
      );
      teams.roster['t1'] = [
        for (var i = 0; i < 3; i++) RosterPlayer(id: 'r$i', name: 'Roster $i'),
      ];
      await vm.apply.execute(application);
      expect(
        (vm.apply.result as Error).error,
        isA<RosterTooSmallException>().having(
          (e) => e.toString(),
          'message',
          contains('at least 4 players'),
        ),
      );
      teams.roster['t1'] = [
        ...teams.roster['t1']!,
        const RosterPlayer(id: 'r3', name: 'Roster 3'),
      ];
      await vm.apply.execute(application);
      expect(vm.apply.completed, isTrue);
      vm.dispose();
    });

    test(
      "a division saved before the season changed still publishes right",
      () async {
        final id = await hostLeague();
        // The host drops the playoffs after the division was saved.
        final t = repo.tournaments[id]!;
        repo.tournaments[id] = t.copyWith(
          season: () =>
              const LeagueSeason(weeks: 4, playoffWeeks: 0, playoffTeams: 0),
        );
        final host = await page('director', id);
        expect(
          host.division!.settings.format,
          TournamentFormat.singleElim,
          reason: 'the stored format is stale',
        );
        expect(host.formatOf(host.division!), TournamentFormat.roundRobin);
        await repo.saveDivision(
          host.tournament!,
          host.division!.copyWith(seeds: ['a', 'b', 'c', 'd']),
        );
        await pumpEventQueue();
        await host.publish.execute();
        await pumpEventQueue();
        expect(
          repo.divisions[id]!.values.single.settings.format,
          TournamentFormat.roundRobin,
        );
        expect(host.games.every((g) => g.stage.name == 'pool'), isTrue);
        host.dispose();
      },
    );

    test(
      'new divisions play the event format: a day event, or weekly evenings',
      () async {
        final tid = await hostHat();
        final hat = await page('director', tid);
        final d = hat.newDivision();
        expect(d.settings.playersOnField, 4);
        expect(d.settings.startsAt.hour, 9);
        hat.dispose();
        final lid = await hostLeague();
        final league = await page('director', lid);
        final l = league.newDivision();
        expect(l.level, CompetitionLevel.league);
        expect(l.settings.startsAt, DateTime(2027, 6, 3, 18, 30));
        expect(l.settings.format, TournamentFormat.singleElim);
        expect(l.settings.laterDays, isEmpty);
        league.dispose();
      },
    );

    test('publishing a league schedules its weekly season', () async {
      final id = await hostLeague();
      final host = await page('director', id);
      // Four teams enter and are accepted, as they would by applying.
      final division = host.division!;
      await repo.saveDivision(
        host.tournament!,
        division.copyWith(seeds: ['a', 'b', 'c', 'd']),
      );
      await pumpEventQueue();
      final (:plan, :problem) = host.preview();
      expect(problem, isNull);
      // Four weeks of regular season plus one of playoffs.
      expect(plan!.days, hasLength(5));
      expect(plan.games.first.label, 'Week 1');
      expect(plan.games.first.startsAt, DateTime(2027, 6, 3, 18, 30));
      expect(plan.games.last.label, 'Final');
      await host.publish.execute();
      await pumpEventQueue();
      expect(host.games.length, plan.games.length);
      expect(host.tournament!.status, HostedStatus.scheduled);
      host.dispose();
    });
  });

  group('a league where players sign up', () {
    /// A player league with 8 accepted players drafted into 2 saved teams.
    Future<String> draftedLeague() async {
      final f = await form();
      f.setKind(HostedKind.league);
      f.setEntryType(TournamentEntryType.players);
      f.name = 'Thursday Night';
      f.setFirstNight(DateTime(2027, 6, 3));
      f.setSeason(
        const LeagueSeason(weeks: 4, playoffWeeks: 1, playoffTeams: 2),
      );
      await f.save.execute();
      final id = (f.save.result as Ok<String>).value;
      f.dispose();
      final host = await page('director', id);
      await host.saveDivision.execute(
        host.newDivision().copyWith(
          settings: host.newDivision().settings.copyWith(playersOnField: 4),
          maxTeams: 4,
        ),
      );
      await host.setStatus.execute(HostedStatus.registration);
      await pumpEventQueue();
      host.dispose();
      final division = repo.divisions[id]!.keys.single;
      for (var i = 0; i < 8; i++) {
        repo.signups.putIfAbsent(id, () => {})['p$i'] = PlayerSignup(
          uid: 'p$i',
          name: 'Player $i',
          divisionId: division,
          skill: 1 + i % 5,
          status: SignupStatus.accepted,
        );
      }
      final draft = TeamDraftViewModel(
        tournamentId: id,
        divisionId: division,
        tournamentRepository: repo,
        seed: 3,
      );
      await pumpEventQueue();
      draft.setTeamCount(2);
      await draft.draft.execute();
      await draft.save.execute();
      expect(draft.save.completed, isTrue);
      draft.dispose();
      return id;
    }

    test('the schedule waits until the teams are made', () async {
      final id = await draftedLeague();
      final host = await page('director', id);
      expect(host.needsTeamsCreated, isTrue);
      final (:plan, :problem) = host.preview();
      expect(plan, isNull);
      expect(problem, contains('Create the league'));
      await host.publish.execute();
      expect(host.publish.error, isTrue);
      expect(repo.games, isEmpty);
      host.dispose();
    });

    test('creating teams gives them real ids, entries and captains', () async {
      final id = await draftedLeague();
      final before = repo.divisions[id]!.values.single;
      final names = [for (final t in before.teams) t.name];
      final host = await page('director', id);
      await host.createTeams.execute(before.id);
      await pumpEventQueue();
      expect(host.createTeams.completed, isTrue);

      final d = host.division!;
      expect(d.teamsCreated, isTrue);
      expect(d.teams.map((t) => t.name), names);
      expect(
        d.teams.map((t) => t.id),
        everyElement(startsWith(TournamentDivision.leagueTeamPrefix)),
      );
      expect(d.seeds, [for (final t in d.teams) t.id]);
      expect(d.captains.keys, d.seeds);
      for (final t in d.teams) {
        final entry = repo.entries[id]![t.id]!;
        expect(entry.status, EntryStatus.accepted);
        expect(entry.captainIds, [t.captainId]);
        expect(host.teamName(t.id), t.name);
      }
      // Now the schedule can be published, and by the real ids.
      expect(host.needsTeamsCreated, isFalse);
      await host.publish.execute();
      await pumpEventQueue();
      expect(host.publish.completed, isTrue);
      expect(
        host.games.expand((g) => [g.teamA, g.teamB]).whereType<String>(),
        everyElement(startsWith(TournamentDivision.leagueTeamPrefix)),
      );
      // Once the schedule is out, the teams can't be made again.
      await host.createTeams.execute(d.id);
      expect(host.createTeams.error, isTrue);
      host.dispose();
    });

    test('creating twice before publishing is harmless', () async {
      final id = await draftedLeague();
      final host = await page('director', id);
      final division = repo.divisions[id]!.keys.single;
      await host.createTeams.execute(division);
      final first = repo.divisions[id]!.values.single.seeds;
      await host.createTeams.execute(division);
      expect(host.createTeams.completed, isTrue);
      expect(repo.divisions[id]!.values.single.seeds, first);
      host.dispose();
    });

    test(
      'only the host, only leagues, only drafted teams, and the server can refuse',
      () async {
        final id = await draftedLeague();
        final division = repo.divisions[id]!.keys.single;
        final player = await page('p1', id);
        await player.createTeams.execute(division);
        expect(player.createTeams.error, isTrue);
        expect(repo.divisions[id]!.values.single.teamsCreated, isFalse);
        player.dispose();

        final host = await page('director', id);
        repo.createTeamsError = Exception('A player is on more than one team.');
        await host.createTeams.execute(division);
        expect(
          (host.createTeams.result as Error).error.toString(),
          contains('more than one'),
        );
        repo.createTeamsError = null;

        await repo.saveDraftTeams(id, host.division!, const []);
        await pumpEventQueue();
        await host.createTeams.execute(division);
        expect(
          (host.createTeams.result as Error).error.toString(),
          contains('at least two'),
        );
        host.dispose();

        final hat = await hostHat();
        final hatHost = await page('director', hat);
        await hatHost.createTeams.execute(repo.divisions[hat]!.keys.single);
        expect(hatHost.createTeams.error, isTrue);
        hatHost.dispose();
      },
    );

    test('the draft is read-only once the teams are made', () async {
      final id = await draftedLeague();
      final division = repo.divisions[id]!.keys.single;
      final host = await page('director', id);
      await host.createTeams.execute(division);
      await pumpEventQueue();
      host.dispose();

      final draft = TeamDraftViewModel(
        tournamentId: id,
        divisionId: division,
        tournamentRepository: repo,
      );
      await pumpEventQueue();
      expect(draft.created, isTrue);
      final ids = [for (final t in draft.teams) t.id];
      draft.setTeamCount(3);
      draft.rename(ids.first, 'Nope');
      draft.movePlayer(draft.teams.first.playerIds.first, teamId: null);
      expect(draft.teams.map((t) => t.id), ids);
      expect(draft.teams.first.name, isNot('Nope'));
      expect(draft.unassigned, isEmpty);
      await draft.draft.execute();
      expect(draft.draft.error, isTrue);
      await draft.save.execute();
      expect(draft.save.error, isTrue);
      draft.dispose();
    });

    testWidgets('the host makes the teams from the Players tab', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final id = await tester.runAsync(draftedLeague);
      final vm = await tester.runAsync(() => page('director', id!));
      final sign = await tester.runAsync(
        () => signups('director', id!, manager: true),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: HostedTournamentScreen(viewModel: vm!, signups: sign),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('League'), findsOneWidget);
      expect(find.text('Players sign up · balanced teams'), findsOneWidget);
      await tester.tap(find.text('Players'));
      await tester.pumpAndSettle();
      expect(find.text('Make the teams'), findsOneWidget);

      await tester.tap(find.text('Create teams'));
      await tester.pumpAndSettle();
      expect(find.text('Create 2 teams?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Create teams').last);
      await tester.pumpAndSettle();
      expect(find.text('Make the teams'), findsNothing);
      expect(find.textContaining('These are real teams'), findsOneWidget);
      expect(find.text('View teams'), findsOneWidget);
      expect(repo.divisions[id]!.values.single.teamsCreated, isTrue);
      await tester.pumpWidget(const SizedBox());
      vm.dispose();
      sign!.dispose();
    });
  });

  group('the page', () {
    testWidgets('players see a signup card and sign up', (tester) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final id = await tester.runAsync(hostHat);
      final vm = await tester.runAsync(() => page('pat', id!));
      final sign = await tester.runAsync(() => signups('pat', id!));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: HostedTournamentScreen(viewModel: vm!, signups: sign),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Hat tournament'), findsOneWidget);
      expect(find.text('Players'), findsOneWidget);
      expect(find.text('Teams'), findsNothing);
      expect(find.textContaining(r'$20 per player'), findsOneWidget);
      expect(find.text('Sign up to play'), findsOneWidget);
      expect(find.text(r'Sign up · $20'), findsOneWidget);
      expect(find.text('Apply with a team'), findsNothing);

      await tester.tap(find.text(r'Sign up · $20'));
      await tester.pumpAndSettle();
      expect(find.text('Your skill: 3 of 5'), findsOneWidget);
      expect(find.text('Gender match'), findsOneWidget);
      await tester.tap(find.text('WMP'));
      await tester.tap(find.text('Sign up').last);
      await tester.pumpAndSettle();
      expect(find.text('Your signup'), findsOneWidget);
      expect(find.text('Signed up'), findsOneWidget);
      expect(repo.signups[id]!['pat']!.gender, GenderMatch.wmp);
      expect(find.textContaining('Entry fee \$20 to pay'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      vm.dispose();
      sign!.dispose();
    });

    testWidgets("the host's Players tab lists signups with paid switches", (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final id = await tester.runAsync(hostHat);
      final division = repo.divisions[id]!.keys.single;
      repo.signups[id!] = {
        'p1': PlayerSignup(
          uid: 'p1',
          name: 'Pat Jones',
          divisionId: division,
          skill: 4,
          gender: GenderMatch.mmp,
          status: SignupStatus.accepted,
        ),
        'p2': PlayerSignup(
          uid: 'p2',
          name: 'Sam Lee',
          divisionId: division,
          skill: 2,
        ),
      };
      final vm = await tester.runAsync(() => page('director', id));
      final sign = await tester.runAsync(
        () => signups('director', id, manager: true),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: HostedTournamentScreen(viewModel: vm!, signups: sign),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Players'));
      await tester.pumpAndSettle();
      expect(find.text('Pat Jones'), findsOneWidget);
      expect(find.text('Sam Lee'), findsOneWidget);
      expect(find.textContaining('2 signed up · 1 accepted'), findsOneWidget);
      expect(find.text('Draft teams'), findsOneWidget);
      // Organisers play too.
      expect(find.text('Play in Hat Day'), findsOneWidget);
      expect(find.byType(Switch), findsNWidgets(2));

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(repo.payments[id]!['p1']!.paid, isTrue);
      expect(find.textContaining('Unpaid (1)'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      vm.dispose();
      sign!.dispose();
    });
  });

  group('players sign up and teams reserve spots', () {
    /// A 3v3 league: players pay $20 to sign up, teams $60 a spot, and a
    /// team needs 4 players.
    Future<String> hostMixed() async {
      final f = await form();
      f.setKind(HostedKind.league);
      f.setEntryType(TournamentEntryType.players);
      f.setTeamEntry(true);
      f.name = 'Mini League';
      f.setFieldSize(3);
      f.setFormat(f.format.copyWith(minRoster: () => 4, maxTeams: 6));
      f.setHasFee(true);
      f.feeAmount = '20';
      expect(f.problem, 'Enter the team spot fee, e.g. 300.');
      f.teamFeeAmount = '60';
      expect(f.problem, isNull);
      await f.save.execute();
      final id = (f.save.result as Ok<String>).value;
      f.dispose();
      final vm = await page('director', id);
      await vm.setStatus.execute(HostedStatus.registration);
      await pumpEventQueue();
      vm.dispose();
      return id;
    }

    test('the event keeps both fees and takes both', () async {
      final t = repo.tournaments[await hostMixed()]!;
      expect(t.takesPlayers, isTrue);
      expect(t.takesTeams, isTrue);
      expect(t.mixedEntry, isTrue);
      expect(t.isHat, isFalse);
      expect(t.entryFee!.label, r'$20');
      expect(t.spotFee!.label, r'$60');
      expect(eventTabs(t, hasSignups: true), contains(EventTab.players));
      expect(eventTabs(t, hasSignups: true), contains(EventTab.teams));
    });

    test('a captain starts a team and reserves its spot', () async {
      final id = await hostMixed();
      final cap = await page('cap', id);
      expect(cap.canReserve, isTrue);
      final div = cap.divisions.single;
      await cap.reserveSpot.execute((name: 'Reds', divisionId: div.id));
      final made = cap.reserveSpot.result;
      expect(made, isA<Ok<String>>(), reason: '$made');
      final teamId = (made as Ok<String>).value;
      final team = teams.teams[teamId]!;
      expect(team.ownerId, 'cap');
      expect(team.division, div.division);
      expect(team.level, div.level);
      final entry = repo.entries[id]![teamId]!;
      expect(entry.status, EntryStatus.applied);
      expect(entry.captainIds, ['cap']);
      await pumpEventQueue();
      // One of four so far.
      expect(cap.playersShort(teamId), 3);
      expect(cap.myActiveEntry?.teamId, teamId);
      cap.dispose();
    });

    test(
      'a division of only registered teams publishes without a draft',
      () async {
        final id = await hostMixed();
        final div = repo.divisions[id]!.values.single.id;
        for (final cap in ['c1', 'c2']) {
          final vm = await page(cap, id);
          await vm.reserveSpot.execute((name: 'Team $cap', divisionId: div));
          expect(vm.reserveSpot.result, isA<Ok<String>>());
          vm.dispose();
        }
        final host = await page('director', id);
        for (final e in [...repo.entries[id]!.values]) {
          await host.decide.execute((entry: e, status: EntryStatus.accepted));
          await pumpEventQueue();
        }
        await host.setStatus.execute(HostedStatus.seeding);
        await pumpEventQueue();
        expect(host.needsTeamsCreated, isFalse);
        expect(host.seedsOf(div), hasLength(2));
        await host.publish.execute();
        expect(
          host.publish.result,
          isA<Ok<void>>(),
          reason: '${host.publish.result}',
        );
        expect(repo.games.values.expand((g) => g), isNotEmpty);
        host.dispose();
      },
    );

    test('a player on a reserved team is kept from signing up alone', () async {
      final id = await hostMixed();
      final cap = await page('cap', id);
      await cap.reserveSpot.execute((
        name: 'Reds',
        divisionId: cap.divisions.single.id,
      ));
      final teamId = (cap.reserveSpot.result as Ok<String>).value;
      cap.dispose();
      // Pat joins by invite as a player, not an admin.
      final t = teams.teams[teamId]!;
      teams.teams[teamId] = t.copyWith(
        members: {...t.members, 'pat': TeamRole.player},
      );
      final pat = await page('pat', id);
      expect(pat.myEntries, isEmpty);
      expect(pat.myActiveEntry?.teamId, teamId);
      pat.dispose();
    });

    test("a division people signed up for can't be closed", () async {
      final id = await hostMixed();
      final div = repo.divisions[id]!.values.single;
      repo.signups[id] = {
        'pat': PlayerSignup(uid: 'pat', name: 'Pat', divisionId: div.id),
      };
      final f = await form(tournamentId: id);
      expect(f.lockedReason(div.division), 'People have signed up for it.');
      f.setOpen(div.division, false);
      expect(f.isOpen(div.division), isTrue);
      f.dispose();
    });

    test("teams can't reserve spots where only players sign up", () async {
      final id = await hostHat();
      final cap = await page('cap', id);
      expect(cap.canReserve, isFalse);
      await cap.reserveSpot.execute((
        name: 'Reds',
        divisionId: cap.divisions.single.id,
      ));
      expect(cap.reserveSpot.result, isA<Error<String>>());
      cap.dispose();
    });

    test('a drafted team keeps registered teams in the seeds', () {
      final d = TournamentDivision(
        id: 'd',
        division: Division.mixed,
        level: CompetitionLevel.league,
        settings: TournamentSettings(startsAt: DateTime(2027)),
        seeds: const ['reg', 'team1'],
        captains: const {
          'reg': ['c'],
          'team1': ['a'],
        },
        teams: const [TournamentTeam(id: 'team1', name: 'A', captainId: 'a')],
      );
      final next = d.withDrafted(const [
        TournamentTeam(id: 'team1', name: 'A', captainId: 'x'),
        TournamentTeam(id: 'team2', name: 'B', captainId: 'y'),
      ]);
      expect(next.seeds, ['reg', 'team1', 'team2']);
      expect(next.captains, {
        'reg': ['c'],
        'team1': ['x'],
        'team2': ['y'],
      });
      expect(next.registeredSeeds, ['reg']);
    });
  });
}
