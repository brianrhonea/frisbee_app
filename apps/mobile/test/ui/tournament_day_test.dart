import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/hosted_tournament/tournament_days.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/group_tournament.dart';
import 'package:frisbee_app/domain/models/hosted_tournament.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/tournament_engine/tournament_day.dart';
import 'package:frisbee_app/routing/routes.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/tournaments/view_models/hosted_tournament_viewmodel.dart';
import 'package:frisbee_app/ui/tournaments/widgets/hosted_tournament_screen.dart';
import 'package:frisbee_app/ui/tournaments/widgets/tournament_day_card.dart';
import 'package:go_router/go_router.dart';

import '../testing/fakes.dart';
import '../testing/hosted_tournament_fakes.dart';

void main() {
  final now = DateTime(2026, 11, 21, 11);
  late FakeHostedTournamentRepository repo;
  late FakeTeamRepository teams;

  Team team(String id, Map<String, TeamRole> members, {TeamKind? kind}) => Team(
    id: id,
    name: id == 't1' ? 'Northside Flyers' : 'Team $id',
    division: Division.mixed,
    level: CompetitionLevel.club,
    ownerId: members.keys.first,
    members: members,
    memberNames: {for (final m in members.keys) m: 'Name $m'},
    kind: kind ?? TeamKind.team,
  );

  setUp(() {
    repo = FakeHostedTournamentRepository();
    teams = FakeTeamRepository();
    teams.teams['t1'] = team('t1', {
      'cap': TeamRole.owner,
      'pat': TeamRole.player,
    });
    teams.teams['host'] = team('host', {
      'director': TeamRole.owner,
    }, kind: TeamKind.community);
  });

  Future<TournamentDays> days(String uid, {DateTime? at}) async {
    final d = TournamentDays(
      repository: repo,
      teams: Stream.value([teams.teams['t1']!]),
      uid: uid,
      clock: () => at ?? now,
    );
    addTearDown(d.dispose);
    await pumpEventQueue();
    return d;
  }

  group('TournamentDays', () {
    test("shows a live tournament's day for the team", () async {
      seedLiveTournament(repo, now: now, captains: ['cap']);
      final d = (await days('pat')).days.single;
      expect(d.tournament.name, 'Mile High Open');
      expect(d.day.phase, TournamentDayPhase.today);
      expect(d.day.next?.game.id, 'g3');
      expect(d.nameOf(d.day.next?.opponent), 'Boulder Gold');
      expect((d.day.wins, d.day.losses), (1, 0));
      expect(d.day.poolPlace, 1);
      // A started game with no score is due, but only captains act on it.
      expect(d.day.scoreDueKind, ScoreDueKind.report);
      expect(d.isCaptain, isFalse);
      expect(d.actionGame, isNull);
    });

    test('captains get the game to report', () async {
      seedLiveTournament(repo, now: now, captains: ['cap']);
      final d = (await days('cap')).days.single;
      expect(d.isCaptain, isTrue);
      expect(d.actionGame?.id, 'g3');
    });

    test('nothing for an entry that was not accepted', () async {
      seedLiveTournament(repo, now: now);
      repo.entered['t1'] = [
        for (final e in repo.entered['t1']!)
          EnteredTournament(
            tournamentId: e.tournamentId,
            name: e.name,
            status: EntryStatus.applied,
            startsOn: e.startsOn,
            endsOn: e.endsOn,
          ),
      ];
      expect((await days('pat')).days, isEmpty);
    });

    test('nothing for a tournament days away', () async {
      seedLiveTournament(repo, now: now, status: HostedStatus.scheduled);
      final early = now.subtract(const Duration(days: 3));
      expect((await days('pat', at: early)).days, isEmpty);
    });

    test("a host's dates a day off here still follow the event", () async {
      // Stored as the host's local midnight, which can read as the evening
      // before here: the card still shows on the day.
      seedLiveTournament(repo, now: now);
      final evening = DateTime(now.year, now.month, now.day - 1, 22);
      repo.entered['t1'] = [
        EnteredTournament(
          tournamentId: 'x9',
          name: 'Mile High Open',
          status: EntryStatus.accepted,
          startsOn: evening,
          endsOn: evening,
        ),
      ];
      expect((await days('pat')).days, hasLength(1));
    });

    test("communities' entries aren't followed", () async {
      seedLiveTournament(repo, now: now, teamId: 'host');
      final d = TournamentDays(
        repository: repo,
        teams: Stream.value([teams.teams['host']!]),
        uid: 'director',
        clock: () => now,
      );
      addTearDown(d.dispose);
      await pumpEventQueue();
      expect(d.days, isEmpty);
    });

    test('nothing for a draft tournament', () async {
      seedLiveTournament(repo, now: now, status: HostedStatus.draft);
      expect((await days('pat')).days, isEmpty);
    });
  });

  group('TournamentDayCard', () {
    Future<GoRouter> pumpCard(WidgetTester tester, TeamTournamentDay d) async {
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              body: ListView(children: [TournamentDayCard(day: d)]),
            ),
          ),
          GoRoute(
            path: '/tournaments/:id',
            builder: (_, s) => Text('opened ${s.uri}'),
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      );
      await tester.pumpAndSettle();
      return router;
    }

    testWidgets('shows the next game, record and last result', (tester) async {
      seedLiveTournament(repo, now: now, captains: ['cap']);
      final d = (await tester.runAsync(() => days('pat')))!.days.single;
      await pumpCard(tester, d);
      expect(find.text('LIVE · NORTHSIDE FLYERS'), findsOneWidget);
      expect(find.text('Mile High Open'), findsOneWidget);
      expect(find.text('vs Boulder Gold'), findsOneWidget);
      expect(find.textContaining('Field 3'), findsOneWidget);
      expect(find.text('1–0 · 1st in Pool A'), findsOneWidget);
      expect(find.text('Last: W 13–8 vs Front Range'), findsOneWidget);
      // Not a captain: no score button.
      expect(find.text('Report score'), findsNothing);
      expect(find.text('Schedule & standings'), findsOneWidget);
    });

    testWidgets('waiting on the bracket, and a next game on another day', (
      tester,
    ) async {
      seedLiveTournament(repo, now: now);
      // Every pool game played; the final, tomorrow, waits for Pool A's top
      // two.
      final games = repo.games['x9/d1']!;
      repo.games['x9/d1'] = [
        for (final g in games)
          GroupGame.fromMap(g.id, {
            ...g.toMap(),
            'status': 'done',
            'scoreA': g.scoreA ?? 13,
            'scoreB': g.scoreB ?? 9,
          }),
        GroupGame(
          id: 'f',
          order: 9,
          stage: GameStage.winners,
          round: 1,
          label: 'Final',
          field: 1,
          startsAt: DateTime(now.year, now.month, now.day + 1, 9),
          sourceA: const PoolRank('A', 1),
          sourceB: const PoolRank('A', 2),
        ),
      ];
      var d = (await tester.runAsync(() => days('pat')))!.days.single;
      expect(d.day.awaiting, isTrue);
      await pumpCard(tester, d);
      expect(find.text('Next game to be decided'), findsOneWidget);
      expect(find.text('Waiting on the bracket'), findsOneWidget);

      // Seeded: the final shows with its day.
      repo.games['x9/d1'] = [
        ...repo.games['x9/d1']!.where((g) => g.id != 'f'),
        GroupGame(
          id: 'f',
          order: 9,
          stage: GameStage.winners,
          round: 1,
          label: 'Final',
          field: 1,
          startsAt: DateTime(now.year, now.month, now.day + 1, 9),
          teamA: 't1',
          teamB: 'bg',
        ),
      ];
      d = (await tester.runAsync(() => days('pat')))!.days.single;
      await pumpCard(tester, d);
      expect(find.text('vs Boulder Gold'), findsOneWidget);
      expect(find.textContaining('Tomorrow 9:00'), findsOneWidget);
    });

    testWidgets("a captain's Report score opens the game", (tester) async {
      seedLiveTournament(repo, now: now, captains: ['cap']);
      final d = (await tester.runAsync(() => days('cap')))!.days.single;
      await pumpCard(tester, d);
      await tester.tap(find.text('Report score'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'opened ${Routes.tournament('x9', division: 'd1', game: 'g3')}',
        ),
        findsOneWidget,
      );
    });
  });

  testWidgets('the tournament page opens on a game with its score sheet', (
    tester,
  ) async {
    seedLiveTournament(repo, now: now, captains: ['cap']);
    final vm = HostedTournamentViewModel(
      tournamentId: 'x9',
      tournamentRepository: repo,
      teamRepository: teams,
      authRepository: FakeAuthRepository(
        user: const AppUser(uid: 'cap', email: 'cap@x.com'),
      ),
      postRepository: FakeTeamPostRepository(),
      now: () => now,
    );
    addTearDown(vm.dispose);
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: HostedTournamentScreen(
          viewModel: vm,
          openGameId: 'g3',
          openDivisionId: 'd1',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('Report score'),
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });

  test('Routes.tournament builds the game link', () {
    expect(Routes.tournament('x9'), '/tournaments/x9');
    expect(
      Routes.tournament('x9', division: 'd1', game: 'g3'),
      '/tournaments/x9?division=d1&game=g3',
    );
    expect(Routes.tournament('x9', host: 'g 1'), '/tournaments/x9?host=g+1');
  });
}
