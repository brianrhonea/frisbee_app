import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/ui/teams/view_models/create_team_viewmodel.dart';
import 'package:frisbee_app/ui/teams/view_models/team_detail_viewmodel.dart';
import 'package:frisbee_app/ui/teams/view_models/teams_viewmodel.dart';
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

    test('owner sets roles, shares codes and can transfer', () async {
      final vm = detailFor(TeamRole.owner);
      await pumpEventQueue();
      expect(vm.canSetRoles, isTrue);
      expect(vm.canShareCode, isTrue);
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
      expect(vm.canSetRoles, isFalse);
      expect(vm.team!.canKeepStats('u1'), isTrue);
      expect(vm.canManage('player'), isTrue);
      expect(vm.canManage('stats'), isTrue);
      expect(vm.canManage('coach'), isFalse);
    });

    test('coach shares the code and keeps stats, but sets no roles', () async {
      final vm = detailFor(TeamRole.coach);
      await pumpEventQueue();
      expect(vm.canShareCode, isTrue);
      expect(vm.canSetRoles, isFalse);
      expect(vm.team!.canKeepStats('u1'), isTrue);
    });

    test('player with stats access only keeps stats', () async {
      final vm = detailFor(TeamRole.player, stats: true);
      await pumpEventQueue();
      expect(vm.canEdit, isFalse);
      expect(vm.canShareCode, isFalse);
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
    });

    test('losing admin stops showing the code', () async {
      final vm = detailFor(TeamRole.owner);
      await pumpEventQueue();
      expect(vm.canShareCode, isTrue);

      final t = teams.teams['t1']!;
      await teams.updateTeam(
        t.copyWith(members: {...t.members, 'u1': TeamRole.player}),
      );
      await pumpEventQueue();
      expect(vm.canShareCode, isFalse);
    });
  });

  group('TeamDetailViewModel custom roles', () {
    TeamDetailViewModel load() => TeamDetailViewModel(
      teamId: 't1',
      teamRepository: teams,
      playRepository: FakePlayRepository(),
      eventRepository: FakeEventRepository(),
      authRepository: auth,
    );

    test("the owner assigns roles; each member's permissions follow", () async {
      teams.teams['t1'] = teamWith({'u1': TeamRole.owner, 'p': TeamRole.player})
          .copyWith(
            roles: {
              'm': const CustomRole(
                id: 'm',
                name: 'Mods',
                permissions: {TeamPermission.manageMembers},
              ),
            },
          );
      final vm = load();
      await pumpEventQueue();
      await vm.setMemberRoles.execute((uid: 'p', roleIds: {'m'}));
      await pumpEventQueue();
      expect(vm.team!.rolesOf('p').single.name, 'Mods');
      expect(vm.team!.has('p', TeamPermission.manageMembers), isTrue);
      await vm.setMemberRoles.execute((uid: 'p', roleIds: {}));
      await pumpEventQueue();
      expect(vm.team!.memberRoles, isEmpty);
      expect(vm.team!.has('p', TeamPermission.manageMembers), isFalse);
      vm.dispose();
    });

    test('Manage members shares the invite code and removes players', () async {
      teams.teams['t1'] =
          teamWith({
            'o': TeamRole.owner,
            'u1': TeamRole.player,
            'p': TeamRole.player,
          }).copyWith(
            memberPerms: {
              'u1': {TeamPermission.manageMembers},
            },
          );
      final vm = load();
      await pumpEventQueue();
      expect(vm.canManageMembers, isTrue);
      expect(vm.canShareCode, isTrue);
      expect(vm.canRemove('p'), isTrue);
      expect(vm.canRemove('o'), isFalse);
      expect(vm.canSetRoles, isFalse);
      expect(vm.canEdit, isFalse);
      vm.dispose();
    });

    Team legacyGroup(String owner) => Team(
      id: 't1',
      name: 'Pickup',
      division: Division.mixed,
      level: CompetitionLevel.pickup,
      kind: TeamKind.community,
      ownerId: owner,
      members: {
        owner: TeamRole.owner,
        if (owner != 'u1') 'u1': TeamRole.player,
        'k1': TeamRole.captain,
        'k2': TeamRole.captain,
        'm': TeamRole.player,
      },
    );

    test("the owner's visit turns organizers into a role, once", () async {
      teams.teams['t1'] = legacyGroup('u1');
      final vm = load();
      await pumpEventQueue();
      // The fake team stream drops writes made while the first snapshot
      // is being handled, so read what was saved.
      final team = teams.teams['t1']!;
      expect(team.needsRoleMigration, isFalse);
      expect(team.roleOf('k1'), TeamRole.player);
      final organizer = team.roles.values.single;
      expect(organizer.name, 'Organizer');
      expect(organizer.permissions, {
        TeamPermission.manageTeam,
        TeamPermission.manageMembers,
        TeamPermission.manageChats,
        TeamPermission.manageEvents,
      });
      expect(team.rolesOf('k2').single.id, organizer.id);
      expect(team.has('k1', TeamPermission.manageEvents), isTrue);
      expect(team.has('m', TeamPermission.manageEvents), isFalse);
      expect(teams.migrations, 1);
      vm.dispose();
    });

    test("a team's coaches and captains become roles too", () async {
      teams.teams['t1'] = teamWith({
        'u1': TeamRole.owner,
        'c': TeamRole.coach,
        'k': TeamRole.captain,
        'p': TeamRole.player,
      });
      final vm = load();
      await pumpEventQueue();
      final team = teams.teams['t1']!;
      expect(team.needsRoleMigration, isFalse);
      expect(team.rolesOf('c').single.name, 'Coach');
      expect(team.rolesOf('k').single.name, 'Captain');
      for (final p in TeamPermission.values) {
        expect(team.has('c', p), isTrue, reason: '$p');
      }
      expect(team.has('p', TeamPermission.manageTeam), isFalse);
      vm.dispose();
    });

    test('members leave organizers alone', () async {
      teams.teams['t1'] = legacyGroup('o');
      final vm = load();
      await pumpEventQueue();
      expect(vm.team!.needsRoleMigration, isTrue);
      expect(teams.migrations, 0);
      vm.dispose();
    });
  });
}
