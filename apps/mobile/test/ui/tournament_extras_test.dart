// Tournament extras (F30): the bracket on its own page, the score form's
// −/+ steppers, a league's schedule a week at a time, entering a team on a
// full screen (now the respond flow, respond_test), the event form as steps with Save draft / Publish, and
// Share on the event page.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/group_tournament.dart';
import 'package:frisbee_app/domain/models/hosted_tournament.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/routing/routes.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/group_tournaments/widgets/tournament_widgets.dart';
import 'package:frisbee_app/ui/tournaments/view_models/hosted_tournament_form_viewmodel.dart';
import 'package:frisbee_app/ui/tournaments/view_models/hosted_tournament_viewmodel.dart';
import 'package:frisbee_app/ui/tournaments/widgets/hosted_bracket_screen.dart';
import 'package:frisbee_app/ui/tournaments/widgets/hosted_tournament_form_screen.dart';
import 'package:frisbee_app/ui/tournaments/widgets/hosted_tournament_screen.dart';
import 'package:frisbee_app/ui/tournaments/widgets/share_tournament.dart';
import 'package:frisbee_app/utils/result.dart';
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

  FakeAuthRepository as(String uid) => FakeAuthRepository(
    user: AppUser(uid: uid, email: '$uid@x.com'),
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

  HostedTournamentViewModel page(String uid) {
    final vm = HostedTournamentViewModel(
      tournamentId: 'x9',
      tournamentRepository: repo,
      teamRepository: teams,
      authRepository: as(uid),
      postRepository: FakeTeamPostRepository(),
      now: () => now,
    );
    addTearDown(vm.dispose);
    return vm;
  }

  void bigView(WidgetTester tester) {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// A semifinal and a final after the pool games.
  void addBracket() {
    repo.games['x9/d1']!.addAll([
      GroupGame(
        id: 'sf1',
        order: 10,
        stage: GameStage.winners,
        round: 1,
        label: 'Semifinal',
        startsAt: now.add(const Duration(hours: 4)),
        teamA: 't1',
        teamB: 'me',
      ),
      GroupGame(
        id: 'sf2',
        order: 11,
        stage: GameStage.winners,
        round: 1,
        label: 'Semifinal',
        startsAt: now.add(const Duration(hours: 4)),
        teamA: 'fr',
        teamB: 'bg',
      ),
      GroupGame(
        id: 'f',
        order: 12,
        stage: GameStage.winners,
        round: 2,
        label: 'Final',
        startsAt: now.add(const Duration(hours: 6)),
        sourceA: const WinnerOf('sf1'),
        sourceB: const WinnerOf('sf2'),
      ),
    ]);
  }

  group('Share', () {
    test('sends the name, when and where, and the public page', () {
      final s = tournamentShare(repo.tournaments['x9']!);
      expect(s.link.path, '/tournaments/x9');
      expect(s.link.scheme, 'https');
      expect(s.text, startsWith('Mile High Open\nSat, Nov 21 · Aurora'));
      expect(s.text, endsWith('${s.link}'));
    });

    testWidgets("is on a published event's page, not a draft's", (
      tester,
    ) async {
      bigView(tester);
      final shared = <Uri>[];
      Future<void> pump() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: HostedTournamentScreen(
              viewModel: page('pat'),
              share: (_, _, link) async => shared.add(link),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await pump();
      await tester.tap(find.byTooltip('Share'));
      await tester.pumpAndSettle();
      expect(shared.single.path, '/tournaments/x9');
      await tester.pumpWidget(const SizedBox());

      repo.tournaments['x9'] = repo.tournaments['x9']!.copyWith(
        status: HostedStatus.draft,
      );
      await pump();
      expect(find.byTooltip('Share'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('Score steppers', () {
    testWidgets('step from empty, clamp, and still type', (tester) async {
      (int, int)? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await showScoreDialog(
                context,
                title: 'Report the score',
                nameA: 'Northside Flyers',
                nameB: 'Front Range',
                scoreB: 99,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      String text(int i) => tester
          .widgetList<TextField>(find.byType(TextField))
          .elementAt(i)
          .controller!
          .text;
      // Untouched stays empty, so a missing score is still caught.
      expect(text(0), '');
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('score-minus-a')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();
      expect(find.text('Enter both scores.'), findsOneWidget);
      // + starts at 1, then counts; − takes one off.
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const Key('score-plus-a')));
        await tester.pump();
      }
      await tester.tap(find.byKey(const Key('score-minus-a')));
      await tester.pump();
      expect(text(0), '2');
      // 99 is the most.
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('score-plus-b')))
            .onPressed,
        isNull,
      );
      // Typing still works, and the usual checks still apply.
      await tester.enterText(find.byType(TextField).last, '2');
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();
      expect(find.text("Games can't end in a tie."), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, '13');
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();
      expect(result, (2, 13));
    });
  });

  group('Bracket page', () {
    testWidgets('Results opens the bracket on its own page', (tester) async {
      bigView(tester);
      addBracket();
      final router = GoRouter(
        initialLocation: Routes.tournament('x9', tab: 'results'),
        routes: [
          GoRoute(
            path: '/tournaments/:id',
            builder: (_, state) => HostedTournamentScreen(
              viewModel: page('pat'),
              initialTab: state.uri.queryParameters['tab'],
            ),
            routes: [
              GoRoute(
                path: 'bracket/:divisionId',
                builder: (_, state) => HostedBracketScreen(
                  viewModel: page('pat'),
                  divisionId: state.pathParameters['divisionId']!,
                ),
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      );
      await tester.pumpAndSettle();
      expect(find.text('Bracket'), findsOneWidget);
      await tester.tap(find.text('Open bracket'));
      await tester.pumpAndSettle();
      expect(find.byType(HostedBracketScreen), findsOneWidget);
      expect(find.text('Mile High Open · Club Mixed'), findsOneWidget);
      expect(find.text('SEMIFINAL'), findsOneWidget);
      expect(find.text('FINAL'), findsOneWidget);
      expect(find.text('Winner of game 11'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets("a refused score from the bracket's game shows why", (
      tester,
    ) async {
      bigView(tester);
      final refusing = _RefusingRepo()..liveClock = () => now;
      seedLiveTournament(refusing, now: now, captains: ['cap']);
      refusing.tournaments['x9'] = repo.tournaments['x9']!;
      repo = refusing;
      addBracket();
      final vm = page('cap');
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: HostedBracketScreen(viewModel: vm, divisionId: 'd1'),
        ),
      );
      await tester.pumpAndSettle();
      await vm.report.execute((gameId: 'sf1', scoreA: 13, scoreB: 9));
      await tester.pumpAndSettle();
      expect(find.textContaining('Scores are closed.'), findsOneWidget);
      expect(vm.report.error, isFalse);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('says so when there is no bracket yet', (tester) async {
      bigView(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: HostedBracketScreen(viewModel: page('pat'), divisionId: 'd1'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No bracket yet'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('League weeks', () {
    testWidgets('opens on the next night and steps a week at a time', (
      tester,
    ) async {
      bigView(tester);
      // A league: g1-g2 last week, g3-g4 tonight, g5 next week.
      final t = repo.tournaments['x9']!;
      repo.tournaments['x9'] = HostedTournament.fromMap('x9', {
        ...t.toMap(),
        'kind': 'league',
        'status': 'live',
      });
      final list = repo.games['x9/d1']!;
      DateTime night(int week) =>
          DateTime(now.year, now.month, now.day + 7 * week, 19);
      for (final (i, g) in [...list].indexed) {
        list[i] = g.copyWith(
          startsAt: night(switch (g.id) {
            'g1' || 'g2' => -1,
            'g5' => 1,
            _ => 0,
          }),
        );
      }
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: HostedTournamentScreen(
            viewModel: page('pat'),
            initialTab: 'schedule',
          ),
        ),
      );
      await tester.pumpAndSettle();
      String label() =>
          tester.widget<Text>(find.byKey(const Key('week-label'))).data!;
      expect(label(), 'Week 2 of 3');
      await tester.tap(find.byKey(const Key('week-next')));
      await tester.pumpAndSettle();
      expect(label(), 'Week 3 of 3');
      expect(
        tester.widget<IconButton>(find.byKey(const Key('week-next'))).onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const Key('week-previous')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('week-previous')));
      await tester.pumpAndSettle();
      expect(label(), 'Week 1 of 3');
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('Event form steps', () {
    HostedTournamentFormViewModel form({String? id}) {
      final f = HostedTournamentFormViewModel(
        hostId: id == null ? 'host' : null,
        tournamentId: id,
        tournamentRepository: repo,
        teamRepository: teams,
        authRepository: as('director'),
        now: () => now,
      );
      addTearDown(f.dispose);
      return f;
    }

    test('steps clamp, and Review is last', () async {
      final f = form();
      await pumpEventQueue();
      expect(f.step, 0);
      f.back();
      expect(f.step, 0);
      f.goTo(99);
      expect(f.onReview, isTrue);
      expect(HostedTournamentFormViewModel.steps[f.step], 'Review');
    });

    test('Save draft keeps it a draft; Publish opens registration', () async {
      final draft = form();
      await pumpEventQueue();
      draft.name = 'Turkey Bowl';
      await draft.save.execute();
      final id = (draft.save.result as Ok<String>).value;
      expect(repo.tournaments[id]!.status, HostedStatus.draft);

      final published = form();
      await pumpEventQueue();
      expect(published.isDraft, isTrue);
      published.name = 'Snow Bowl';
      await published.publish.execute();
      final id2 = (published.publish.result as Ok<String>).value;
      expect(repo.tournaments[id2]!.status, HostedStatus.registration);
      expect(repo.divisions[id2], isNotEmpty);

      // Editing the draft can publish it; a published event can't again.
      final edit = form(id: id);
      await pumpEventQueue();
      expect(edit.isDraft, isTrue);
      await edit.publish.execute();
      expect(repo.tournaments[id]!.status, HostedStatus.registration);
      final again = form(id: id);
      await pumpEventQueue();
      expect(again.isDraft, isFalse);
      await again.publish.execute();
      expect(again.publish.error, isTrue);
    });

    test('a new event that cannot be published stays one draft', () async {
      final refusing = _RefusingRepo();
      final f = HostedTournamentFormViewModel(
        hostId: 'host',
        tournamentRepository: refusing,
        teamRepository: teams,
        authRepository: as('director'),
        now: () => now,
      );
      addTearDown(f.dispose);
      await pumpEventQueue();
      f.name = 'Snow Bowl';
      await f.publish.execute();
      expect(f.publish.error, isTrue);
      expect(refusing.tournaments, hasLength(1));
      final id = refusing.tournaments.keys.single;
      expect(f.createdDraftId, id);
      expect(refusing.tournaments[id]!.status, HostedStatus.draft);
    });

    testWidgets('Next through the steps, Review, then Publish', (tester) async {
      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final f = form();
      final router = GoRouter(
        initialLocation: '/tournaments/new',
        routes: [
          GoRoute(
            path: '/tournaments/new',
            builder: (_, _) => HostedTournamentFormScreen(viewModel: f),
          ),
          GoRoute(
            path: '/tournaments/:id',
            builder: (_, state) => Text('page ${state.pathParameters['id']}'),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      );
      await tester.pumpAndSettle();
      expect(find.text('Step 1 of 7 · Details'), findsOneWidget);
      expect(find.text('Save draft'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Name'),
        'Turkey Bowl',
      );
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.byKey(const Key('form-next')));
        await tester.pumpAndSettle();
      }
      // The Director step: optional, a member or anyone by name.
      expect(find.text('Step 6 of 7 · Director'), findsOneWidget);
      expect(find.byKey(const Key('director-me')), findsOneWidget);
      await tester.tap(find.byKey(const Key('form-next')));
      await tester.pumpAndSettle();
      expect(find.text('Step 7 of 7 · Review'), findsOneWidget);
      expect(find.textContaining('Turkey Bowl · Tournament'), findsOneWidget);
      expect(find.byKey(const Key('form-problem')), findsNothing);
      // The name typed on step 1 is kept; Edit goes back to it.
      await tester.tap(find.bySemanticsLabel('Edit Details'));
      await tester.pumpAndSettle();
      expect(find.text('Step 1 of 7 · Details'), findsOneWidget);
      expect(find.text('Turkey Bowl'), findsOneWidget);
      f.goTo(HostedTournamentFormViewModel.steps.length - 1);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('form-publish')));
      await tester.pumpAndSettle();
      final id = repo.tournaments.keys.firstWhere((k) => k != 'x9');
      expect(repo.tournaments[id]!.status, HostedStatus.registration);
      expect(find.text('page $id'), findsOneWidget);
    });

    testWidgets('without a name, Review says so and nothing saves', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final f = form();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: HostedTournamentFormScreen(viewModel: f),
        ),
      );
      await tester.pumpAndSettle();
      f.goTo(HostedTournamentFormViewModel.steps.length - 1);
      await tester.pumpAndSettle();
      expect(find.text('Give it a name.'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('form-publish')))
            .onPressed,
        isNull,
      );
      expect(
        tester.widget<TextButton>(find.byKey(const Key('form-save'))).onPressed,
        isNull,
      );
    });
  });
}

/// Refuses score reports and status changes, like the server can.
class _RefusingRepo extends FakeHostedTournamentRepository {
  @override
  Future<Result<void>> reportScore(
    String tournamentId,
    String divisionId,
    String gameId,
    ScoreReport report,
  ) async => Result.error(Exception('Scores are closed.'));

  @override
  Future<Result<void>> setStatus(
    String tournamentId,
    HostedStatus status,
  ) async => Result.error(Exception('Add a division first.'));
}
