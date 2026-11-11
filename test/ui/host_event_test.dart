import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/hosted_tournament.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/domain/models/group_tournament.dart';
import 'package:frisbee_app/ui/tournaments/view_models/host_event_viewmodel.dart';
import 'package:frisbee_app/ui/tournaments/view_models/hosted_tournament_form_viewmodel.dart';
import 'package:frisbee_app/ui/tournaments/view_models/hosted_tournament_viewmodel.dart';
import 'package:frisbee_app/ui/tournaments/view_models/hosted_tournaments_viewmodel.dart';
import 'package:frisbee_app/ui/tournaments/widgets/host_event_screen.dart';
import 'package:frisbee_app/utils/result.dart';

import '../testing/fakes.dart';
import '../testing/hosted_tournament_fakes.dart';

void main() {
  late FakeTeamRepository teams;
  late FakeHostedTournamentRepository repo;

  Team team(String id, TeamKind kind, String owner) => Team(
    id: id,
    name: 'Org $id',
    division: Division.mixed,
    level: CompetitionLevel.club,
    ownerId: owner,
    members: {owner: TeamRole.owner},
    memberNames: {owner: 'Name $owner'},
    kind: kind,
  );

  FakeAuthRepository as(String uid) => FakeAuthRepository(
    user: AppUser(uid: uid, email: '$uid@x.com', displayName: 'Player $uid'),
  );

  setUp(() {
    teams = FakeTeamRepository();
    repo = FakeHostedTournamentRepository();
  });

  test('lists the groups and clubs the user can host from', () async {
    teams.teams['club'] = team('club', TeamKind.organization, 'me');
    teams.teams['squad'] = team('squad', TeamKind.team, 'me');
    teams.teams['other'] = team('other', TeamKind.organization, 'someone');
    final vm = HostEventViewModel(
      teamRepository: teams,
      authRepository: as('me'),
    );
    await pumpEventQueue();
    expect(vm.loaded, isTrue);
    // Clubs and groups come first, and only the user's own.
    expect(vm.hosts.map((t) => t.id), ['club', 'squad']);
    vm.dispose();
  });

  test(
    'official organizers like Stall 10 come first, in their own section',
    () async {
      teams.teams['club'] = team('club', TeamKind.organization, 'me');
      teams.teams['group'] = team('group', TeamKind.community, 'me');
      teams.teams['squad'] = team('squad', TeamKind.team, 'me');
      teams.teams['stall10'] = Team.fromMap('stall10', {
        ...team('stall10', TeamKind.organization, 'me').toEditableMap(),
        'kind': 'organization',
        'ownerId': 'me',
        'members': {'me': 'owner'},
        'official': true,
      });
      final vm = HostEventViewModel(
        teamRepository: teams,
        authRepository: as('me'),
      );
      await pumpEventQueue();
      expect(vm.sections.map((s) => s.kind), [
        HostSectionKind.official,
        HostSectionKind.organizations,
        HostSectionKind.groups,
        HostSectionKind.teams,
      ]);
      expect(vm.sections.first.teams.single.id, 'stall10');
      expect(vm.hosts.map((t) => t.id), ['stall10', 'club', 'group', 'squad']);
      vm.dispose();
    },
  );

  test('an official host badges the events it hosts', () async {
    teams.teams['stall10'] = Team.fromMap('stall10', {
      ...team('stall10', TeamKind.organization, 'me').toEditableMap(),
      'kind': 'organization',
      'ownerId': 'me',
      'members': {'me': 'owner'},
      'official': true,
    });
    final form = HostedTournamentFormViewModel(
      hostId: 'stall10',
      tournamentRepository: repo,
      teamRepository: teams,
      authRepository: as('me'),
      type: HostedType.league,
    );
    await pumpEventQueue();
    form.name = 'Summer League';
    await form.save.execute();
    expect(form.save.result, isA<Ok<String>>(), reason: '${form.save.result}');
    expect(repo.tournaments.values.single.hostOfficial, isTrue);
    form.dispose();
  });

  testWidgets('with no host, it offers to start a club or group', (
    tester,
  ) async {
    final vm = HostEventViewModel(
      teamRepository: teams,
      authRepository: as('me'),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: HostEventScreen(viewModel: vm),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining("You don't run"), findsOneWidget);
    expect(find.text('Start a school or club'), findsOneWidget);
    expect(find.text('Start a community group'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    vm.dispose();
  });

  testWidgets('a host is listed to pick', (tester) async {
    teams.teams['club'] = team('club', TeamKind.organization, 'me');
    final vm = HostEventViewModel(
      teamRepository: teams,
      authRepository: as('me'),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: HostEventScreen(viewModel: vm),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Org club'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    vm.dispose();
  });

  test('the list can be narrowed to leagues or hat tournaments', () async {
    HostedTournament event(String id, HostedKind kind, bool players) =>
        HostedTournament(
          id: id,
          hostId: 'h',
          hostName: 'Stall 10',
          name: 'Event $id',
          startsOn: DateTime(2027, 6, 3),
          endsOn: DateTime(2027, 6, 4),
          status: HostedStatus.registration,
          kind: kind,
          entryType: players
              ? TournamentEntryType.players
              : TournamentEntryType.teams,
        );
    repo.tournaments['a'] = event('a', HostedKind.tournament, false);
    repo.tournaments['b'] = event('b', HostedKind.tournament, true);
    repo.tournaments['c'] = event('c', HostedKind.league, true);
    final vm = HostedTournamentsViewModel(
      tournamentRepository: repo,
      authRepository: as('me'),
    );
    await pumpEventQueue();
    expect(vm.filtersByType, isTrue);
    expect(vm.tournaments, hasLength(3));
    vm.setTypeFilter(HostedType.league);
    expect(vm.tournaments.map((t) => t.id), ['c']);
    vm.setTypeFilter(HostedType.hat);
    expect(vm.tournaments.map((t) => t.id), ['b']);
    vm.setTypeFilter(null);
    vm.setQuery('league');
    expect(vm.tournaments.map((t) => t.id), ['c']);
    vm.dispose();
  });

  test('a host picker choice starts the form on that kind', () async {
    teams.teams['club'] = team('club', TeamKind.organization, 'me');
    HostedTournamentFormViewModel form(HostedType? type) =>
        HostedTournamentFormViewModel(
          hostId: 'club',
          tournamentRepository: repo,
          teamRepository: teams,
          authRepository: as('me'),
          type: type,
        );
    final league = form(HostedType.league);
    expect(league.kind, HostedKind.league);
    final hat = form(HostedType.hat);
    expect(hat.kind, HostedKind.tournament);
    expect(hat.entryType, TournamentEntryType.players);
    final plain = form(null);
    expect(plain.kind, HostedKind.tournament);
    expect(plain.entryType, TournamentEntryType.teams);
    for (final f in [league, hat, plain]) {
      f.dispose();
    }
  });

  group('one format for every division', () {
    HostedTournamentFormViewModel newLeague() => HostedTournamentFormViewModel(
      hostId: 'club',
      tournamentRepository: repo,
      teamRepository: teams,
      authRepository: as('me'),
      type: HostedType.league,
    );

    /// Mini League April 2027: 8 weeks from Saturday April 3, games at
    /// 6pm, 3v3 with 4 on a roster, 25-minute timed games.
    Future<String> miniLeague() async {
      teams.teams['club'] = team('club', TeamKind.organization, 'me');
      final f = newLeague();
      await pumpEventQueue();
      f.name = 'Mini League April 2027';
      f.setFirstNight(DateTime(2027, 4, 3));
      f.setSeason(const LeagueSeason(weeks: 8));
      f.setFirstGame(18, 0);
      f.setFieldSize(3);
      f.setFormat(f.format.copyWith(minRoster: () => 4));
      f.setSettings(
        f.settings.copyWith(scoring: ScoringMode.time, gameMinutes: 25),
      );
      f.setOpen(Division.women, true);
      expect(f.problem, isNull);
      await f.save.execute();
      expect(f.save.result, isA<Ok<String>>(), reason: '${f.save.result}');
      f.dispose();
      return repo.tournaments.keys.single;
    }

    test('ticked divisions open with the same format', () async {
      final id = await miniLeague();
      final t = repo.tournaments[id]!;
      expect(t.format!.settings.playersOnField, 3);
      expect(t.endsOn, DateTime(2027, 5, 22));
      final ds = repo.divisions[id]!.values.toList();
      expect(ds.map((d) => d.label), ['League Mixed', 'League Women']);
      for (final d in ds) {
        expect(d.settings.playersOnField, 3);
        expect(d.effectiveMinRoster, 4);
        expect(d.settings.timed, isTrue);
        expect(d.settings.gameMinutes, 25);
        expect(d.settings.scoreLabel, '25 min timed');
        // Saturdays at 6pm, from the first night.
        expect(d.settings.startsAt, DateTime(2027, 4, 3, 18));
        // The season has playoffs, so a bracket follows the table.
        expect(t.season!.hasPlayoffs, isTrue);
        expect(d.settings.format, TournamentFormat.singleElim);
      }
      expect(t.divisions.map((d) => d.label), ['League Mixed', 'League Women']);
    });

    test(
      'a format change reaches every division; empty ones can close',
      () async {
        final id = await miniLeague();
        final f = HostedTournamentFormViewModel(
          tournamentId: id,
          tournamentRepository: repo,
          teamRepository: teams,
          authRepository: as('me'),
        );
        await pumpEventQueue();
        expect(f.divisions, {Division.mixed, Division.women});
        expect(f.settings.playersOnField, 3);
        // Mixed has a team in it now, so it stays.
        final mixed = repo.divisions[id]!.values.first;
        repo.divisions[id]![mixed.id] = mixed.copyWith(seeds: ['t1']);
        repo.tournaments[id] = repo.tournaments[id]!.copyWith(name: 'x');
        final f2 = HostedTournamentFormViewModel(
          tournamentId: id,
          tournamentRepository: repo,
          teamRepository: teams,
          authRepository: as('me'),
        );
        await pumpEventQueue();
        f.dispose();
        expect(f2.lockedReason(Division.mixed), isNotNull);
        f2.setOpen(Division.mixed, false);
        expect(f2.isOpen(Division.mixed), isTrue);
        f2.setOpen(Division.women, false);
        f2.setFieldSize(4);
        await f2.save.execute();
        expect(f2.save.result, isA<Ok<String>>(), reason: '${f2.save.result}');
        f2.dispose();
        final left = repo.divisions[id]!.values.single;
        expect(left.label, 'League Mixed');
        expect(left.settings.playersOnField, 4);
        expect(left.seeds, ['t1']);
        expect(repo.tournaments[id]!.divisions.single.id, left.id);
      },
    );

    test('at least one division', () async {
      teams.teams['club'] = team('club', TeamKind.organization, 'me');
      final f = newLeague();
      await pumpEventQueue();
      f.name = 'Empty';
      f.setOpen(Division.mixed, false);
      expect(f.problem, 'Open at least one division.');
      f.dispose();
    });
  });

  test('league divisions take teams of their division and level', () {
    TournamentDivision division(Division d, CompetitionLevel l) =>
        TournamentDivision(
          id: 'd',
          division: d,
          level: l,
          settings: TournamentSettings(startsAt: DateTime(2027)),
        );
    final squad = team('s', TeamKind.team, 'me');
    final fit = HostedTournamentViewModel.leagueFitProblem;
    expect(fit(squad, division(Division.mixed, CompetitionLevel.club)), isNull);
    expect(
      fit(squad, division(Division.women, CompetitionLevel.club)),
      contains('Women'),
    );
    expect(
      fit(squad, division(Division.mixed, CompetitionLevel.college)),
      contains('College'),
    );
    // A League-level division takes any level.
    expect(
      fit(squad, division(Division.mixed, CompetitionLevel.league)),
      isNull,
    );
  });
}
