import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/ranking/ranking_repository.dart';
import 'package:frisbee_app/data/repositories/team_elo/team_elo_repository.dart';
import 'package:frisbee_app/domain/models/ranking.dart';
import 'package:frisbee_app/domain/models/team_elo.dart';
import 'package:frisbee_app/ui/rankings/view_models/rankings_viewmodel.dart';

class _Rankings implements RankingRepository {
  _Rankings(this.divisions);

  final List<RankingDivision> divisions;

  @override
  Stream<List<RankingDivision>> watchDivisions() => Stream.value(divisions);
}

class _Elo implements TeamEloRepository {
  _Elo(this.divisions, {this.fail = false});

  final List<TeamEloDivision> divisions;
  final bool fail;

  @override
  Stream<List<TeamEloDivision>> watchDivisions() =>
      fail ? Stream.error(Exception('offline')) : Stream.value(divisions);
}

String url(String id) =>
    'https://play.usaultimate.org/teams/events/Eventteam/?TeamId=$id';

void main() {
  final rankings = [
    RankingDivision(
      key: 'Club-Men',
      label: 'Club Men',
      entries: [
        RankingEntry(rank: 1, teamName: 'Alpha', teamUrl: url('a')),
        RankingEntry(rank: 2, teamName: 'Beta', teamUrl: url('b')),
        RankingEntry(rank: 3, teamName: 'Gamma', teamUrl: url('c')),
      ],
    ),
  ];
  final elo = [
    TeamEloDivision(
      key: 'Club-Men',
      label: 'Club Men',
      entries: [
        TeamEloEntry(rank: 1, teamName: 'Beta', teamUrl: url('b'), elo: 1700),
        TeamEloEntry(rank: 2, teamName: 'Alpha', teamUrl: url('a'), elo: 1600),
      ],
    ),
  ];

  Future<RankingsViewModel> load(TeamEloRepository eloRepo) async {
    final vm = RankingsViewModel(
      rankingRepository: _Rankings(rankings),
      teamEloRepository: eloRepo,
    );
    await pumpEventQueue();
    return vm;
  }

  test('Elo sort orders by rating, unrated teams last', () async {
    final vm = await load(_Elo(elo));
    expect(vm.hasElo, isTrue);
    expect(vm.entries.map((e) => e.teamName), ['Alpha', 'Beta', 'Gamma']);

    vm.setSort(RankingSort.elo);
    expect(vm.entries.map((e) => e.teamName), ['Beta', 'Alpha', 'Gamma']);
    expect(vm.eloFor(vm.entries.first)?.elo, 1700);
    expect(vm.eloFor(vm.entries.last), isNull);
  });

  test('USAU rankings still load when Elo is unavailable', () async {
    final vm = await load(_Elo(const [], fail: true));
    expect(vm.error, isNull);
    expect(vm.hasElo, isFalse);
    vm.setSort(RankingSort.elo);
    expect(vm.entries.map((e) => e.teamName), ['Alpha', 'Beta', 'Gamma']);
  });
}
