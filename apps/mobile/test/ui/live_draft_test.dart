import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/hosted_tournament/hosted_tournament_repository.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/hosted_tournament.dart';
import 'package:frisbee_app/domain/models/live_draft.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/tournaments/view_models/hosted_tournament_form_viewmodel.dart';
import 'package:frisbee_app/ui/tournaments/view_models/hosted_tournament_viewmodel.dart';
import 'package:frisbee_app/ui/tournaments/view_models/live_draft_viewmodel.dart';
import 'package:frisbee_app/ui/tournaments/view_models/team_draft_viewmodel.dart';
import 'package:frisbee_app/ui/tournaments/widgets/live_draft_screen.dart';
import 'package:frisbee_app/utils/result.dart';

import '../testing/fakes.dart';
import '../testing/hosted_tournament_fakes.dart';

void main() {
  group('LiveDraft', () {
    // The same table is in functions/test/tournaments/draft.test.ts.
    test('snakes back and forth', () {
      expect(
        [for (var i = 0; i < 9; i++) LiveDraft.snakeIndex(3, i)],
        [0, 1, 2, 2, 1, 0, 0, 1, 2],
      );
      expect(
        [for (var i = 0; i < 6; i++) LiveDraft.snakeIndex(2, i)],
        [0, 1, 1, 0, 0, 1],
      );
    });

    LiveDraft draft({List<DraftPick> picks = const [], int seconds = 60}) =>
        LiveDraft(
          divisionId: 'd',
          status: DraftStatus.live,
          captains: const [
            DraftCaptain(uid: 'a', name: 'Ana'),
            DraftCaptain(uid: 'b', name: 'Ben'),
            DraftCaptain(uid: 'c', name: 'Cy'),
          ],
          pool: const {'x': 'Xi', 'y': 'Yo', 'z': 'Zed', 'w': 'Wu'},
          picks: picks,
          pickSeconds: seconds,
          turnStartedAt: DateTime(2027, 1, 1, 12),
        );

    test('knows whose turn it is until the pool is empty', () {
      expect(draft().onTheClock, 'a');
      final picks = [
        const DraftPick(uid: 'x', captainId: 'a'),
        const DraftPick(uid: 'y', captainId: 'b'),
        const DraftPick(uid: 'z', captainId: 'c'),
      ];
      expect(draft(picks: picks).onTheClock, 'c');
      expect(draft(picks: picks).available.map((e) => e.key), ['w']);
      expect(draft(picks: picks).teamOf('b'), ['b', 'y']);
      expect(
        draft(
          picks: [
            ...picks,
            const DraftPick(uid: 'w', captainId: 'c'),
          ],
        ).onTheClock,
        isNull,
      );
    });

    test('counts the clock down to zero', () {
      final d = draft();
      expect(d.secondsLeft(DateTime(2027, 1, 1, 12, 0, 20)), 40);
      expect(d.secondsLeft(DateTime(2027, 1, 1, 12, 5)), 0);
      expect(draft(seconds: 0).secondsLeft(DateTime(2027, 1, 1, 12)), isNull);
    });
  });

  group('the draft board', () {
    late FakeTeamRepository teams;
    late FakeHostedTournamentRepository repo;

    FakeAuthRepository as(String uid) => FakeAuthRepository(
      user: AppUser(uid: uid, email: '$uid@x.com', displayName: 'Player $uid'),
    );

    setUp(() {
      teams = FakeTeamRepository();
      repo = FakeHostedTournamentRepository();
      teams.teams['host'] = Team(
        id: 'host',
        name: 'Host',
        division: Division.mixed,
        level: CompetitionLevel.club,
        ownerId: 'director',
        members: {'director': TeamRole.owner},
        memberNames: {'director': 'Director'},
        kind: TeamKind.community,
      );
    });

    /// A hat tournament with a captains' draft and 8 accepted players.
    Future<(String, String)> hat() async {
      final f = HostedTournamentFormViewModel(
        hostId: 'host',
        tournamentRepository: repo,
        teamRepository: teams,
        authRepository: as('director'),
        now: () => DateTime(2027, 3, 1),
      );
      await pumpEventQueue();
      f.setEntryType(TournamentEntryType.players);
      f.setDraftMode(DraftMode.captains);
      f.name = 'Hat Day';
      await f.save.execute();
      final id = (f.save.result as Ok<String>).value;
      f.dispose();
      final page = HostedTournamentViewModel(
        tournamentId: id,
        tournamentRepository: repo,
        teamRepository: teams,
        authRepository: as('director'),
        now: () => DateTime(2027, 4, 10),
      );
      await pumpEventQueue();
      await page.saveDivision.execute(
        page.newDivision().copyWith(
          settings: page.newDivision().settings.copyWith(playersOnField: 4),
        ),
      );
      page.dispose();
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
      return (id, division);
    }

    Future<LiveDraftViewModel> board(String uid, String id, String d) async {
      final vm = LiveDraftViewModel(
        tournamentId: id,
        divisionId: d,
        tournamentRepository: repo,
        teamRepository: teams,
        authRepository: as(uid),
        now: () => DateTime(2027, 1, 1),
      );
      await pumpEventQueue();
      return vm;
    }

    test('a captains draft mode is saved with the event', () async {
      final (id, _) = await hat();
      expect(repo.tournaments[id]!.draftMode, DraftMode.captains);
    });

    test('the host chooses captains and starts it', () async {
      final (id, d) = await hat();
      final host = await board('director', id, d);
      expect(host.isManager, isTrue);
      expect(host.draft, isNull);
      expect(host.accepted, hasLength(8));
      expect(host.startProblem, contains('at least'));
      host.toggleCaptain('p0');
      host.toggleCaptain('p1');
      expect(host.startProblem, isNull);
      await host.start.execute();
      await pumpEventQueue();
      expect(host.start.completed, isTrue);
      expect(host.draft!.captains.map((c) => c.uid), ['p0', 'p1']);
      expect(host.draft!.pool.keys, hasLength(6));
      expect(host.chosen, isEmpty);
      host.dispose();
    });

    test('captains take turns and the host can undo and finish', () async {
      final (id, d) = await hat();
      final host = await board('director', id, d);
      host.toggleCaptain('p0');
      host.toggleCaptain('p1');
      await host.start.execute();
      await pumpEventQueue();

      final first = await board('p0', id, d);
      final second = await board('p1', id, d);
      expect(first.isMyTurn, isTrue);
      expect(second.isMyTurn, isFalse);
      expect(second.canPick, isFalse);
      expect(host.canPick, isTrue);
      expect(first.details, isNotNull);

      await first.pick.execute('p2');
      await pumpEventQueue();
      expect(second.isMyTurn, isTrue);
      await second.pick.execute('p3');
      await second.pick.execute('p4');
      await pumpEventQueue();
      // Snake: p1 picks twice in a row.
      expect(first.isMyTurn, isTrue);
      expect(host.draft!.teamOf('p1'), ['p1', 'p3', 'p4']);

      await host.control.execute(DraftControl.undo);
      await pumpEventQueue();
      expect(host.draft!.picks, hasLength(2));
      await host.control.execute(DraftControl.pause);
      await pumpEventQueue();
      expect(host.canPick, isFalse);
      await host.control.execute(DraftControl.resume);
      await host.control.execute(DraftControl.autopick);
      await pumpEventQueue();
      expect(host.draft!.picks, hasLength(3));

      await host.finish.execute();
      await pumpEventQueue();
      final division = repo.divisions[id]![d]!;
      expect(division.teams, hasLength(2));
      expect(division.teams.first.captainId, 'p0');
      expect(division.teams.first.playerIds.first, 'p0');
      expect(division.seeds, [for (final t in division.teams) t.id]);
      expect(host.draft!.status, DraftStatus.finished);
      for (final vm in [host, first, second]) {
        vm.dispose();
      }
    });

    test('a refused call shows as an error', () async {
      final (id, d) = await hat();
      final host = await board('director', id, d);
      repo.draftError = Exception('The server said no.');
      host.toggleCaptain('p0');
      host.toggleCaptain('p1');
      await host.start.execute();
      expect(host.start.error, isTrue);
      host.dispose();
    });

    test('a captain who opened the board early still sees skills', () async {
      final (id, d) = await hat();
      final early = await board('p0', id, d);
      final watcher = await board('p5', id, d);
      expect(early.details, isNull);
      final host = await board('director', id, d);
      host.toggleCaptain('p0');
      host.toggleCaptain('p1');
      await host.start.execute();
      await pumpEventQueue();
      expect(early.isCaptain, isTrue);
      expect(early.details, isNotNull);
      // A player who isn't a captain never asks for them.
      expect(watcher.details, isNull);
      for (final vm in [early, watcher, host]) {
        vm.dispose();
      }
    });

    test('a running draft can only be restarted by cancelling it', () async {
      final (id, d) = await hat();
      final host = await board('director', id, d);
      host.toggleCaptain('p0');
      host.toggleCaptain('p1');
      await host.start.execute();
      await pumpEventQueue();
      expect(repo.drafts, hasLength(1));
      await host.control.execute(DraftControl.cancel);
      await pumpEventQueue();
      expect(host.draft, isNull);
      host.toggleCaptain('p2');
      host.toggleCaptain('p3');
      await host.start.execute();
      await pumpEventQueue();
      expect(host.draft!.captains.map((c) => c.uid), ['p2', 'p3']);
      host.dispose();
    });

    test('teams from a captains draft are adjusted, not dealt again', () async {
      final (id, d) = await hat();
      final host = await board('director', id, d);
      host.toggleCaptain('p0');
      host.toggleCaptain('p1');
      await host.start.execute();
      await pumpEventQueue();
      await host.control.execute(DraftControl.autopick);
      await host.finish.execute();
      await pumpEventQueue();
      host.dispose();

      final teams = TeamDraftViewModel(
        tournamentId: id,
        divisionId: d,
        tournamentRepository: repo,
      );
      await pumpEventQueue();
      expect(teams.fromCaptains, isTrue);
      final before = [for (final t in teams.teams) t.playerIds];
      await teams.draft.execute();
      expect(teams.draft.error, isTrue);
      expect([for (final t in teams.teams) t.playerIds], before);
      teams.dispose();
    });

    testWidgets('the screen shows who is picking and lets them draft', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final (id, d) = await tester.runAsync(hat).then((r) => r!);
      final host = await tester.runAsync(() => board('director', id, d));
      host!.toggleCaptain('p0');
      host.toggleCaptain('p1');
      await tester.runAsync(host.start.execute);
      await tester.runAsync(pumpEventQueue);
      final cap = await tester.runAsync(() => board('p0', id, d));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: LiveDraftScreen(viewModel: cap!),
        ),
      );
      await tester.pump();
      expect(find.text("You're on the clock"), findsOneWidget);
      expect(find.text('Draft'), findsNWidgets(6));
      await tester.runAsync(() async {
        await cap.pick.execute('p2');
        await pumpEventQueue();
      });
      await tester.pump();
      expect(find.text('Player 1 is picking'), findsOneWidget);
      expect(find.text('Draft'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      cap.dispose();
      host.dispose();
    });
  });
}
