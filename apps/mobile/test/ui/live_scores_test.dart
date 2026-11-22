// Live running scores (F1): captains and the host keep a game's score
// while it's played; everyone sees it on the schedule, the navy header,
// the tournament-day card and Discover's "Live now". It's never the final.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/hosted_tournament/tournament_days.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/group_tournament.dart';
import 'package:frisbee_app/domain/models/hosted_tournament.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/core/ui/layout.dart' show HighlightButton;
import 'package:frisbee_app/ui/core/ui/scoreboard.dart';
import 'package:frisbee_app/ui/tournaments/view_models/hosted_tournament_viewmodel.dart';
import 'package:frisbee_app/ui/tournaments/widgets/hosted_tournament_screen.dart';
import 'package:frisbee_app/ui/tournaments/widgets/live_score_sheet.dart';
import 'package:frisbee_app/ui/tournaments/widgets/tournament_parts.dart'
    show HostedGameRow;
import 'package:frisbee_app/ui/tournaments/widgets/tournament_day_card.dart';
import 'package:go_router/go_router.dart';

import '../testing/fakes.dart';
import '../testing/hosted_tournament_fakes.dart';

void main() {
  // seedLiveTournament: g3 (Boulder Gold v Northside Flyers, t1) started
  // ten minutes ago; "cap" captains t1, "director" runs the host.
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
    repo = FakeHostedTournamentRepository()..liveClock = () => now;
    teams = FakeTeamRepository();
    teams.teams['t1'] = team('t1', {
      'cap': TeamRole.owner,
      'pat': TeamRole.player,
    });
    teams.teams['host'] = team('host', {
      'director': TeamRole.owner,
    }, kind: TeamKind.community);
    seedLiveTournament(repo, now: now, captains: ['cap']);
    // Its one division, as the page lists it.
    repo.tournaments['x9'] = repo.tournaments['x9']!.copyWith(
      divisions: const [
        DivisionSummary(
          id: 'd1',
          division: Division.mixed,
          level: CompetitionLevel.club,
        ),
      ],
    );
  });

  HostedTournamentViewModel page(String uid, {DateTime? at}) {
    final vm = HostedTournamentViewModel(
      tournamentId: 'x9',
      tournamentRepository: repo,
      teamRepository: teams,
      authRepository: FakeAuthRepository(
        user: AppUser(uid: uid, email: '$uid@x.com'),
      ),
      postRepository: FakeTeamPostRepository(),
      now: () => at ?? now,
    );
    addTearDown(vm.dispose);
    return vm;
  }

  GroupGame gameOf(String id) =>
      repo.games['x9/d1']!.firstWhere((g) => g.id == id);

  /// Puts a running score on [id] as the API would.
  void setLive(String id, int a, int b, {DateTime? at}) {
    final list = repo.games['x9/d1']!;
    final i = list.indexWhere((g) => g.id == id);
    list[i] = list[i].copyWith(
      live: () => LiveScore(
        scoreA: a,
        scoreB: b,
        startedAt: (at ?? now).subtract(const Duration(minutes: 5)),
        updatedAt: at ?? now,
      ),
    );
  }

  group('GroupGame.live', () {
    test('reads the stored running score and never writes it back', () {
      final g = GroupGame.fromMap('g1', {
        'order': 0,
        'stage': 'pool',
        'round': 1,
        'label': 'Pool A',
        'status': 'scheduled',
        'live': {
          'scoreA': 7,
          'scoreB': 5,
          'startedAt': now.subtract(const Duration(minutes: 30)),
          'updatedAt': now,
          'by': 'cap',
        },
      });
      expect(g.live?.scoreA, 7);
      expect(g.live?.scoreB, 5);
      expect(g.live?.by, 'cap');
      expect(g.toMap().containsKey('live'), isFalse);
      // Not a final: nothing counts it.
      expect(g.isDone, isFalse);
      expect(g.scoreA, isNull);
    });

    test('is live only while scheduled and fresh', () {
      final g = GroupGame.fromMap('g1', {
        'status': 'scheduled',
        'live': {'scoreA': 1, 'scoreB': 0, 'updatedAt': now},
      });
      expect(g.liveAt(now), isNotNull);
      expect(g.liveAt(now.add(const Duration(hours: 3))), isNotNull);
      expect(g.liveAt(now.add(const Duration(hours: 3, minutes: 1))), isNull);
      expect(g.copyWith(status: GameStatus.reported).liveAt(now), isNull);
      expect(g.copyWith(status: GameStatus.done).liveAt(now), isNull);
    });

    test('takes one from two hours before its start to a day after', () {
      final g = gameOf('g5'); // starts in two hours
      expect(g.inLiveWindow(now), isTrue);
      expect(g.inLiveWindow(now.subtract(const Duration(minutes: 1))), isFalse);
      expect(g.inLiveWindow(now.add(const Duration(hours: 26))), isTrue);
      expect(
        g.inLiveWindow(now.add(const Duration(hours: 26, minutes: 1))),
        isFalse,
      );
    });
  });

  group('HostedTournamentViewModel live scores', () {
    test("either team's captain or the host keeps it; others can't", () async {
      final cap = page('cap');
      final pat = page('pat');
      final director = page('director');
      await pumpEventQueue();
      final g3 = gameOf('g3');
      expect(cap.canKeepLive(g3), isTrue);
      expect(director.canKeepLive(g3), isTrue);
      expect(pat.canKeepLive(g3), isFalse);
      // Not t1's game: its captain can't; the host can.
      expect(cap.canKeepLive(gameOf('g4')), isFalse);
      expect(director.canKeepLive(gameOf('g4')), isTrue);
      // Final already.
      expect(director.canKeepLive(gameOf('g1')), isFalse);
      // Without the API in this build, nobody.
      repo.liveScores = false;
      expect(cap.canKeepLive(g3), isFalse);
    });

    test('not once a score is reported, nor away from the day', () async {
      final cap = page('cap');
      await pumpEventQueue();
      await cap.report.execute((gameId: 'g3', scoreA: 9, scoreB: 15));
      await pumpEventQueue();
      expect(cap.canKeepLive(gameOf('g3')), isFalse);
      final later = page('cap', at: now.add(const Duration(days: 2)));
      await pumpEventQueue();
      expect(later.canKeepLive(gameOf('g4')), isFalse);
      expect(later.canKeepLive(gameOf('g5')), isFalse);
    });

    test('Start game, +1 per team and undo; never the final', () async {
      final cap = page('cap');
      await pumpEventQueue();
      cap.startLive('g3');
      await pumpEventQueue();
      expect(repo.log, contains('live g3 0-0'));
      cap.bumpLive('g3', teamA: false);
      await pumpEventQueue();
      cap.bumpLive('g3', teamA: false);
      await pumpEventQueue();
      cap.bumpLive('g3', teamA: true);
      await pumpEventQueue();
      cap.bumpLive('g3', teamA: false, by: -1);
      await pumpEventQueue();
      final g3 = cap.games.firstWhere((g) => g.id == 'g3');
      expect(cap.liveOf(g3)?.scoreA, 1);
      expect(cap.liveOf(g3)?.scoreB, 1);
      expect(g3.status, GameStatus.scheduled);
      expect(g3.isDone, isFalse);
      expect(cap.liveGames.map((g) => g.id), ['g3']);
      // Nothing moved on; the standings don't count it.
      expect(cap.myUpcoming.map((g) => g.id), contains('g3'));
      // Undo stops at zero.
      cap.setLive('g3', -3, 120);
      await pumpEventQueue();
      expect(repo.log.last, 'live g3 0-99');
    });

    test('quick taps show at once and are sent latest-first', () async {
      final cap = page('cap');
      await pumpEventQueue();
      repo.liveHold = Completer<void>();
      cap.startLive('g3');
      cap.bumpLive('g3', teamA: true);
      cap.bumpLive('g3', teamA: true);
      cap.bumpLive('g3', teamA: false);
      // Shown straight away, while the first is still on its way.
      final g3 = cap.games.firstWhere((g) => g.id == 'g3');
      expect(cap.liveOf(g3)?.scoreA, 2);
      expect(cap.liveOf(g3)?.scoreB, 1);
      expect(cap.liveScore.running, isTrue);
      repo.liveHold!.complete();
      await pumpEventQueue();
      // The first, then only the latest: no tap lost, none sent twice.
      expect(repo.log.where((l) => l.startsWith('live ')), [
        'live g3 0-0',
        'live g3 2-1',
      ]);
      expect(gameOf('g3').live?.scoreA, 2);
      expect(gameOf('g3').live?.scoreB, 1);
    });

    test('taps on another game during a send are sent too', () async {
      final director = page('director');
      await pumpEventQueue();
      repo.liveHold = Completer<void>();
      director.startLive('g3');
      director.startLive('g4');
      director.bumpLive('g4', teamA: true);
      repo.liveHold!.complete();
      await pumpEventQueue();
      expect(repo.log.where((l) => l.startsWith('live ')), [
        'live g3 0-0',
        'live g4 1-0',
      ]);
      expect(director.liveGames.map((g) => g.id), ['g3', 'g4']);
    });

    test('a failed send goes back to the server score and says why', () async {
      setLive('g3', 4, 4);
      final cap = page('cap');
      await pumpEventQueue();
      repo.liveError = Exception('Live scores are kept on the day.');
      cap.bumpLive('g3', teamA: true);
      await pumpEventQueue();
      expect(cap.liveScore.error, isTrue);
      expect(cap.liveOf(cap.games.firstWhere((g) => g.id == 'g3'))?.scoreA, 4);
    });

    test('a stale running score is not live; Stop takes it off', () async {
      setLive('g4', 3, 2, at: now.subtract(const Duration(hours: 4)));
      setLive('g3', 5, 6);
      final director = page('director');
      await pumpEventQueue();
      expect(director.liveGames.map((g) => g.id), ['g3']);
      await director.stopLive.execute('g3');
      await pumpEventQueue();
      expect(director.liveGames, isEmpty);
      expect(repo.log, contains('live off g3'));
    });
  });

  group('the tournament page', () {
    Future<void> open(WidgetTester tester, HostedTournamentViewModel vm) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: HostedTournamentScreen(viewModel: vm, initialTab: 'schedule'),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('everyone sees a red Live pill and the running score', (
      tester,
    ) async {
      setLive('g3', 7, 5);
      final vm = page('pat');
      await open(tester, vm);
      // On the game's row (only that one) and in the navy header.
      expect(find.byType(LivePill), findsOneWidget);
      expect(find.byKey(const Key('header-live')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('header-live')),
          matching: find.textContaining('Boulder Gold'),
        ),
        findsOneWidget,
      );
      // Not a captain: nothing to keep.
      expect(find.text('Start game'), findsNothing);
      expect(find.text('Update live score'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('no Live pill when nothing is being played', (tester) async {
      final vm = page('pat');
      await open(tester, vm);
      expect(find.byType(LivePill), findsNothing);
      expect(find.byKey(const Key('header-live')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets("the captain's game card starts the game and steps the score; "
        'the final sheet is filled in from it', (tester) async {
      final vm = page('cap');
      await open(tester, vm);
      expect(find.text('YOUR GAME · NEEDS A SCORE'), findsOneWidget);
      await tester.tap(find.text('Start game'));
      await tester.pumpAndSettle();
      expect(find.byType(LiveScoreSheet), findsOneWidget);
      await tester.tap(find.byKey(const Key('live-start')));
      await tester.pumpAndSettle();
      expect(repo.log, contains('live g3 0-0'));
      // g3 is Boulder Gold (A) v Northside Flyers (B).
      await tester.tap(find.byKey(const Key('live-plus-b')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('live-plus-b')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('live-plus-a')));
      await tester.pumpAndSettle();
      final sheet = find.byType(LiveScoreSheet);
      String scoreOf(String side) => tester
          .widget<ScoreText>(
            find.descendant(
              of: find
                  .ancestor(
                    of: find.byKey(Key('live-plus-$side')),
                    matching: find.byType(Row),
                  )
                  .first,
              matching: find.byType(ScoreText),
            ),
          )
          .text;
      expect(scoreOf('a'), '1');
      expect(scoreOf('b'), '2');
      await tester.tap(find.byKey(const Key('live-minus-a')));
      await tester.pumpAndSettle();
      expect(scoreOf('a'), '0');
      expect(
        find.descendant(of: sheet, matching: find.byType(LivePill)),
        findsOneWidget,
      );
      expect(gameOf('g3').live?.scoreB, 2);
      expect(gameOf('g3').status, GameStatus.scheduled);

      // The final: the score dialog starts from the running score.
      await tester.tap(find.text('Report final score'));
      await tester.pumpAndSettle();
      final fields = tester
          .widgetList<TextField>(find.byType(TextField))
          .map((f) => f.controller!.text)
          .toList();
      expect(fields, ['0', '2']);
      await tester.enterText(find.byType(TextField).first, '11');
      await tester.enterText(find.byType(TextField).last, '15');
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();
      expect(repo.log, contains('report g3'));
      expect(gameOf('g3').status, GameStatus.reported);
      // Reported: no longer live, and the other captain confirms.
      expect(find.byType(LiveScoreSheet), findsNothing);
      expect(find.byKey(const Key('header-live')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets("the host keeps it from a game's sheet", (tester) async {
      final vm = page('director');
      await open(tester, vm);
      // g4 (Front Range v Mesa): the host isn't a captain of either.
      await tester.tap(
        find.byWidgetPredicate((w) => w is HostedGameRow && w.game.id == 'g4'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('Start game'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LiveScoreSheet), findsOneWidget);
      await tester.tap(find.byKey(const Key('live-start')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('live-plus-a')));
      await tester.pumpAndSettle();
      expect(repo.log, containsAllInOrder(['live g4 0-0', 'live g4 1-0']));
      // The host sets the final, pre-filled the same way.
      expect(find.text('Set final score'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets("the game sheet's Report score starts from the live score", (
      tester,
    ) async {
      setLive('g3', 6, 8);
      final vm = page('cap');
      await open(tester, vm);
      await tester.tap(find.widgetWithText(HighlightButton, 'Report score'));
      await tester.pumpAndSettle();
      expect(
        find.text("Live score. It isn't final until it's reported."),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.widgetWithText(FilledButton, 'Report score'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<TextField>(find.byType(TextField))
            .map((f) => f.controller!.text),
        ['6', '8'],
      );
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('elsewhere', () {
    testWidgets("the tournament-day card shows the live game's score", (
      tester,
    ) async {
      setLive('g3', 4, 6);
      // Made outside the fake clock: it keeps a minute timer.
      final d = (await tester.runAsync(() async {
        final days = TournamentDays(
          repository: repo,
          teams: Stream.value([teams.teams['t1']!]),
          uid: 'pat',
          clock: () => now,
        );
        addTearDown(days.dispose);
        await pumpEventQueue();
        return days.days.single;
      }))!;
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              body: ListView(children: [TournamentDayCard(day: d)]),
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('day-live')), findsOneWidget);
      expect(find.text('vs Boulder Gold'), findsOneWidget);
      // From Northside Flyers' side (team B of g3): 6–4.
      expect(find.text('6–4'), findsOneWidget);
    });

    testWidgets('the card finds the live game when an earlier one still '
        'waits for its score', (tester) async {
      // An earlier t1 game (before g3) was played but only reported.
      repo.games['x9/d1']!.add(
        GroupGame(
          id: 'g0',
          order: -1,
          stage: GameStage.pool,
          round: 1,
          label: 'Pool A',
          poolId: 'A',
          field: 1,
          startsAt: now.subtract(const Duration(hours: 1)),
          teamA: 't1',
          teamB: 'me',
          status: GameStatus.reported,
          report: const ScoreReport(scoreA: 13, scoreB: 9, byTeamId: 't1'),
        ),
      );
      setLive('g3', 2, 1);
      final d = (await tester.runAsync(() async {
        final days = TournamentDays(
          repository: repo,
          teams: Stream.value([teams.teams['t1']!]),
          uid: 'pat',
          clock: () => now,
        );
        addTearDown(days.dispose);
        await pumpEventQueue();
        return days.days.single;
      }))!;
      expect(d.day.next?.game.id, 'g0');
      expect(d.liveGame?.id, 'g3');
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              body: ListView(children: [TournamentDayCard(day: d)]),
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('day-live')), findsOneWidget);
      expect(find.text('vs Boulder Gold'), findsOneWidget);
      expect(find.text('1–2'), findsOneWidget);
    });
  });
}
