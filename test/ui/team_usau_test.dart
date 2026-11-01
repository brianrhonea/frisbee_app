import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/usau_team/usau_team_repository.dart';
import 'package:frisbee_app/domain/models/ranking.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/usau_team.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/teams/view_models/team_home_viewmodel.dart';
import 'package:frisbee_app/ui/teams/view_models/team_usau_viewmodel.dart';
import 'package:frisbee_app/ui/teams/widgets/team_home_screen.dart';
import 'package:frisbee_app/utils/result.dart';

import '../testing/fakes.dart';

const _url =
    'https://play.usaultimate.org/teams/events/Eventteam/?TeamId=abc%3d%3d';

class _Usau implements UsauTeamRepository {
  _Usau({this.fail = false});

  final bool fail;

  @override
  Future<Result<UsauTeam>> getTeam(String url) async => fail
      ? Result.error(Exception('down'))
      : Result.ok(
          UsauTeam(
            name: 'Ring of Fire',
            url: url,
            games: const [
              UsauGame(opponent: 'A', score: '13-9'),
              UsauGame(opponent: 'B', score: '10-13'),
              UsauGame(opponent: 'C', score: '15-3'),
            ],
            events: [
              UsauEvent(
                name: 'Early Season Open',
                startDate: DateTime.utc(2026, 8, 1, 12),
                placement: '1',
              ),
              UsauEvent(
                name: 'Sectionals',
                startDate: DateTime.utc(2026, 9, 12, 12),
                placement: '3',
              ),
              UsauEvent(
                name: 'Regionals',
                startDate: DateTime.utc(2026, 11, 7, 12),
                location: 'Denver, CO',
              ),
              UsauEvent(
                name: 'Nationals',
                startDate: DateTime.utc(2026, 11, 20, 12),
              ),
            ],
          ),
        );
}

RankingDivision _division({String teamUrl = _url}) => RankingDivision(
  key: 'club-mixed',
  label: 'Club Mixed',
  entries: [
    const RankingEntry(rank: 1, teamName: 'Other', teamUrl: 'x'),
    RankingEntry(
      rank: 12,
      teamName: 'Ring of Fire',
      wins: 18,
      losses: 6,
      teamUrl: teamUrl,
    ),
  ],
);

void main() {
  final now = DateTime(2026, 11, 1);

  group('TeamUsauViewModel', () {
    test('finds the ranking however the url is written', () async {
      final vm = TeamUsauViewModel(
        url: _url,
        usauTeamRepository: _Usau(),
        // The rankings list prints the id decoded and on www.
        rankingRepository: FakeRankingRepository([
          _division(
            teamUrl:
                'http://www.play.usaultimate.org/teams/events/eventteam/'
                '?TeamId=abc==',
          ),
        ]),
        clock: () => now,
      );
      await pumpEventQueue();
      expect(vm.ranking?.rank, 12);
      expect(vm.division, 'Club Mixed');
      // The rankings' record wins over counting games.
      expect(vm.record, (wins: 18, losses: 6));
      vm.dispose();
    });

    test('unranked teams count their games', () async {
      final vm = TeamUsauViewModel(
        url: _url,
        usauTeamRepository: _Usau(),
        rankingRepository: FakeRankingRepository(const []),
        clock: () => now,
      );
      await pumpEventQueue();
      expect(vm.ranking, isNull);
      expect(vm.record, (wins: 2, losses: 1));
      vm.dispose();
    });

    test('the schedule leads with what is next, then latest results', () async {
      final vm = TeamUsauViewModel(
        url: _url,
        usauTeamRepository: _Usau(),
        clock: () => now,
      );
      await pumpEventQueue();
      expect(vm.schedule.map((e) => e.name), [
        'Regionals',
        'Nationals',
        'Sectionals',
      ]);
      vm.dispose();
    });
  });

  testWidgets('the public page shows ranking, record and schedule at phone '
      'width', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final teams = FakeTeamRepository();
    final team = teamWith({'owner': TeamRole.owner});
    teams.teams[team.id] = team;
    teams.listings[team.id] = TeamListing(
      id: team.id,
      name: team.name,
      division: team.division,
      level: team.level,
      usauUrl: _url,
      usauName: 'Ring of Fire',
    );
    final vm = TeamHomeViewModel(
      teamId: team.id,
      teamRepository: teams,
      eventRepository: FakeEventRepository(),
      teamPostRepository: FakeTeamPostRepository(),
      authRepository: FakeAuthRepository(user: testUser),
      filePicker: FakeFilePickerService(),
      usauTeamRepository: _Usau(),
      rankingRepository: FakeRankingRepository([_division()]),
      clock: () => now,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: TeamHomeScreen(viewModel: vm),
      ),
    );
    await tester.pumpAndSettle();

    expect(vm.isMember, isFalse);
    await tester.scrollUntilVisible(
      find.text('USA Ultimate'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('#12'), findsOneWidget);
    expect(find.text('Club Mixed'), findsOneWidget);
    expect(find.text('18–6'), findsOneWidget);
    expect(find.text('Regionals'), findsOneWidget);
    expect(find.text('Upcoming'), findsNWidgets(2));
    expect(find.text('3rd'), findsOneWidget);
    expect(tester.takeException(), isNull);
    vm.dispose();
  });

  test('a team without a USA Ultimate link has no card', () async {
    final teams = FakeTeamRepository();
    final team = teamWith({'owner': TeamRole.owner});
    teams.teams[team.id] = team;
    teams.listings[team.id] = TeamListing.of(team);
    final vm = TeamHomeViewModel(
      teamId: team.id,
      teamRepository: teams,
      eventRepository: FakeEventRepository(),
      teamPostRepository: FakeTeamPostRepository(),
      authRepository: FakeAuthRepository(user: testUser),
      filePicker: FakeFilePickerService(),
      usauTeamRepository: _Usau(fail: true),
    );
    await pumpEventQueue();
    expect(vm.usau, isNull);
    vm.dispose();
  });
}
