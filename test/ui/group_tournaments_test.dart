import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/group_tournament.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/team_event.dart';
import 'package:frisbee_app/domain/tournament_engine/generator.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/group_tournaments/view_models/group_tournament_viewmodel.dart';
import 'package:frisbee_app/ui/group_tournaments/view_models/group_tournaments_viewmodel.dart';
import 'package:frisbee_app/ui/group_tournaments/view_models/tournament_editor_viewmodel.dart';
import 'package:frisbee_app/ui/group_tournaments/widgets/group_tournament_screen.dart';
import 'package:frisbee_app/ui/schedule/view_models/event_detail_viewmodel.dart';

import '../testing/fakes.dart';
import '../testing/group_tournament_fakes.dart';

void main() {
  late FakeTeamRepository teams;
  late FakeEventRepository events;
  late FakeGroupTournamentRepository repo;

  /// Owner "owner" organizes; p1..p8 are members.
  final players = [for (var i = 1; i <= 8; i++) 'p$i'];

  setUp(() {
    teams = FakeTeamRepository();
    events = FakeEventRepository();
    repo = FakeGroupTournamentRepository();
    final members = {
      'owner': TeamRole.owner,
      for (final p in players) p: TeamRole.player,
    };
    teams.teams['g1'] = Team(
      id: 'g1',
      name: 'Sunday Pickup',
      division: Division.mixed,
      level: CompetitionLevel.pickup,
      city: 'Denver',
      ownerId: 'owner',
      members: members,
      memberNames: {for (final uid in members.keys) uid: 'Name $uid'},
      kind: TeamKind.community,
    );
  });

  FakeAuthRepository as(String uid) => FakeAuthRepository(
    user: AppUser(uid: uid, email: '$uid@x.com'),
  );

  /// Four teams of two; team tN's captain is the first player.
  GroupTournament fourTeams(TournamentFormat format) => GroupTournament(
    id: 't1',
    name: 'Fall Hat',
    status: TournamentStatus.scheduled,
    settings: TournamentSettings(
      startsAt: DateTime(2026, 11, 7, 9),
      format: format,
      scoreCap: 11,
    ),
    teams: [
      for (var i = 0; i < 4; i++)
        TournamentTeam(
          id: 'T${i + 1}',
          name: 'Team ${i + 1}',
          captainId: players[i * 2],
          playerIds: [players[i * 2], players[i * 2 + 1]],
          playerNames: {
            players[i * 2]: 'Name ${players[i * 2]}',
            players[i * 2 + 1]: 'Name ${players[i * 2 + 1]}',
          },
        ),
    ],
  );

  void seed(GroupTournament t) {
    repo.tournaments['g1'] = [t];
    repo.games[t.id] = generateSchedule(t).games;
  }

  Future<GroupTournamentViewModel> tournamentVm(String uid) async {
    final vm = GroupTournamentViewModel(
      groupId: 'g1',
      tournamentId: 't1',
      teamRepository: teams,
      tournamentRepository: repo,
      authRepository: as(uid),
    );
    await pumpEventQueue();
    return vm;
  }

  group('editor', () {
    Future<TournamentEditorViewModel> editorVm({String? eventId}) async {
      final vm = TournamentEditorViewModel(
        groupId: 'g1',
        tournamentId: null,
        teamRepository: teams,
        eventRepository: events,
        tournamentRepository: repo,
        authRepository: as('owner'),
        eventId: eventId,
        clock: () => DateTime(2026, 11, 1),
        random: Random(1),
      );
      await pumpEventQueue();
      return vm;
    }

    setUp(() {
      events.events['e1'] = TeamEvent(
        id: 'e1',
        title: 'Fall Hat',
        type: EventType.tournament,
        startsAt: DateTime(2026, 11, 7, 9),
        endsAt: DateTime(2026, 11, 7, 15),
        rsvps: {
          for (final p in players.take(5)) p: RsvpStatus.going,
          'p6': RsvpStatus.maybe,
          'p7': RsvpStatus.notGoing,
          // Left the group since: not imported.
          'gone': RsvpStatus.going,
        },
      );
    });

    test('a linked event names the tournament and sets its times', () async {
      final vm = await editorVm(eventId: 'e1');
      expect(vm.name, 'Fall Hat');
      expect(vm.settings.startsAt, DateTime(2026, 11, 7, 9));
      expect(vm.settings.laterDays, isEmpty);
      expect(vm.settings.idealEndsAt, DateTime(2026, 11, 7, 15));
    });

    test('a multi-day event makes a multi-day tournament', () async {
      events.events['e2'] = TeamEvent(
        id: 'e2',
        title: 'Big Weekend',
        type: EventType.tournament,
        startsAt: DateTime(2026, 11, 7, 9),
        endsAt: DateTime(2026, 11, 8, 16),
      );
      final vm = await editorVm(eventId: 'e2');
      expect(vm.settings.days, [
        DateTime(2026, 11, 7, 9),
        DateTime(2026, 11, 8, 9),
      ]);
    });

    test('dates and per-day start times', () async {
      final vm = await editorVm();
      vm.setDates(DateTime(2026, 11, 7), DateTime(2026, 11, 9));
      expect(vm.settings.days, [
        DateTime(2026, 11, 7, 9),
        DateTime(2026, 11, 8, 9),
        DateTime(2026, 11, 9, 9),
      ]);
      vm.setDayStart(1, hour: 10, minute: 30);
      vm.setDayStart(0, hour: 8, minute: 0);
      expect(vm.settings.days, [
        DateTime(2026, 11, 7, 8),
        DateTime(2026, 11, 8, 10, 30),
        DateTime(2026, 11, 9, 9),
      ]);
      // Shortening keeps the start times already set.
      vm.setDates(DateTime(2026, 11, 7), DateTime(2026, 11, 8));
      expect(vm.settings.days, [
        DateTime(2026, 11, 7, 8),
        DateTime(2026, 11, 8, 10, 30),
      ]);

      vm.setName('Weekend');
      vm.previewSchedule();
      final plan = vm.plan!;
      expect(plan.days, hasLength(2));
      expect(plan.days.map((d) => d.games), [
        (plan.games.length + 1) ~/ 2,
        plan.games.length ~/ 2,
      ]);
      expect(plan.days.last.startsAt, DateTime(2026, 11, 8, 10, 30));
    });

    test('starts with four empty teams and publishes before players', () async {
      final vm = await editorVm();
      expect(vm.teams.map((t) => t.name), [
        'Team 1',
        'Team 2',
        'Team 3',
        'Team 4',
      ]);
      expect(vm.problem, 'Give the tournament a name.');
      vm.setName('Fall Hat');
      vm.setTeamCount(6);
      expect(vm.teams, hasLength(6));
      expect(vm.teams.last.name, 'Team 6');
      expect(vm.problem, isNull);
      expect(vm.todo, '6 teams without players');

      vm.updateSettings(
        vm.settings.copyWith(format: TournamentFormat.roundRobin),
      );
      await vm.publish.execute();
      expect(vm.publish.completed, isTrue);
      final saved = repo.tournaments['g1']!.single;
      expect(saved.status, TournamentStatus.scheduled);
      expect(saved.createdBy, 'owner');
      // Six teams, each pair once.
      expect(repo.games[saved.id], hasLength(15));
    });

    test(
      'players added after publishing are saved without a new schedule',
      () async {
        final first = await editorVm(eventId: 'e1');
        await first.publish.execute();
        final id = repo.tournaments['g1']!.single.id;
        final gamesBefore = repo.games[id];

        final vm = TournamentEditorViewModel(
          groupId: 'g1',
          tournamentId: id,
          teamRepository: teams,
          eventRepository: events,
          tournamentRepository: repo,
          authRepository: as('owner'),
          random: Random(2),
        );
        await pumpEventQueue();
        expect(vm.wasPublished, isTrue);
        vm.importRsvps();
        vm.addToBench((uid: 'p7', name: 'Name p7'));
        vm.assignTeams();
        expect(vm.bench, isEmpty);
        expect(vm.teams.map((t) => t.name), [
          'Team 1',
          'Team 2',
          'Team 3',
          'Team 4',
        ]);
        for (final t in vm.teams) {
          expect(t.playerIds, hasLength(inInclusiveRange(1, 2)));
          expect(t.playerIds, contains(t.captainId));
        }
        expect(vm.teams.expand((t) => t.playerIds).toSet(), hasLength(7));
        expect(vm.todo, isNull);
        await vm.save.execute();
        expect(vm.save.completed, isTrue);
        expect(repo.games[id], same(gamesBefore));
        final saved = repo.tournaments['g1']!.single;
        expect(saved.status, TournamentStatus.scheduled);
        expect(saved.participantIds, hasLength(7));

        // A different number of teams needs a new schedule.
        vm.setTeamCount(5);
        expect(vm.teamsChanged, isTrue);
        expect(vm.saveProblem, contains('publish'));
        await vm.save.execute();
        expect(vm.save.error, isTrue);
        await vm.publish.execute();
        expect(vm.publish.completed, isTrue);
        expect(vm.teamsChanged, isFalse);
      },
    );

    test('saving puts the tournament on the group schedule', () async {
      final vm = await editorVm();
      vm.setName('Winter Hat');
      vm.setDates(DateTime(2026, 11, 14), DateTime(2026, 11, 15));
      await vm.save.execute();
      expect(vm.save.completed, isTrue);
      final created = events.events.values.singleWhere(
        (e) => e.title == 'Winter Hat',
      );
      expect(created.type, EventType.tournament);
      expect(created.startsAt, DateTime(2026, 11, 14, 9));
      // Ends when the last game on the second day should.
      expect(created.endsAt!.day, 15);
      expect(vm.eventId, created.id);
      expect(repo.tournaments['g1']!.single.eventId, created.id);

      // Saving again updates the same event.
      vm.setName('Winter Classic');
      await vm.publish.execute();
      expect(vm.publish.completed, isTrue);
      expect(events.events.values.where((e) => e.title.startsWith('Winter')), [
        isA<TeamEvent>().having((e) => e.title, 'title', 'Winter Classic'),
      ]);
    });

    test('a linked event keeps its RSVPs and follows the times', () async {
      final vm = await editorVm(eventId: 'e1');
      vm.setDayStart(0, hour: 8, minute: 30);
      await vm.save.execute();
      final e = events.events['e1']!;
      expect(e.startsAt, DateTime(2026, 11, 7, 8, 30));
      expect(e.rsvps['p1'], RsvpStatus.going);
      expect(events.events, hasLength(1));
    });

    test('the event page links to its tournament', () async {
      seed(fourTeams(TournamentFormat.roundRobin));
      final t = repo.tournaments['g1']!.single;
      repo.tournaments['g1']![0] = t.copyWith(eventId: () => 'e1');
      EventDetailViewModel detail(String uid) => EventDetailViewModel(
        teamId: 'g1',
        eventId: 'e1',
        eventRepository: events,
        teamRepository: teams,
        authRepository: as(uid),
        tournamentRepository: repo,
      );
      final org = detail('owner');
      final player = detail('p1');
      final outsider = detail('stranger');
      await pumpEventQueue();
      expect(org.tournament?.id, 't1');
      expect(org.canSetUpTournament, isFalse);
      expect(player.tournament?.id, 't1');
      expect(outsider.tournament, isNull);
    });

    test('captains follow players; fewer teams bench their players', () async {
      final vm = await editorVm();
      vm.setName('Hat');
      final a = vm.teams[0].id;
      final b = vm.teams[1].id;
      // The first player on a team captains it until someone else is set.
      vm.movePlayerTo((uid: 'p1', name: 'Name p1'), a);
      vm.movePlayerTo((uid: 'p3', name: 'Name p3'), a);
      expect(vm.teams[0].captainId, 'p1');
      vm.setCaptain(a, 'p3');
      expect(vm.teams[0].captainId, 'p3');
      // Moving the captain away hands it to a teammate.
      vm.movePlayerTo((uid: 'p3', name: 'Name p3'), b);
      expect(vm.teams[0].captainId, 'p1');
      vm.renameTeam(a, '  Discs ');
      expect(vm.teams.first.name, 'Discs');

      vm.movePlayerTo((uid: 'p4', name: 'Name p4'), vm.teams[3].id);
      vm.setTeamCount(3);
      expect(vm.teams, hasLength(3));
      expect(vm.bench.map((p) => p.uid), ['p4']);
      vm.setTeamCount(1);
      expect(vm.teams, hasLength(2));
    });
  });

  group('scores', () {
    setUp(() => seed(fourTeams(TournamentFormat.singleElim)));

    GroupGame game(String id) =>
        repo.games['t1']!.firstWhere((g) => g.id == id);

    test('captain reports, the other confirms, the winner moves on', () async {
      final first = repo.games['t1']!.firstWhere((g) => g.hasTeams);
      final capA = fourTeams(
        TournamentFormat.singleElim,
      ).team(first.teamA)!.captainId!;
      final capB = fourTeams(
        TournamentFormat.singleElim,
      ).team(first.teamB)!.captainId!;
      final a = await tournamentVm(capA);
      final b = await tournamentVm(capB);
      final watcher = await tournamentVm('owner');
      final finalGame = watcher.bracketGames.last;
      expect(
        watcher.slotLabel(finalGame, a: true),
        startsWith('Winner of game'),
      );

      expect(a.actionFor(first), GameAction.report);
      expect(b.actionFor(first), GameAction.report);
      await a.report.execute((gameId: first.id, scoreA: 11, scoreB: 7));
      await pumpEventQueue();
      expect(a.actionFor(game(first.id)), GameAction.awaiting);
      expect(b.actionFor(game(first.id)), GameAction.confirm);

      await b.confirm.execute(game(first.id));
      await pumpEventQueue();
      final done = game(first.id);
      expect(done.isDone, isTrue);
      expect((done.scoreA, done.scoreB), (11, 7));
      expect(b.actionFor(done), isNull);
      final next = repo.games['t1']!.firstWhere(
        (g) =>
            g.id != first.id &&
            (g.teamA == first.teamA || g.teamB == first.teamA),
        orElse: () => throw StateError('winner not advanced'),
      );
      expect(next.stage, GameStage.winners);
    });

    test('a disputing captain re-reports and the first one confirms', () async {
      final first = repo.games['t1']!.firstWhere((g) => g.hasTeams);
      final t = fourTeams(TournamentFormat.singleElim);
      final a = await tournamentVm(t.team(first.teamA)!.captainId!);
      final b = await tournamentVm(t.team(first.teamB)!.captainId!);

      await a.report.execute((gameId: first.id, scoreA: 11, scoreB: 7));
      await pumpEventQueue();
      await b.report.execute((gameId: first.id, scoreA: 9, scoreB: 11));
      await pumpEventQueue();
      expect(game(first.id).report!.byTeamId, first.teamB);
      expect(a.actionFor(game(first.id)), GameAction.confirm);
      await a.confirm.execute(game(first.id));
      await pumpEventQueue();
      expect(game(first.id).winner, first.teamB);
    });

    test('only captains report; ties are refused', () async {
      final first = repo.games['t1']!.firstWhere((g) => g.hasTeams);
      final t = fourTeams(TournamentFormat.singleElim);
      final notCaptain = t.team(first.teamA)!.playerIds.last;
      final player = await tournamentVm(notCaptain);
      expect(player.actionFor(first), isNull);
      expect(player.canSetScore(first), isFalse);
      await player.report.execute((gameId: first.id, scoreA: 11, scoreB: 3));
      expect(player.report.error, isTrue);

      final cap = await tournamentVm(t.team(first.teamA)!.captainId!);
      await cap.report.execute((gameId: first.id, scoreA: 5, scoreB: 5));
      expect(cap.report.error, isTrue);
      expect(repo.log, isEmpty);
    });

    test('organizers set a final score and the bracket moves on', () async {
      final org = await tournamentVm('owner');
      final firsts = [
        for (final g in repo.games['t1']!)
          if (g.hasTeams) g,
      ];
      for (final g in firsts) {
        expect(org.canSetScore(g), isTrue);
        await org.setFinalScore.execute((gameId: g.id, scoreA: 11, scoreB: 4));
        await pumpEventQueue();
      }
      final last = org.bracketGames.last;
      expect(last.teamA, isNotNull);
      expect(last.teamB, isNotNull);
      // Results the final depends on can't change once it's played.
      await org.setFinalScore.execute((gameId: last.id, scoreA: 11, scoreB: 9));
      await pumpEventQueue();
      expect(org.championId, game(last.id).winner);
      expect(org.canSetScore(game(firsts.first.id)), isFalse);
    });
  });

  test('pool play: organizers seed the bracket once pools finish', () async {
    seed(fourTeams(TournamentFormat.poolsSingleElim));
    final org = await tournamentVm('owner');
    expect(org.canSeedBracket, isFalse);
    expect(org.poolStandings, isNotEmpty);
    for (final g in [...repo.games['t1']!]) {
      if (g.stage == GameStage.pool) {
        await org.setFinalScore.execute((gameId: g.id, scoreA: 11, scoreB: 6));
        await pumpEventQueue();
      }
    }
    expect(org.canSeedBracket, isTrue);
    await org.seedBracket.execute();
    await pumpEventQueue();
    expect(org.canSeedBracket, isFalse);
    expect(org.bracketGames.where((g) => g.hasTeams), isNotEmpty);
  });

  test("members only see tournaments they're playing in", () async {
    seed(fourTeams(TournamentFormat.roundRobin));
    repo.tournaments['g1']!.add(
      GroupTournament(
        id: 't2',
        name: 'Other',
        settings: TournamentSettings(startsAt: DateTime(2026, 11, 8)),
      ),
    );
    GroupTournamentsViewModel listVm(String uid) => GroupTournamentsViewModel(
      groupId: 'g1',
      teamRepository: teams,
      tournamentRepository: repo,
      authRepository: as(uid),
    );
    final org = listVm('owner');
    final member = listVm('p1');
    final outsider = listVm('stranger');
    await pumpEventQueue();
    expect(org.isOrganizer, isTrue);
    expect(org.tournaments, hasLength(2));
    expect(member.tournaments.map((t) => t.id), ['t1']);
    expect(member.isOrganizer, isFalse);
    expect(outsider.tournaments, isEmpty);
  });

  testWidgets('a captain reports a score from the game sheet', (tester) async {
    seed(fourTeams(TournamentFormat.singleElim));
    final first = repo.games['t1']!.firstWhere((g) => g.hasTeams);
    final cap = fourTeams(
      TournamentFormat.singleElim,
    ).team(first.teamA)!.captainId!;
    final vm = GroupTournamentViewModel(
      groupId: 'g1',
      tournamentId: 't1',
      teamRepository: teams,
      tournamentRepository: repo,
      authRepository: as(cap),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: GroupTournamentScreen(viewModel: vm),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Fall Hat'), findsOneWidget);
    expect(find.textContaining("You're on"), findsOneWidget);
    expect(find.text('Report score'), findsOneWidget);

    await tester.tap(find.text('Report score'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Report score'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '11');
    await tester.enterText(fields.at(1), '8');
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();

    expect(repo.log, ['report ${first.id}']);
    expect(find.text('Waiting for the other captain to confirm.'), findsOne);
    vm.dispose();
  });
}
