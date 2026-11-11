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
