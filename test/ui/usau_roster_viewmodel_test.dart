import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/ranking/ranking_repository.dart';
import 'package:frisbee_app/data/repositories/usau_team/usau_team_repository.dart';
import 'package:frisbee_app/domain/models/ranking.dart';
import 'package:frisbee_app/domain/models/roster_player.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/usau_team.dart';
import 'package:frisbee_app/ui/teams/view_models/usau_roster_viewmodel.dart';
import 'package:frisbee_app/utils/result.dart';

import '../testing/fakes.dart';

const _url = 'https://play.usaultimate.org/teams/events/Eventteam/?TeamId=abc';

class _Usau implements UsauTeamRepository {
  final requested = <String>[];

  @override
  Future<Result<UsauTeam>> getTeam(String url) async {
    requested.add(url);
    return const Result.ok(
      UsauTeam(
        name: 'Ring of Fire',
        url: _url,
        roster: [
          UsauPlayer(name: 'Jordan Lee', number: '7', position: 'Handler'),
          UsauPlayer(name: 'New Person', number: '12'),
        ],
      ),
    );
  }
}

class _Rankings implements RankingRepository {
  @override
  Stream<List<RankingDivision>> watchDivisions() => Stream.value(const [
    RankingDivision(
      key: 'Club-Women',
      label: 'Club Women',
      entries: [RankingEntry(rank: 3, teamName: 'Ring Women', teamUrl: 'w')],
    ),
    RankingDivision(
      key: 'Club-Mixed',
      label: 'Club Mixed',
      entries: [
        RankingEntry(rank: 9, teamName: 'Other', teamUrl: 'o'),
        RankingEntry(rank: 1, teamName: 'Ring', teamUrl: _url),
      ],
    ),
  ]);
}

void main() {
  late FakeTeamRepository teams;
  late _Usau usau;

  UsauRosterViewModel vmFor() => UsauRosterViewModel(
    teamId: 't1',
    teamRepository: teams,
    usauTeamRepository: usau,
    rankingRepository: _Rankings(),
    authRepository: FakeAuthRepository(user: testUser),
  );

  setUp(() {
    teams = FakeTeamRepository();
    usau = _Usau();
    teams.teams['t1'] = Team(
      id: 't1',
      name: 'Ring',
      division: Division.mixed,
      level: CompetitionLevel.club,
      ownerId: 'u1',
      members: const {'u1': TeamRole.owner},
    );
    teams.roster['t1'] = const [
      RosterPlayer(id: 'a', name: 'Jordan Lee'),
      RosterPlayer(id: 'b', name: 'Casey Unsigned'),
    ];
  });

  test('searches rankings by team name, own division first', () async {
    final vm = vmFor();
    await pumpEventQueue();
    expect(vm.linked, isFalse);
    expect(vm.query, 'Ring');
    expect(vm.candidates.map((c) => c.entry.teamName), ['Ring', 'Ring Women']);
    vm.setQuery('women');
    expect(vm.candidates.single.division, 'Club Women');
  });

  test('linking loads the page and previews the sync', () async {
    final vm = vmFor();
    await pumpEventQueue();
    final pick = vm.candidates.first;
    await vm.link.execute((url: pick.entry.teamUrl, name: pick.entry.teamName));
    await pumpEventQueue();
    expect(vm.linked, isTrue);
    expect(usau.requested, [_url]);
    final plan = vm.plan!;
    expect(plan.added.single.name, 'New Person');
    expect(plan.missing.single.name, 'Casey Unsigned');
    expect(vm.pendingWrites, 3);

    vm.toggleSkip(plan.added.single);
    expect(vm.pendingWrites, 2);
    await vm.apply.execute();
    expect(vm.apply.completed, isTrue);
    expect(teams.syncs.single.map((p) => p.name), [
      'Jordan Lee',
      'Casey Unsigned',
    ]);
  });

  test('accepts only USA Ultimate team links', () {
    expect(
      UsauRosterViewModel.parseLink(
        'https://play.usaultimate.org/teams/events/Eventteam/?TeamId=7Itt%2fk7%3d',
      ),
      'https://play.usaultimate.org/teams/events/Eventteam/?TeamId=7Itt%2Fk7%3D',
    );
    expect(
      UsauRosterViewModel.parseLink('https://example.com/?TeamId=x'),
      isNull,
    );
    expect(
      UsauRosterViewModel.parseLink('https://play.usaultimate.org/events/x/'),
      isNull,
    );
  });

  test('players cannot sync', () async {
    teams.teams['t1'] = teamWith({
      'boss': TeamRole.owner,
      'u1': TeamRole.player,
    });
    final vm = vmFor();
    await pumpEventQueue();
    expect(vm.canEdit, isFalse);
  });
}
