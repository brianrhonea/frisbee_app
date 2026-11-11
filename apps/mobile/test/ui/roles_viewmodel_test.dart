import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/ui/teams/view_models/roles_viewmodel.dart';

import '../testing/fakes.dart';

void main() {
  late FakeTeamRepository teams;
  late RolesViewModel vm;

  setUp(() async {
    teams = FakeTeamRepository()
      ..teams['t1'] = teamWith({'u1': TeamRole.owner, 'p': TeamRole.player});
    vm = RolesViewModel(
      teamId: 't1',
      teamRepository: teams,
      authRepository: FakeAuthRepository(user: testUser),
    );
    await pumpEventQueue();
  });

  tearDown(() => vm.dispose());

  Team saved() => teams.teams['t1']!;

  test('the owner creates, edits, reorders and deletes roles', () async {
    expect(vm.isOwner, isTrue);
    expect(vm.canAdd, isTrue);
    expect(vm.permissions, contains(TeamPermission.keepStats));

    await vm.save.execute(
      const CustomRole(
        id: '',
        name: ' Handlers ',
        permissions: {TeamPermission.manageChats},
      ),
    );
    await pumpEventQueue();
    await vm.save.execute(const CustomRole(id: '', name: 'Mods'));
    await pumpEventQueue();
    expect(vm.roles.map((r) => r.name), ['Handlers', 'Mods']);
    final handlers = vm.roles.first;
    expect(handlers.id, isNotEmpty);
    expect(vm.summaryOf(handlers), 'Manage chats');
    expect(vm.summaryOf(vm.roles.last), 'No permissions');

    // Give p the role, then change what it grants: p's permissions follow.
    await teams.saveRoles(
      saved(),
      roles: saved().roles,
      memberRoles: {
        'p': {handlers.id},
      },
    );
    await pumpEventQueue();
    expect(vm.memberCount(handlers.id), 1);
    expect(saved().memberPerms['p'], {TeamPermission.manageChats});
    await vm.save.execute(
      handlers.copyWith(permissions: {TeamPermission.manageEvents}),
    );
    expect(saved().memberPerms['p'], {TeamPermission.manageEvents});

    await vm.shift.execute((id: handlers.id, by: 1));
    await pumpEventQueue();
    expect(vm.roles.map((r) => r.name), ['Mods', 'Handlers']);

    await vm.delete.execute(handlers.id);
    await pumpEventQueue();
    expect(vm.roles.map((r) => r.name), ['Mods']);
    expect(saved().memberRoles, isEmpty);
    expect(saved().memberPerms, isEmpty);
  });

  test('a role needs a name', () async {
    await vm.save.execute(const CustomRole(id: '', name: '  '));
    expect(vm.save.error, isTrue);
    expect(teams.rolesSaved, 0);
  });

  test("groups' roles can't keep stats", () async {
    final t = saved();
    teams.teams['t1'] = Team(
      id: t.id,
      name: t.name,
      division: t.division,
      level: t.level,
      ownerId: t.ownerId,
      members: t.members,
      kind: TeamKind.community,
    );
    final group = RolesViewModel(
      teamId: 't1',
      teamRepository: teams,
      authRepository: FakeAuthRepository(user: testUser),
    );
    await pumpEventQueue();
    expect(group.permissions, isNot(contains(TeamPermission.keepStats)));
    group.dispose();
  });
}
