import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/team/view_as_team_repository.dart';
import 'package:frisbee_app/domain/models/team.dart';

import '../testing/fakes.dart';

void main() {
  late FakeTeamRepository inner;
  late ViewAsRole viewAs;
  late ViewAsTeamRepository repo;

  setUp(() {
    inner = FakeTeamRepository();
    inner.teams['t1'] = teamWith({
      testUser.uid: TeamRole.owner,
      'other': TeamRole.coach,
    }, id: 't1');
    inner.teams['t2'] = teamWith({'other': TeamRole.owner}, id: 't2');
    viewAs = ViewAsRole();
    repo = ViewAsTeamRepository(
      inner: inner,
      authRepository: FakeAuthRepository(user: testUser),
      viewAs: viewAs,
    );
  });

  test('passes teams through when no role is set', () async {
    final team = await repo.watchTeam('t1').first;
    expect(team!.roleOf(testUser.uid), TeamRole.owner);
  });

  test('rewrites only the current user and re-emits on change', () async {
    final seen = <TeamRole?>[];
    final sub = repo
        .watchMyTeams(testUser.uid)
        .listen((teams) => seen.add(teams.single.roleOf(testUser.uid)));
    await pumpEventQueue();

    viewAs.role = TeamRole.player;
    await pumpEventQueue();
    viewAs.role = null;
    await pumpEventQueue();
    expect(seen, [TeamRole.owner, TeamRole.player, TeamRole.owner]);

    viewAs.role = TeamRole.player;
    final team = await repo.watchTeam('t1').first;
    expect(team!.canEdit(testUser.uid), isFalse);
    expect(team.roleOf('other'), TeamRole.coach);
    // Teams the user isn't on stay as they are.
    final other = await repo.watchTeam('t2').first;
    expect(other!.members.containsKey(testUser.uid), isFalse);
    await sub.cancel();
  });
}
