import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/services/usau/usau_parser.dart';
import 'package:frisbee_app/domain/models/tournament.dart';
import 'package:frisbee_app/domain/models/usau_schedule.dart';
import 'package:frisbee_app/ui/tournaments/view_models/tournament_detail_viewmodel.dart';
import 'package:frisbee_app/ui/tournaments/widgets/event_schedule_widgets.dart';
import 'package:frisbee_app/ui/tournaments/widgets/tournament_detail_screen.dart';

import '../testing/fakes.dart';

void main() {
  const men = UsauDivision(label: 'Men', level: 'Club');
  const mixed = UsauDivision(label: 'Mixed', level: 'Club');
  const women = UsauDivision(label: 'Women', level: 'Club');

  final menSchedule = parseDivisionSchedule(
    File(
      'functions/test/fixtures/event_details_men_example.html',
    ).readAsStringSync(),
    url: 'https://play.usaultimate.org/events/x/schedule/Men/Club-Men/',
  );
  const mixedSchedule = UsauDivisionSchedule(
    title: 'Club - Mixed',
    url: 'u',
    stages: [
      UsauStage(
        title: 'Saturday Pools',
        pools: [
          UsauPool(
            name: 'Pool A',
            teams: [UsauPoolTeam(name: 'Mixtape', seed: 1, record: '2 - 0')],
          ),
        ],
      ),
    ],
  );

  const tournament = Tournament(
    id: 'nats',
    name: 'Club Nationals',
    url: 'https://play.usaultimate.org/events/x/',
  );

  late FakeUsauScheduleRepository schedules;

  TournamentDetailViewModel viewModel({
    Tournament t = tournament,
    Map<UsauDivision, UsauDivisionSchedule?>? divisions,
  }) {
    schedules = FakeUsauScheduleRepository(
      schedules:
          divisions ?? {men: menSchedule, mixed: mixedSchedule, women: null},
    );
    return TournamentDetailViewModel(
      tournamentId: t.id,
      tournamentRepository: FakeTournamentRepository([t]),
      usauScheduleRepository: schedules,
    );
  }

  Future<void> pump(WidgetTester tester, TournamentDetailViewModel vm) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: TournamentDetailScreen(viewModel: vm)),
    );
    await tester.pumpAndSettle();
  }

  group('TournamentDetailViewModel', () {
    test('loads the first division, then others on selection', () async {
      final vm = viewModel();
      await pumpEventQueue();
      expect(vm.divisions, [men, mixed, women]);
      expect(vm.selectedDivision, men);
      expect(vm.schedule, same(menSchedule));
      expect(vm.divisionLabel(men), 'Men');

      vm.selectStage(1);
      expect(vm.stage?.title, "2026 Men's Club Championship");

      vm.selectDivision(mixed);
      expect(vm.stageIndex, 0);
      await pumpEventQueue();
      expect(vm.schedule, same(mixedSchedule));
      expect(schedules.requests, [(men, false), (mixed, false)]);

      vm.selectDivision(men);
      await pumpEventQueue();
      expect(schedules.requests, hasLength(2), reason: 'kept in memory');

      vm.refresh();
      await pumpEventQueue();
      expect(schedules.requests.last, (men, true));
      vm.dispose();
    });

    test('a division selected mid-load is loaded afterwards', () async {
      final vm = viewModel();
      final hold = schedules.hold = Completer<void>();
      await pumpEventQueue();
      expect(vm.loadSchedule.running, isTrue);
      vm.selectDivision(mixed);
      expect(vm.scheduleLoading, isTrue);
      schedules.hold = null;
      hold.complete();
      await pumpEventQueue();
      expect(schedules.requests, [(men, false), (mixed, false)]);
      expect(vm.schedule, same(mixedSchedule));
      vm.dispose();
    });

    test('shows a division error and retries it', () async {
      final vm = viewModel();
      await pumpEventQueue();
      vm.selectDivision(women);
      await pumpEventQueue();
      expect(vm.scheduleError, isNotNull);
      expect(vm.scheduleLoading, isFalse);
      vm.retry();
      await pumpEventQueue();
      expect(schedules.requests.where((r) => r.$1 == women), hasLength(2));
      vm.dispose();
    });

    test('adds the level to labels when levels differ', () async {
      final vm = viewModel(
        divisions: {
          men: mixedSchedule,
          const UsauDivision(label: 'Men', level: 'College'): mixedSchedule,
        },
      );
      await pumpEventQueue();
      expect(vm.divisionLabel(men), 'Club Men');
      vm.dispose();
    });
  });

  testWidgets('shows divisions, stage tabs and pools', (tester) async {
    await pump(tester, viewModel());
    expect(find.text('Schedule & brackets'), findsOneWidget);
    for (final label in ['Men', 'Mixed', 'Women']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Friday Pool Play'), findsOneWidget);
    expect(find.text('Pool A'), findsOneWidget);
    expect(find.text('Pool A Schedule & Scores'), findsOneWidget);
    expect(find.byType(BracketView), findsNothing);
  });

  testWidgets('draws the bracket tab as a tree', (tester) async {
    await pump(tester, viewModel());
    await tester.tap(find.text("2026 Men's Club Championship"));
    await tester.pumpAndSettle();
    expect(find.byType(BracketView), findsOneWidget);
    expect(find.text('Championship'), findsOneWidget);
    expect(find.text('Prequarterfinals'), findsOneWidget);
    expect(find.textContaining('Ring of Fire'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switches division', (tester) async {
    await pump(tester, viewModel());
    await tester.tap(find.text('Mixed'));
    await tester.pumpAndSettle();
    expect(find.text('Saturday Pools'), findsOneWidget);
    expect(find.text('Mixtape'), findsOneWidget);
  });

  testWidgets('says when no schedule is posted', (tester) async {
    await pump(tester, viewModel(divisions: {}));
    expect(find.text('No schedule posted yet.'), findsOneWidget);
  });

  testWidgets('hides the schedule for tournaments without a page', (
    tester,
  ) async {
    await pump(
      tester,
      viewModel(
        t: const Tournament(id: 'nats', name: 'Local', url: ''),
      ),
    );
    expect(find.text('Local'), findsWidgets);
    expect(find.text('Schedule & brackets'), findsNothing);
  });
}
