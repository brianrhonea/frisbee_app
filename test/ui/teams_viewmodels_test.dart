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
    TeamDetailViewModel detailFor(TeamRole role, {bool stats = false}) {
      teams.teams['t1'] = teamWith(
        {
          'owner': TeamRole.owner,
          'coach': TeamRole.coach,
          'captain': TeamRole.captain,
          'stats': TeamRole.player,
          'player': TeamRole.player,
          if (role != TeamRole.owner) 'u1': role,
        },
        statKeepers: {'stats', if (stats) 'u1'},
      );
      if (role == TeamRole.owner) {
        teams.teams['t1'] = teamWith(
          {
            'u1': TeamRole.owner,
            'coach': TeamRole.coach,
            'captain': TeamRole.captain,
            'stats': TeamRole.player,
            'player': TeamRole.player,
          },
          statKeepers: {'stats'},
        );
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

    test('owner sets roles, regenerates codes and can transfer', () async {
      final vm = detailFor(TeamRole.owner);
      await pumpEventQueue();
      expect(vm.canSetRoles, isTrue);
      expect(vm.canRegenerateCode, isTrue);
      expect(vm.canRemove('coach'), isTrue);
      await vm.transferOwnership.execute('coach');
      await pumpEventQueue();
      expect(vm.team!.ownerId, 'coach');
      expect(vm.myRole, TeamRole.player);
      expect(vm.canSetRoles, isFalse);
    });

    test('owner gives and takes stats access', () async {
      final vm = detailFor(TeamRole.owner);
      await pumpEventQueue();
      expect(vm.team!.canKeepStats('player'), isFalse);
      await vm.setStatKeeper.execute((uid: 'player', on: true));
      await pumpEventQueue();
      expect(vm.team!.canKeepStats('player'), isTrue);
      expect(vm.team!.isStatKeeper('player'), isTrue);
      await vm.setStatKeeper.execute((uid: 'player', on: false));
      await pumpEventQueue();
      expect(vm.team!.canKeepStats('player'), isFalse);
    });

    test('captain manages the team and stats, not roles or codes', () async {
      final vm = detailFor(TeamRole.captain);
      await pumpEventQueue();
      expect(vm.canEdit, isTrue);
      expect(vm.canShareCode, isTrue);
      expect(vm.inviteCode, 'CODEt1');
      expect(vm.canRegenerateCode, isFalse);
      expect(vm.canSetRoles, isFalse);
      expect(vm.team!.canKeepStats('u1'), isTrue);
      expect(vm.canManage('player'), isTrue);
      expect(vm.canManage('stats'), isTrue);
      expect(vm.canManage('coach'), isFalse);
    });

    test('coach shares the code and keeps stats, but no new codes', () async {
      final vm = detailFor(TeamRole.coach);
      await pumpEventQueue();
      expect(vm.canShareCode, isTrue);
      expect(vm.inviteCode, 'CODEt1');
      expect(vm.canRegenerateCode, isFalse);
      expect(vm.canSetRoles, isFalse);
      expect(vm.team!.canKeepStats('u1'), isTrue);
    });

    test('player with stats access only keeps stats', () async {
      final vm = detailFor(TeamRole.player, stats: true);
      await pumpEventQueue();
      expect(vm.canEdit, isFalse);
      expect(vm.canShareCode, isFalse);
      expect(vm.inviteCode, isNull);
      expect(teams.inviteWatches, isEmpty);
      expect(vm.canManage('player'), isFalse);
      expect(vm.team!.canKeepStats('u1'), isTrue);
    });

    test('player manages nobody', () async {
      final vm = detailFor(TeamRole.player);
      await pumpEventQueue();
      expect(vm.canEdit, isFalse);
      expect(vm.canManage('player'), isFalse);
      expect(vm.canShareCode, isFalse);
      expect(vm.team!.canKeepStats('u1'), isFalse);
      // Players never even ask for the code; the rules would refuse.
      expect(vm.inviteCode, isNull);
      expect(teams.inviteWatches, isEmpty);
    });

    test('owner regenerates the code; losing admin hides it', () async {
      final vm = detailFor(TeamRole.owner);
      await pumpEventQueue();
      expect(vm.inviteCode, 'CODEt1');
      await vm.regenerateInviteCode.execute();
      await pumpEventQueue();
      expect(vm.inviteCode, 'NEWt1');

      final t = teams.teams['t1']!;
      await teams.updateTeam(
        t.copyWith(members: {...t.members, 'u1': TeamRole.player}),
      );
      await pumpEventQueue();
      expect(vm.inviteCode, isNull);
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
