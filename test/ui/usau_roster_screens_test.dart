import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/ranking/ranking_repository.dart';
import 'package:frisbee_app/data/repositories/usau_team/usau_team_repository.dart';
import 'package:frisbee_app/domain/models/ranking.dart';
import 'package:frisbee_app/domain/models/roster_player.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/usau_team.dart';
import 'package:frisbee_app/ui/teams/view_models/team_detail_viewmodel.dart';
import 'package:frisbee_app/ui/teams/view_models/usau_roster_viewmodel.dart';
import 'package:frisbee_app/ui/teams/widgets/roster_tab.dart';
import 'package:frisbee_app/ui/teams/widgets/usau_roster_screen.dart';
import 'package:frisbee_app/utils/result.dart';

import '../testing/fakes.dart';

const _url = 'https://play.usaultimate.org/teams/events/Eventteam/?TeamId=abc';

class _Usau implements UsauTeamRepository {
  @override
  Future<Result<UsauTeam>> getTeam(String url) async => const Result.ok(
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

class _NoRankings implements RankingRepository {
  @override
  Stream<List<RankingDivision>> watchDivisions() => const Stream.empty();
}

void main() {
  late FakeTeamRepository teams;

  setUp(() {
    teams = FakeTeamRepository()
      ..teams['t1'] = Team(
        id: 't1',
        name: 'Ring',
        division: Division.mixed,
        level: CompetitionLevel.club,
        ownerId: 'u1',
        members: const {'u1': TeamRole.owner},
        usauUrl: _url,
        usauName: 'Ring of Fire',
      )
      ..roster['t1'] = const [
        RosterPlayer(id: 'a', name: 'Jordan Lee', onUsau: true, paid: true),
        RosterPlayer(id: 'b', name: 'Casey Unsigned', onUsau: false),
      ];
  });

  Future<void> phone(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(380, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: child));
    await tester.pumpAndSettle();
  }

  testWidgets('roster shows USAU status, paid toggle and filter', (
    tester,
  ) async {
    final vm = TeamDetailViewModel(
      teamId: 't1',
      teamRepository: teams,
      playRepository: FakePlayRepository(),
      eventRepository: FakeEventRepository(),
      authRepository: FakeAuthRepository(user: testUser),
    );
    await phone(
      tester,
      ListenableBuilder(
        listenable: vm,
        builder: (_, _) =>
            vm.team == null ? const SizedBox() : RosterTab(viewModel: vm),
      ),
    );
    expect(find.text('Ring of Fire'), findsOneWidget);
    expect(find.textContaining('1/2 confirmed'), findsOneWidget);
    expect(find.text('On USAU'), findsOneWidget);
    expect(find.text('Not on USAU'), findsOneWidget);
    expect(find.text('Sync'), findsOneWidget);

    await tester.tap(find.text('Unconfirmed only'));
    await tester.pumpAndSettle();
    expect(find.text('Jordan Lee'), findsNothing);
    expect(find.text('Casey Unsigned'), findsOneWidget);
  });

  testWidgets('players see only names, positions and numbers', (tester) async {
    teams.teams['t1'] = teams.teams['t1']!.copyWith(
      members: {'boss': TeamRole.owner, testUser.uid: TeamRole.player},
    );
    teams.roster['t1'] = const [
      RosterPlayer(
        id: 'a',
        name: 'Jordan Lee',
        number: 7,
        position: PlayerPosition.handler,
        onUsau: true,
        paid: true,
      ),
      RosterPlayer(id: 'b', name: 'Casey Unsigned', onUsau: false),
    ];
    final vm = TeamDetailViewModel(
      teamId: 't1',
      teamRepository: teams,
      playRepository: FakePlayRepository(),
      eventRepository: FakeEventRepository(),
      authRepository: FakeAuthRepository(user: testUser),
    );
    await phone(
      tester,
      ListenableBuilder(
        listenable: vm,
        builder: (_, _) =>
            vm.team == null ? const SizedBox() : RosterTab(viewModel: vm),
      ),
    );
    expect(vm.canSeeRosterStatus, isFalse);
    // The roster arrives without status, so it can't leak into the UI.
    expect(vm.roster.every((p) => !p.paid && p.onUsau == null), isTrue);
    expect(find.text('Jordan Lee'), findsOneWidget);
    expect(find.text('Casey Unsigned'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('Handler'), findsOneWidget);
    for (final hidden in [
      'Paid',
      'Unpaid',
      'On USAU',
      'Not on USAU',
      'Sync',
      'Ring of Fire',
      'Unconfirmed only',
      'Add player',
    ]) {
      expect(find.text(hidden), findsNothing, reason: hidden);
    }
    expect(find.textContaining('confirmed'), findsNothing);
  });

  testWidgets('sync screen previews new, missing and applies', (tester) async {
    final vm = UsauRosterViewModel(
      teamId: 't1',
      teamRepository: teams,
      usauTeamRepository: _Usau(),
      rankingRepository: _NoRankings(),
      authRepository: FakeAuthRepository(user: testUser),
    );
    await phone(tester, UsauRosterScreen(viewModel: vm));
    expect(find.text('New players (1)'), findsOneWidget);
    expect(find.text('New Person'), findsOneWidget);
    expect(find.text('Not on USA Ultimate roster (1)'), findsOneWidget);
    expect(find.text('Apply 2 changes'), findsOneWidget);
    await tester.tap(find.text('Apply 2 changes'));
    await tester.pumpAndSettle();
    expect(teams.syncs, hasLength(1));
  });

  testWidgets('unlinked screen offers search and a pasted link', (
    tester,
  ) async {
    teams.teams['t1'] = teamWith({'u1': TeamRole.owner});
    final vm = UsauRosterViewModel(
      teamId: 't1',
      teamRepository: teams,
      usauTeamRepository: _Usau(),
      rankingRepository: _NoRankings(),
      authRepository: FakeAuthRepository(user: testUser),
    );
    await phone(tester, UsauRosterScreen(viewModel: vm));
    expect(find.text('Find your team'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'not a link');
    await tester.pump();
    await tester.ensureVisible(find.text('Use link'));
    await tester.tap(find.text('Use link'));
    await tester.pumpAndSettle();
    expect(
      find.text('Paste a play.usaultimate.org team page link'),
      findsOneWidget,
    );
  });
}
