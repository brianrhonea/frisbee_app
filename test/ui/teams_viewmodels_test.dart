import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/tournament.dart';
import 'package:frisbee_app/ui/teams/view_models/create_team_viewmodel.dart';
import 'package:frisbee_app/ui/teams/view_models/team_detail_viewmodel.dart';
import 'package:frisbee_app/ui/teams/view_models/teams_viewmodel.dart';
import 'package:frisbee_app/ui/tournaments/view_models/tournaments_viewmodel.dart';
import 'package:frisbee_app/utils/result.dart';

import '../testing/fakes.dart';

void main() {
  late FakeTeamRepository teams;
  late FakeAuthRepository auth;

  setUp(() {
    teams = FakeTeamRepository();
    auth = FakeAuthRepository(user: testUser);
  });

  test('create team then it appears in my teams', () async {
    final list = TeamsViewModel(teamRepository: teams, authRepository: auth);
    final create = CreateTeamViewModel(
      teamRepository: teams,
      authRepository: auth,
    );
    await pumpEventQueue();
    expect(list.loading, isFalse);
    expect(list.teams, isEmpty);

    await create.create.execute(
      const NewTeam(
        name: 'Ring',
        division: Division.mixed,
        level: CompetitionLevel.club,
      ),
    );
    expect(create.create.result, isA<Ok<String>>());
    await pumpEventQueue();
    expect(list.teams.single.name, 'Ring');
    expect(list.roleIn(list.teams.single), TeamRole.owner);
  });

  test('join reports errors for unknown codes', () async {
    final vm = TeamsViewModel(teamRepository: teams, authRepository: auth);
    await vm.joinTeam.execute('NOPE');
    expect(vm.joinTeam.error, isTrue);
  });

  group('TeamDetailViewModel permissions', () {
    TeamDetailViewModel detailFor(TeamRole role) {
      teams.teams['t1'] = teamWith({
        'owner': TeamRole.owner,
        'coach': TeamRole.coach,
        'player': TeamRole.player,
        if (role != TeamRole.owner) 'u1': role,
      });
      if (role == TeamRole.owner) {
        teams.teams['t1'] = teamWith({
          'u1': TeamRole.owner,
          'coach': TeamRole.coach,
          'player': TeamRole.player,
        });
      }
      return TeamDetailViewModel(
        teamId: 't1',
        teamRepository: teams,
        playRepository: FakePlayRepository(),
        eventRepository: FakeEventRepository(),
        authRepository: auth,
      );
    }

    test('owner manages everyone but self', () async {
      final vm = detailFor(TeamRole.owner);
      await pumpEventQueue();
      expect(vm.isOwner, isTrue);
      expect(vm.canManage('coach'), isTrue);
      expect(vm.canManage('player'), isTrue);
      expect(vm.canManage('u1'), isFalse);
    });

    test('coach manages players only', () async {
      final vm = detailFor(TeamRole.coach);
      await pumpEventQueue();
      expect(vm.canEdit, isTrue);
      expect(vm.canManage('player'), isTrue);
      expect(vm.canManage('owner'), isFalse);
      expect(vm.canManage('coach'), isFalse);
    });

    test('player manages nobody', () async {
      final vm = detailFor(TeamRole.player);
      await pumpEventQueue();
      expect(vm.canEdit, isFalse);
      expect(vm.canManage('player'), isFalse);
    });
  });

  group('TournamentsViewModel', () {
    final now = DateTime(2026, 10, 26);
    final list = [
      Tournament(
        id: 'past',
        name: 'Fall Brawl',
        url: '',
        startDate: DateTime(2026, 9, 1),
        endDate: DateTime(2026, 9, 2),
        competitionLevel: 'Club',
        divisions: const ['Mixed'],
      ),
      Tournament(
        id: 'soon',
        name: 'Winter Classic',
        url: '',
        city: 'Denver',
        startDate: DateTime(2026, 11, 7),
        competitionLevel: 'College',
        divisions: const ['Women'],
      ),
      Tournament(
        id: 'later',
        name: 'Spring Fling',
        url: '',
        startDate: DateTime(2027, 3, 1),
        competitionLevel: 'Club',
        divisions: const ['Mixed', 'Men'],
      ),
    ];

    test('filters by upcoming/past, level, division and query', () async {
      final vm = TournamentsViewModel(
        tournamentRepository: FakeTournamentRepository(list),
        clock: () => now,
      );
      await pumpEventQueue();
      expect(vm.tournaments.map((t) => t.id), ['soon', 'later']);
      expect(vm.levels, ['Club', 'College']);
      expect(vm.divisions, ['Men', 'Mixed', 'Women']);

      vm.setLevel('Club');
      expect(vm.tournaments.map((t) => t.id), ['later']);
      vm.setLevel(null);

      vm.setQuery('denver');
      expect(vm.tournaments.map((t) => t.id), ['soon']);
      vm.setQuery('');

      vm.setDivision('Mixed');
      vm.setShowPast(true);
      expect(vm.tournaments.map((t) => t.id), ['past']);
    });
  });
}
