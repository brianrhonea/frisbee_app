import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/group_tournament.dart';
import 'package:frisbee_app/domain/models/hosted_tournament.dart';
import 'package:frisbee_app/domain/models/roster_player.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/tournament_engine/progress.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/tournaments/view_models/hosted_tournament_form_viewmodel.dart';
import 'package:frisbee_app/ui/tournaments/view_models/hosted_tournament_viewmodel.dart';
import 'package:frisbee_app/ui/tournaments/view_models/hosted_tournaments_viewmodel.dart';
import 'package:frisbee_app/ui/tournaments/widgets/hosted_tournament_screen.dart';
import 'package:frisbee_app/utils/result.dart';

import '../testing/fakes.dart';
import '../testing/hosted_tournament_fakes.dart';

void main() {
  late FakeTeamRepository teams;
  late FakeHostedTournamentRepository repo;
  late FakeTeamPostRepository posts;

  Team team(
    String id,
    String owner, {
    TeamKind kind = TeamKind.team,
    Map<String, TeamRole> more = const {},
  }) {
    final members = {owner: TeamRole.owner, ...more};
    return Team(
      id: id,
      name: 'Team $id',
      division: Division.mixed,
      level: CompetitionLevel.club,
      ownerId: owner,
      members: members,
      memberNames: {for (final m in members.keys) m: 'Name $m'},
      kind: kind,
    );
  }

  setUp(() {
    teams = FakeTeamRepository();
    repo = FakeHostedTournamentRepository();
    posts = FakeTeamPostRepository();
    // A group hosts; "director" runs it, "fan" is just a member.
    teams.teams['host'] = team(
      'host',
      'director',
      kind: TeamKind.community,
      more: {'fan': TeamRole.player},
    );
    // Four club teams; capN owns teamN.
    for (var i = 1; i <= 4; i++) {
      teams.teams['t$i'] = team('t$i', 'cap$i', more: {'p$i': TeamRole.player});
      // Enough to register (TournamentDivision.defaultMinRoster).
      teams.roster['t$i'] = [
        for (var n = 1; n <= TournamentDivision.defaultMinRoster; n++)
          RosterPlayer(id: 't$i-$n', name: 'Player $n'),
      ];
    }
  });

  FakeAuthRepository as(String uid) => FakeAuthRepository(
    user: AppUser(uid: uid, email: '$uid@x.com'),
  );

  Future<HostedTournamentViewModel> page(String uid, String id) async {
    final vm = HostedTournamentViewModel(
      tournamentId: id,
      tournamentRepository: repo,
      teamRepository: teams,
      authRepository: as(uid),
      postRepository: posts,
      now: () => DateTime(2027, 4, 10),
    );
    await pumpEventQueue();
    return vm;
  }

  /// The director hosts a public tournament with one division and opens
  /// registration.
  Future<String> host({BidFee? fee}) async {
    final form = HostedTournamentFormViewModel(
      hostId: 'host',
      tournamentRepository: repo,
      teamRepository: teams,
      authRepository: as('director'),
      now: () => DateTime(2027, 3, 1),
    );
    await pumpEventQueue();
    expect(form.canHost, isTrue);
    form.name = 'Spring Fling';
    form.location = 'City Park';
    if (fee != null) {
      form.setHasFee(true);
      form.feeAmount = '${fee.amountCents / 100}';
      form.setFeeDue(fee.dueAt);
    }
    // One Club Mixed division, opened by the form with the event's format.
    form.setFormat(form.format.copyWith(maxTeams: 4));
    await form.save.execute();
    final id = (form.save.result as Ok<String>).value;
    form.dispose();
    final vm = await page('director', id);
    expect(vm.isManager, isTrue);
    expect(vm.tournament!.status, HostedStatus.draft);
    await pumpEventQueue();
    expect(vm.divisions, hasLength(1));
    expect(vm.division!.label, 'Club Mixed');
    await vm.setStatus.execute(HostedStatus.registration);
    await pumpEventQueue();
    vm.dispose();
    return id;
  }

  test('only managers can host', () async {
    final form = HostedTournamentFormViewModel(
      hostId: 'host',
      tournamentRepository: repo,
      teamRepository: teams,
      authRepository: as('fan'),
    );
    await pumpEventQueue();
    form.name = 'Mine';
    expect(form.canHost, isFalse);
    await form.save.execute();
    expect(form.save.error, isTrue);
    expect(repo.tournaments, isEmpty);
  });

  test('the form checks the bid fee and saves it in cents', () async {
    final id = await host(
      fee: BidFee(amountCents: 25050, dueAt: DateTime(2027, 4, 1)),
    );
    final t = repo.tournaments[id]!;
    expect(t.bidFee!.amountCents, 25050);
    expect(t.bidFee!.label, r'$250.50');
    expect(t.name, 'Spring Fling');
    expect(t.hostName, 'Team host');
  });

  test('teams apply; the host accepts up to the cap, then waitlists', () async {
    final id = await host();
    final vms = <HostedTournamentViewModel>[];
    for (var i = 1; i <= 4; i++) {
      final cap = await page('cap$i', id);
      vms.add(cap);
      expect(cap.canApply, isTrue);
      expect(cap.myAdminTeams.single.id, 't$i');
      await cap.apply.execute((
        teamId: 't$i',
        divisionId: cap.divisions.single.id,
        captainIds: ['cap$i', 'p$i'],
      ));
      expect(cap.apply.completed, isTrue, reason: '${cap.apply.result}');
    }
    // Players can't apply for their team.
    final player = await page('p1', id);
    expect(player.myAdminTeams, isEmpty);
    expect(player.canApply, isFalse);

    final dir = await page('director', id);
    expect(dir.entriesWith(EntryStatus.applied), hasLength(4));
    // Lower the cap to 3 to see the limit.
    await dir.saveDivision.execute(dir.division!.copyWith(maxTeams: 3));
    await pumpEventQueue();
    for (final e in [...dir.entriesWith(EntryStatus.applied)]) {
      await dir.decide.execute((entry: e, status: EntryStatus.accepted));
      await pumpEventQueue();
    }
    expect(dir.division!.seeds, hasLength(3));
    expect(dir.decide.error, isTrue); // the fourth didn't fit
    dir.decide.clearResult();
    final left = dir.entriesWith(EntryStatus.applied).single;
    await dir.decide.execute((entry: left, status: EntryStatus.waitlisted));
    await pumpEventQueue();
    expect(dir.entryOf(left.teamId)!.status, EntryStatus.waitlisted);
    // Captains came along for score reporting.
    expect(dir.division!.captains['t1'], ['cap1', 'p1']);

    // A team withdraws: out of the seeds.
    await vms.first.decide.execute((
      entry: vms.first.myEntries.single,
      status: EntryStatus.withdrawn,
    ));
    await pumpEventQueue();
    expect(dir.division!.seeds, isNot(contains('t1')));
    for (final v in [...vms, player, dir]) {
      v.dispose();
    }
  });

  test('invite only: the host invites, the team accepts', () async {
    final id = await host();
    repo.tournaments[id] = repo.tournaments[id]!.copyWith(
      visibility: TournamentVisibility.inviteOnly,
    );
    final dir = await page('director', id);
    final cap = await page('cap2', id);
    expect(cap.canApply, isFalse);
    await dir.invite.execute((
      team: TeamListing.of(teams.teams['t2']!),
      divisionId: dir.division!.id,
    ));
    await pumpEventQueue();
    final invite = cap.myEntries.single;
    expect(invite.status, EntryStatus.invited);
    await cap.apply.execute((
      teamId: 't2',
      divisionId: invite.divisionId,
      captainIds: ['cap2'],
    ));
    await pumpEventQueue();
    expect(dir.entryOf('t2')!.status, EntryStatus.applied);
    dir.dispose();
    cap.dispose();
  });

  test('bid fees: paid toggles, overdue and the unpaid count', () async {
    final id = await host(
      fee: BidFee(amountCents: 20000, dueAt: DateTime(2027, 4, 1)),
    );
    for (var i = 1; i <= 2; i++) {
      final cap = await page('cap$i', id);
      await cap.apply.execute((
        teamId: 't$i',
        divisionId: cap.divisions.single.id,
        captainIds: ['cap$i'],
      ));
      cap.dispose();
    }
    final dir = await page('director', id);
    for (final e in [...dir.entriesWith(EntryStatus.applied)]) {
      await dir.decide.execute((entry: e, status: EntryStatus.accepted));
      await pumpEventQueue();
    }
    expect(dir.unpaidCount, 2);
    expect(dir.isOverdue('t1'), isTrue); // due Apr 1, now Apr 10
    await dir.setPaid.execute((teamId: 't1', paid: true));
    await pumpEventQueue();
    expect(dir.isPaid('t1'), isTrue);
    expect(dir.isOverdue('t1'), isFalse);
    expect(dir.unpaidCount, 1);
    // A team's admin sees their own payment.
    final cap = await page('cap1', id);
    expect(cap.canSeePayments, isTrue);
    expect(cap.isPaid('t1'), isTrue);
    dir.dispose();
    cap.dispose();
  });

  test('seed, publish, report, confirm and finish with placements', () async {
    final id = await host();
    for (var i = 1; i <= 4; i++) {
      final cap = await page('cap$i', id);
      await cap.apply.execute((
        teamId: 't$i',
        divisionId: cap.divisions.single.id,
        captainIds: ['cap$i'],
      ));
      cap.dispose();
    }
    final dir = await page('director', id);
    for (final e in [...dir.entriesWith(EntryStatus.applied)]) {
      await dir.decide.execute((entry: e, status: EntryStatus.accepted));
      await pumpEventQueue();
    }
    // Seed t4 first, then the rest.
    await dir.saveSeeds.execute(['t4', 't1', 't2', 't3']);
    await pumpEventQueue();
    expect(dir.division!.seeds.first, 't4');
    // Four teams: a single round robin pool, then a placement bracket.
    await dir.saveDivision.execute(
      dir.division!.copyWith(
        settings: dir.division!.settings.copyWith(
          format: TournamentFormat.poolsPlacement,
          poolCount: 1,
        ),
      ),
    );
    await pumpEventQueue();
    expect(dir.preview().plan, isNotNull);
    await dir.publish.execute();
    await pumpEventQueue();
    expect(dir.publish.completed, isTrue, reason: '${dir.publish.result}');
    expect(dir.isPublished, isTrue);
    expect(dir.tournament!.status, HostedStatus.scheduled);

    // Captain t4 reports the first game t4 plays; the other confirms.
    final cap4 = await page('cap4', id);
    final first = cap4.myUpcoming.first;
    expect(cap4.actionFor(first), HostedGameAction.report);
    final t4IsA = first.teamA == 't4';
    await cap4.report.execute((
      gameId: first.id,
      scoreA: t4IsA ? 15 : 10,
      scoreB: t4IsA ? 10 : 15,
    ));
    await pumpEventQueue();
    final other = first.teamA == 't4' ? first.teamB! : first.teamA!;
    final otherCap = await page('cap${other.substring(1)}', id);
    final reported = otherCap.games.firstWhere((g) => g.id == first.id);
    expect(otherCap.actionFor(reported), HostedGameAction.confirm);
    await otherCap.confirm.execute(reported);
    await pumpEventQueue();
    expect(dir.games.firstWhere((g) => g.id == first.id).isDone, isTrue);
    expect(dir.tournament!.status, HostedStatus.live);

    // The director plays out the rest: better seed wins.
    final seeds = dir.division!.seeds;
    for (var guard = 0; guard < 50; guard++) {
      if (dir.canSeedBracket) {
        await dir.seedBracket.execute();
        await pumpEventQueue();
      }
      final g = gamesToPlay(dir.games).where((g) => g.hasTeams).firstOrNull;
      if (g == null) break;
      final aWins = seeds.indexOf(g.teamA!) < seeds.indexOf(g.teamB!);
      await dir.setFinalScore.execute((
        gameId: g.id,
        scoreA: aWins ? 15 : 9,
        scoreB: aWins ? 9 : 15,
      ));
      await pumpEventQueue();
    }
    expect(gamesToPlay(dir.games), isEmpty);
    expect(dir.placements, ['t4', 't1', 't2', 't3']);
    expect(dir.championId, 't4');
    // Saved on the division, and the tournament is final.
    expect(repo.divisions[id]!.values.single.placements, hasLength(4));
    expect(dir.tournament!.status, HostedStatus.finished);
    for (final v in [dir, cap4, otherCap]) {
      v.dispose();
    }
  });

  test('a list filters by status when it has more than one', () async {
    final id = await host();
    repo.tournaments['draft'] = repo.tournaments[id]!.copyWith(
      id: 'draft',
      status: HostedStatus.draft,
    );
    final managerList = HostedTournamentsViewModel(
      hostId: 'host',
      tournamentRepository: repo,
      teamRepository: teams,
      authRepository: as('director'),
    );
    final fanList = HostedTournamentsViewModel(
      hostId: 'host',
      tournamentRepository: repo,
      teamRepository: teams,
      authRepository: as('fan'),
    );
    await pumpEventQueue();
    final published = repo.tournaments[id]!.status;
    expect(managerList.filtersByStatus, isTrue);
    expect(managerList.statusCounts, {HostedStatus.draft: 1, published: 1});
    managerList.setStatusFilter(HostedStatus.draft);
    expect([for (final t in managerList.tournaments) t.id], ['draft']);
    managerList.setStatusFilter(null);
    expect(managerList.tournaments, hasLength(2));
    // Fans don't see the draft, so there's only one status: no filter.
    expect(fanList.filtersByStatus, isFalse);
    fanList.setStatusFilter(HostedStatus.draft);
    expect(fanList.tournaments, hasLength(1));
    managerList.dispose();
    fanList.dispose();
  });

  test("a host's list hides drafts from non-managers", () async {
    final id = await host();
    repo.tournaments['draft'] = repo.tournaments[id]!.copyWith(
      id: 'draft',
      status: HostedStatus.draft,
    );
    final managerList = HostedTournamentsViewModel(
      hostId: 'host',
      tournamentRepository: repo,
      teamRepository: teams,
      authRepository: as('director'),
    );
    final fanList = HostedTournamentsViewModel(
      hostId: 'host',
      tournamentRepository: repo,
      teamRepository: teams,
      authRepository: as('fan'),
    );
    await pumpEventQueue();
    expect(managerList.canHost, isTrue);
    expect(managerList.tournaments, hasLength(2));
    expect(fanList.canHost, isFalse);
    expect(fanList.tournaments.map((t) => t.id), [id]);
    managerList.dispose();
    fanList.dispose();
  });

  test("a team's members see the tournaments it plays in", () async {
    repo.entered['t1'] = [
      EnteredTournament(
        tournamentId: 'later',
        name: 'Later Open',
        status: EntryStatus.applied,
        startsOn: DateTime(2027, 6, 1),
      ),
      EnteredTournament(
        tournamentId: 'soon',
        name: 'Spring Classic',
        status: EntryStatus.accepted,
        startsOn: DateTime(2027, 5, 1),
      ),
      const EnteredTournament(
        tournamentId: 'gone',
        name: 'Withdrew',
        status: EntryStatus.withdrawn,
      ),
    ];
    HostedTournamentsViewModel list(String uid) => HostedTournamentsViewModel(
      hostId: 't1',
      tournamentRepository: repo,
      teamRepository: teams,
      authRepository: as(uid),
    );
    final player = list('p1');
    final outsider = list('cap2');
    await pumpEventQueue();
    expect(player.playingIn.map((e) => e.tournamentId), ['soon', 'later']);
    expect(outsider.playingIn, isEmpty);
    player.dispose();
    outsider.dispose();
  });

  test('a team needs ${TournamentDivision.defaultMinRoster} players on its '
      'roster to register', () async {
    final id = await host();
    teams.roster['t1'] = teams.roster['t1']!.take(6).toList();
    final cap = await page('cap1', id);
    addTearDown(cap.dispose);
    final application = (
      teamId: 't1',
      divisionId: cap.divisions.single.id,
      captainIds: ['cap1'],
    );
    await cap.apply.execute(application);
    expect(
      (cap.apply.result as Error).error,
      isA<RosterTooSmallException>().having(
        (e) => e.toString(),
        'message',
        contains('at least 7 players'),
      ),
    );
    expect(repo.entries[id]?['t1'], isNull);
    teams.roster['t1'] = [
      ...teams.roster['t1']!,
      const RosterPlayer(id: 'new', name: 'Seventh'),
    ];
    await cap.apply.execute(application);
    expect(cap.apply.result, isA<Ok<void>>());
    expect(repo.entries[id]!['t1']!.status, EntryStatus.applied);
  });

  testWidgets('the page shows the overview and tabs', (tester) async {
    final id = await tester.runAsync(host);
    final vm = HostedTournamentViewModel(
      tournamentId: id!,
      tournamentRepository: repo,
      teamRepository: teams,
      authRepository: as('director'),
      postRepository: posts,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: HostedTournamentScreen(viewModel: vm),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Spring Fling'), findsOneWidget);
    expect(find.text('Registration open'), findsOneWidget);
    expect(find.text('Club Mixed'), findsOneWidget);
    expect(find.text('Close registration'), findsOneWidget);
    await tester.tap(find.text('Teams'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Teams (0 of 4)'), findsOneWidget);
    await tester.tap(find.text('Schedule'));
    await tester.pumpAndSettle();
    expect(find.text('Publish schedule'), findsOneWidget);
    await tester.tap(find.text('News'));
    await tester.pumpAndSettle();
    expect(find.text('No news yet'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    vm.dispose();
  });

  Future<void> open(WidgetTester tester, HostedTournamentViewModel vm) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: HostedTournamentScreen(viewModel: vm),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets("a team that withdrew is gone from the host's list", (
    tester,
  ) async {
    final id = (await tester.runAsync(host))!;
    final division = repo.divisions[id]!.keys.single;
    await tester.runAsync(() async {
      for (final (team, status) in [
        ('t1', EntryStatus.withdrawn),
        ('t2', EntryStatus.declined),
        ('t3', EntryStatus.applied),
      ]) {
        await repo.saveEntry(
          id,
          TournamentEntry(
            teamId: team,
            teamName: 'Team $team',
            divisionId: division,
            status: status,
          ),
        );
      }
    });
    final vm = HostedTournamentViewModel(
      tournamentId: id,
      tournamentRepository: repo,
      teamRepository: teams,
      authRepository: as('director'),
      postRepository: posts,
    );
    await open(tester, vm);
    await tester.tap(find.text('Teams'));
    await tester.pumpAndSettle();
    expect(find.text('Team t1'), findsNothing);
    expect(find.text('Declined'), findsWidgets);
    expect(find.text('Team t2'), findsOneWidget);
    expect(find.text('Team t3'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    vm.dispose();
  });

  testWidgets('withdrawing asks first, and says what it does', (tester) async {
    final id = (await tester.runAsync(host))!;
    final division = repo.divisions[id]!.keys.single;
    await tester.runAsync(
      () => repo.saveEntry(
        id,
        TournamentEntry(
          teamId: 't1',
          teamName: 'Team t1',
          divisionId: division,
          status: EntryStatus.accepted,
        ),
      ),
    );
    final vm = HostedTournamentViewModel(
      tournamentId: id,
      tournamentRepository: repo,
      teamRepository: teams,
      authRepository: as('cap1'),
      postRepository: posts,
    );
    await open(tester, vm);
    await tester.ensureVisible(find.text('Withdraw'));
    await tester.tap(find.text('Withdraw'));
    await tester.pumpAndSettle();
    expect(find.text('Withdraw Team t1?'), findsOneWidget);
    expect(find.textContaining('off your schedule'), findsOneWidget);
    // Cancel keeps the team in.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repo.entries[id]!['t1']!.status, EntryStatus.accepted);
    await tester.tap(find.text('Withdraw'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Withdraw'));
    await tester.pumpAndSettle();
    expect(repo.entries[id]!['t1']!.status, EntryStatus.withdrawn);
    await tester.pumpWidget(const SizedBox());
    vm.dispose();
  });
}
