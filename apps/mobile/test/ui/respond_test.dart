// The respond flow (/tournaments/:id/respond): an invite's Accept or
// Decline, then the roster (or later), the fee (or later), then "Request
// confirmed!". The website's EnterTeam does the same; the website has no
// test runner, so the shared rules are checked by the API tests and
// fixtures/entry_checklist.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/group_tournament.dart';
import 'package:frisbee_app/domain/models/hosted_tournament.dart';
import 'package:frisbee_app/domain/models/roster_player.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/tournaments/view_models/respond_viewmodel.dart';
import 'package:frisbee_app/ui/tournaments/widgets/respond_screen.dart';

import '../testing/fakes.dart';
import '../testing/hosted_tournament_fakes.dart';

void main() {
  final now = DateTime(2026, 11, 21, 11);
  late FakeHostedTournamentRepository repo;
  late FakeTeamRepository teams;

  void seed({
    EntryStatus? entry,
    int feeCents = 40000,
    HostedStatus status = HostedStatus.registration,
    List<String> roster = const [],
  }) {
    repo.tournaments['x'] = HostedTournament(
      id: 'x',
      hostId: 'host',
      hostName: 'Denver Ultimate',
      name: 'Spring Fling',
      startsOn: now.add(const Duration(days: 30)),
      status: status,
      bidFee: feeCents == 0 ? null : BidFee(amountCents: feeCents),
      entryDeadline: now.add(const Duration(days: 20)),
      director: const TournamentDirector(name: 'Dana Director'),
    );
    repo.divisions['x'] = {
      'd1': TournamentDivision(
        id: 'd1',
        division: Division.mixed,
        level: CompetitionLevel.club,
        settings: TournamentSettings(startsAt: now),
      ),
    };
    if (entry != null) {
      repo.entries['x'] = {
        't1': TournamentEntry(
          teamId: 't1',
          teamName: 'Northside Flyers',
          divisionId: 'd1',
          status: entry,
          captainIds: const ['cap'],
          replyBy: now.add(const Duration(days: 10)),
          roster: roster,
        ),
      };
    }
  }

  setUp(() {
    repo = FakeHostedTournamentRepository();
    teams = FakeTeamRepository();
    teams.teams['t1'] = Team(
      id: 't1',
      name: 'Northside Flyers',
      division: Division.mixed,
      level: CompetitionLevel.club,
      ownerId: 'cap',
      members: const {'cap': TeamRole.owner, 'pat': TeamRole.player},
      memberNames: const {'cap': 'Name cap', 'pat': 'Name pat'},
    );
    teams.roster['t1'] = [
      for (var i = 0; i < 8; i++) RosterPlayer(id: 'p$i', name: 'Player $i'),
    ];
  });

  RespondViewModel open({String? team = 't1', String? step}) {
    final vm = RespondViewModel(
      tournamentId: 'x',
      teamId: team,
      step: step,
      tournamentRepository: repo,
      teamRepository: teams,
      authRepository: FakeAuthRepository(
        user: const AppUser(uid: 'cap', email: 'cap@x.com'),
      ),
      now: () => now,
    );
    addTearDown(vm.dispose);
    return vm;
  }

  group('view model', () {
    test(
      'an invite: Accept puts the team straight in, then roster, pay, done',
      () async {
        seed(entry: EntryStatus.invited);
        final vm = open();
        await pumpEventQueue();
        expect(vm.loaded, isTrue);
        expect(vm.blocked, isNull);
        expect(vm.mode, RespondMode.invite);
        expect(vm.step, RespondStep.respond);
        expect(vm.steps, [
          RespondStep.respond,
          RespondStep.roster,
          RespondStep.pay,
        ]);

        await vm.respond.execute();
        expect(vm.respond.completed, isTrue, reason: '${vm.respond.result}');
        expect(repo.entries['x']!['t1']!.status, EntryStatus.accepted);
        expect(repo.divisions['x']!['d1']!.seeds, ['t1']);
        // The mode stays: the flow's own write doesn't swap the screen.
        expect(vm.mode, RespondMode.invite);
        expect(vm.step, RespondStep.roster);
        await pumpEventQueue();
        // A first roster starts with everyone ticked.
        expect(vm.picked, hasLength(8));
        vm.togglePlayer('p0', false);
        await vm.saveRoster.execute();
        expect(repo.entries['x']!['t1']!.roster, hasLength(7));
        expect(vm.step, RespondStep.pay);
        vm.next(RespondStep.pay);
        expect(vm.step, RespondStep.done);
        expect(vm.status, EntryStatus.accepted);
        expect(vm.checklist.rosterSet, isTrue);
        expect(vm.checklist.paid, isFalse);
      },
    );

    test('Decline withdraws the entry with the reason', () async {
      seed(entry: EntryStatus.invited);
      final vm = open();
      await pumpEventQueue();
      await vm.decline.execute();
      expect(vm.step, RespondStep.declined);
      expect(repo.declined, [('x', 't1')]);
      expect(repo.entries['x']!['t1']!.reason, 'declined');
    });

    test(
      'roster and payment can both wait; without a fee there is no Pay',
      () async {
        seed(entry: EntryStatus.invited, feeCents: 0);
        final vm = open();
        await pumpEventQueue();
        expect(vm.steps, [RespondStep.respond, RespondStep.roster]);
        await vm.respond.execute();
        vm.next(RespondStep.roster);
        expect(vm.step, RespondStep.done);
        expect(vm.checklist.rosterSet, isFalse);
      },
    );

    test('an entered team picks up where it left off, or at ?step=', () async {
      seed(entry: EntryStatus.accepted);
      expect(open().step, RespondStep.respond); // not loaded yet
      final vm = open();
      await pumpEventQueue();
      expect(vm.mode, RespondMode.entered);
      expect(vm.step, RespondStep.roster);

      repo.entries['x']!['t1'] = repo.entries['x']!['t1']!.copyWith(
        roster: [for (var i = 0; i < 7; i++) 'p$i'],
      );
      final paying = open();
      await pumpEventQueue();
      expect(paying.step, RespondStep.pay);

      final captains = open(step: 'captains');
      await pumpEventQueue();
      expect(captains.step, RespondStep.respond);
      expect(captains.captains, {'cap'});
    });

    test('an expired invite, or a closed event, says why', () async {
      seed(entry: EntryStatus.invited);
      repo.entries['x']!['t1'] = TournamentEntry(
        teamId: 't1',
        teamName: 'Northside Flyers',
        divisionId: 'd1',
        status: EntryStatus.invited,
        replyBy: now.subtract(const Duration(days: 1)),
      );
      final expired = open();
      await pumpEventQueue();
      expect(expired.blocked, TournamentEntry.expiredMessage);

      seed(status: HostedStatus.scheduled);
      final closed = open(team: null);
      await pumpEventQueue();
      expect(closed.mode, RespondMode.apply);
      expect(closed.blocked, "Registration isn't open.");
    });

    test('applying to a public event sends a request', () async {
      seed();
      final vm = open(team: null);
      await pumpEventQueue();
      expect(vm.mode, RespondMode.apply);
      expect(vm.teamId, 't1');
      await vm.respond.execute();
      expect(repo.entries['x']!['t1']!.status, EntryStatus.applied);
      expect(vm.status, EntryStatus.applied);
    });
  });

  group('screen', () {
    Future<void> pump(WidgetTester tester, RespondViewModel vm) async {
      tester.view.physicalSize = const Size(500, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: RespondScreen(viewModel: vm),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('Accept, Set later, Pay later, then Request confirmed!', (
      tester,
    ) async {
      seed(entry: EntryStatus.invited);
      final vm = open();
      await pump(tester, vm);
      expect(find.text('Respond to the invite'), findsOneWidget);
      expect(find.text('Step 1 of 3 · Respond'), findsOneWidget);
      expect(find.text('Dana Director'), findsOneWidget);
      expect(find.text('Roster and fee due'), findsOneWidget);
      expect(find.text('Reply by'), findsOneWidget);

      await tester.tap(find.byKey(const Key('respond-accept')));
      await tester.pumpAndSettle();
      expect(find.text('Step 2 of 3 · Roster'), findsOneWidget);
      await tester.tap(find.byKey(const Key('roster-later')));
      await tester.pumpAndSettle();
      expect(find.text('Step 3 of 3 · Payment'), findsOneWidget);
      await tester.tap(find.byKey(const Key('pay-later')));
      await tester.pumpAndSettle();
      expect(find.text('Request confirmed!'), findsOneWidget);
      expect(find.text('Roster to set'), findsOneWidget);
      expect(find.text('Fee to pay'), findsOneWidget);
    });

    testWidgets('Decline asks first, then says so', (tester) async {
      seed(entry: EntryStatus.invited);
      final vm = open();
      await pump(tester, vm);
      await tester.tap(find.byKey(const Key('respond-decline')));
      await tester.pumpAndSettle();
      expect(find.text('Decline the invite?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Decline'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('respond-declined')), findsOneWidget);
      expect(repo.declined, [('x', 't1')]);
    });
  });
}
