// The organizer's run sheet: confirm each division's seeds, then publish
// every schedule at once; accepted teams missing a roster or their fee
// are flagged. The website's RunEvent does the same (no website tests:
// the API's tournaments.test.ts covers the endpoints both use).
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/group_tournament.dart';
import 'package:frisbee_app/domain/models/hosted_tournament.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/ui/tournaments/view_models/event_guide.dart';
import 'package:frisbee_app/ui/tournaments/view_models/hosted_tournament_viewmodel.dart';

import '../testing/fakes.dart';
import '../testing/hosted_tournament_fakes.dart';

void main() {
  final now = DateTime(2026, 11, 21, 11);
  late FakeHostedTournamentRepository repo;
  late FakeTeamRepository teams;

  setUp(() {
    repo = FakeHostedTournamentRepository();
    teams = FakeTeamRepository();
    teams.teams['host'] = Team(
      id: 'host',
      name: 'Denver Ultimate',
      division: Division.mixed,
      level: CompetitionLevel.club,
      ownerId: 'td',
      members: const {'td': TeamRole.owner},
      kind: TeamKind.community,
    );
    repo.tournaments['x'] = HostedTournament(
      id: 'x',
      hostId: 'host',
      hostName: 'Denver Ultimate',
      name: 'Spring Fling',
      startsOn: now.add(const Duration(days: 30)),
      status: HostedStatus.registration,
      bidFee: const BidFee(amountCents: 40000),
      entryDeadline: now.subtract(const Duration(days: 1)),
      divisions: const [
        DivisionSummary(
          id: 'd1',
          division: Division.mixed,
          level: CompetitionLevel.club,
        ),
      ],
    );
    repo.divisions['x'] = {
      'd1': TournamentDivision(
        id: 'd1',
        division: Division.mixed,
        level: CompetitionLevel.club,
        settings: TournamentSettings(
          startsAt: now.add(const Duration(days: 30)),
        ),
        seeds: const ['a', 'b', 'c', 'd'],
      ),
    };
    repo.entries['x'] = {
      for (final id in ['a', 'b', 'c', 'd'])
        id: TournamentEntry(
          teamId: id,
          teamName: 'Team $id',
          divisionId: 'd1',
          status: EntryStatus.accepted,
          roster: id == 'a' ? const [] : [for (var i = 0; i < 7; i++) '$id$i'],
        ),
    };
    repo.payments['x'] = {
      for (final id in ['b', 'c', 'd'])
        id: EntryPayment(teamId: id, paid: true),
    };
  });

  HostedTournamentViewModel page() {
    final vm = HostedTournamentViewModel(
      tournamentId: 'x',
      tournamentRepository: repo,
      teamRepository: teams,
      authRepository: FakeAuthRepository(
        user: const AppUser(uid: 'td', email: 'td@x.com'),
      ),
      postRepository: FakeTeamPostRepository(),
      now: () => now,
    );
    addTearDown(vm.dispose);
    return vm;
  }

  test(
    'flags teams missing a roster or their fee, past the deadline',
    () async {
      final vm = page();
      await pumpEventQueue();
      expect(vm.teamsMissingRoster.map((e) => e.teamId), ['a']);
      expect(vm.teamsUnpaid.map((e) => e.teamId), ['a']);
      expect(vm.pastDeadline, isTrue);
      expect(vm.isOverdue('a'), isTrue);
      expect(vm.isOverdue('b'), isFalse);
      final registration = EventGuide.of(vm, null).steps[1];
      expect(registration.detail, contains('1 missing a roster'));
      expect(registration.detail, contains('1 unpaid'));
    },
  );

  test('confirm seeds, then publish every schedule at once', () async {
    final vm = page();
    await pumpEventQueue();
    var guide = EventGuide.of(vm, null);
    expect(guide.steps[2].title, 'Confirm the seeds');
    expect(guide.steps[2].button?.action, GuideAction.confirmSeeds);
    expect(vm.allSeedsConfirmed, isFalse);

    await vm.confirmSeeds.execute('d1');
    await pumpEventQueue();
    expect(vm.allSeedsConfirmed, isTrue);
    guide = EventGuide.of(vm, null);
    expect(guide.steps[2].state, GuideStepState.done);
    expect(guide.steps[3].button?.action, GuideAction.publishAll);

    // Changing the order needs a new confirm.
    await vm.saveSeeds.execute(['b', 'a', 'c', 'd']);
    await pumpEventQueue();
    expect(vm.allSeedsConfirmed, isFalse);
    expect(
      EventGuide.of(vm, null).steps[3].button?.action,
      isNot(GuideAction.publishAll),
    );
    await vm.confirmSeeds.execute('d1');
    await pumpEventQueue();

    await vm.publishAll.execute();
    expect(vm.publishAll.completed, isTrue, reason: '${vm.publishAll.result}');
    await pumpEventQueue();
    expect(repo.games['x/d1'], isNotEmpty);
    expect(repo.tournaments['x']!.status, HostedStatus.scheduled);
  });

  test(
    "publishing all is refused until every division's seeds are confirmed",
    () async {
      final vm = page();
      await pumpEventQueue();
      await vm.publishAll.execute();
      expect(vm.publishAll.error, isTrue);
      expect(repo.games['x/d1'], isNull);
    },
  );

  test(
    "a division published alone isn't lost once the event is scheduled",
    () async {
      final d1 = repo.divisions['x']!['d1']!.copyWith(
        seedsConfirmedAt: () => DateTime(2026, 11, 20),
      );
      repo.divisions['x'] = {
        'd1': d1,
        'd2': TournamentDivision(
          id: 'd2',
          division: Division.women,
          level: CompetitionLevel.club,
          settings: d1.settings,
          seeds: const ['e', 'f'],
        ),
      };
      repo.tournaments['x'] = repo.tournaments['x']!.copyWith(
        divisions: const [
          DivisionSummary(
            id: 'd1',
            division: Division.mixed,
            level: CompetitionLevel.club,
          ),
          DivisionSummary(
            id: 'd2',
            division: Division.women,
            level: CompetitionLevel.club,
          ),
        ],
      );
      final vm = page();
      await pumpEventQueue();
      vm.selectDivision('d1');
      await pumpEventQueue();
      // The Schedule tab's single-division publish.
      await vm.publish.execute();
      await pumpEventQueue();
      expect(repo.tournaments['x']!.status, HostedStatus.scheduled);
      final schedule = EventGuide.of(vm, null).steps[3];
      expect(schedule.state, isNot(GuideStepState.done));
      expect(schedule.button?.action, GuideAction.publishSchedule);
      expect(schedule.button?.divisionId, 'd2');
    },
  );
}
