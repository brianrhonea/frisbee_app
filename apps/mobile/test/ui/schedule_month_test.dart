import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/schedule/schedule_settings_repository.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/team_event.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/schedule/view_models/schedule_viewmodel.dart';
import 'package:frisbee_app/ui/schedule/widgets/schedule_screen.dart';

import '../testing/fakes.dart';
import '../ui_harness/harness.dart';

void main() {
  late FakeTeamRepository teams;
  late FakeEventRepository events;
  late ScheduleSettingsRepositoryMemory settings;
  // Thursday 19 November 2026.
  final now = DateTime(2026, 11, 19, 9);

  setUp(() {
    teams = FakeTeamRepository();
    events = FakeEventRepository();
    settings = ScheduleSettingsRepositoryMemory();
    teams.teams['t1'] = teamWith({
      'owner': TeamRole.owner,
      testUser.uid: TeamRole.player,
    });
    events.events
      ..['practice'] = TeamEvent(
        id: 'practice',
        title: 'Thursday practice',
        startsAt: DateTime(2026, 11, 19, 18),
        rsvps: {testUser.uid: RsvpStatus.going},
      )
      ..['hat'] = TeamEvent(
        id: 'hat',
        title: 'Snowmelt Hat',
        startsAt: DateTime(2026, 11, 28, 9),
      );
    events.mine[testUser.uid] = {
      'run': TeamEvent(
        id: 'run',
        title: 'Tempo run',
        type: EventType.workout,
        startsAt: DateTime(2026, 11, 19, 7),
      ),
    };
  });

  ScheduleViewModel schedule() => ScheduleViewModel(
    authRepository: FakeAuthRepository(user: testUser),
    teamRepository: teams,
    eventRepository: events,
    settingsRepository: settings,
    clock: () => now,
  );

  test('monthGrid runs Monday to Sunday around the month', () {
    final nov = monthGrid(DateTime(2026, 11));
    expect(nov.first, DateTime(2026, 10, 26));
    expect(nov.last, DateTime(2026, 12, 6));
    expect(nov, hasLength(42));
    // February 2027 starts on a Monday and ends on a Sunday: four weeks.
    final feb = monthGrid(DateTime(2027, 2));
    expect(feb.first, DateTime(2027, 2, 1));
    expect(feb, hasLength(28));
  });

  test('weekOf is the day\'s Monday-to-Sunday row of the grid', () {
    final week = weekOf(DateTime(2026, 11, 18, 15));
    expect(week.first, DateTime(2026, 11, 16));
    expect(week.last, DateTime(2026, 11, 22));
    // A Sunday stays in the week that started the Monday before.
    expect(weekOf(DateTime(2026, 11)).first, DateTime(2026, 10, 26));
  });

  group('ScheduleViewModel month view', () {
    test('lists the picked day\'s whole week', () async {
      final vm = schedule();
      addTearDown(vm.dispose);
      await pumpEventQueue();
      vm.setView(ScheduleView.month);
      expect(vm.selectedWeek.first, DateTime(2026, 11, 16));
      vm.selectDay(DateTime(2026, 12, 2));
      expect(vm.selectedWeek, [
        for (var d = 30; d <= 36; d++) DateTime(2026, 11, d),
      ]);
    });

    test('marks days, counts the month and moves between months', () async {
      final vm = schedule();
      addTearDown(vm.dispose);
      await pumpEventQueue();
      expect(vm.view, ScheduleView.week);
      vm.setView(ScheduleView.month);
      expect(vm.monthStart, DateTime(2026, 11));
      expect(vm.showsToday, isTrue);
      expect(vm.monthCount, 3);
      final today = vm.marksOn(DateTime(2026, 11, 19));
      expect(
        (today.team, today.personal, today.needsRsvp),
        (true, true, false),
      );
      // Unanswered and ahead: amber.
      final hat = vm.marksOn(DateTime(2026, 11, 28));
      expect((hat.team, hat.personal, hat.needsRsvp), (true, false, true));
      expect(vm.marksOn(DateTime(2026, 11, 20)).team, isFalse);

      vm.nextMonth();
      expect(vm.monthStart, DateTime(2026, 12));
      expect(vm.selectedDay, DateTime(2026, 12));
      expect(vm.showsToday, isFalse);
      // A day from the grid's next month opens that month.
      vm.previousMonth();
      vm.selectDay(DateTime(2026, 12, 2));
      expect(vm.monthStart, DateTime(2026, 12));
      vm.goToToday();
      expect(vm.monthStart, DateTime(2026, 11));
      expect(vm.selectedDay, DateTime(2026, 11, 19));
    });

    test('the choice is kept on the device', () async {
      final vm = schedule();
      await pumpEventQueue();
      vm.setView(ScheduleView.month);
      vm.dispose();
      expect(await settings.view(), 'month');

      final again = schedule();
      addTearDown(again.dispose);
      await pumpEventQueue();
      expect(again.view, ScheduleView.month);
    });

    test('the filter applies to the marks', () async {
      final vm = schedule();
      addTearDown(vm.dispose);
      await pumpEventQueue();
      vm
        ..setView(ScheduleView.month)
        ..setFilter(ScheduleFilter.personal);
      final today = vm.marksOn(DateTime(2026, 11, 19));
      expect((today.team, today.personal), (false, true));
      expect(vm.monthCount, 1);
    });
  });

  testWidgets('Month shows the grid and the whole month as a list', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final vm = schedule();
    addTearDown(vm.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ScheduleScreen(viewModel: vm),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Previous week'), findsNothing);
    await tester.tap(find.text('Month'));
    await tester.pumpAndSettle();
    expect(find.text('November 2026'), findsOneWidget);
    expect(find.text('3 events'), findsOneWidget);
    // The whole month's events below the grid, grouped by day.
    expect(find.text('Thursday, Nov 19'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Thursday practice'), findsOneWidget);
    expect(find.text('Tempo run'), findsOneWidget);
    expect(find.text('Saturday, Nov 28'), findsOneWidget);
    expect(find.text('Snowmelt Hat'), findsOneWidget);
    expect(find.text('Friday, Nov 20'), findsNothing);
    expect(find.byKey(const ValueKey('picked-week')), findsOneWidget);
    // Today's section is the picked one.
    expect(find.byKey(const ValueKey('picked-day-section')), findsOneWidget);

    // Picking a day with events highlights its section.
    await tester.tap(find.bySemanticsLabel('Saturday, November 28'));
    await tester.pumpAndSettle();
    expect(vm.selectedDay, DateTime(2026, 11, 28));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('picked-day-section')),
        matching: find.text('Snowmelt Hat'),
      ),
      findsOneWidget,
    );
    expect(find.text('Thursday practice'), findsOneWidget);

    // A day with nothing on keeps the list; nothing is highlighted.
    await tester.tap(find.bySemanticsLabel('Friday, November 20'));
    await tester.pumpAndSettle();
    expect(find.text('Thursday practice'), findsOneWidget);
    expect(find.byKey(const ValueKey('picked-day-section')), findsNothing);

    await tester.tap(find.byTooltip('Today'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('picked-day-section')), findsOneWidget);

    await tester.tap(find.text('Week'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Previous week'), findsOneWidget);
    expect(find.byKey(const ValueKey('picked-day-section')), findsNothing);
  });

  testWidgets('Picking a day scrolls the month list to it or the next one', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // Enough events that the later days start below the fold.
    for (var d = 2; d <= 17; d++) {
      events.events['e$d'] = TeamEvent(
        id: 'e$d',
        title: 'Filler $d',
        startsAt: DateTime(2026, 11, d, 12),
      );
    }
    final vm = schedule();
    addTearDown(vm.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ScheduleScreen(viewModel: vm),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Month'));
    await tester.pumpAndSettle();
    final hat = find.text('Snowmelt Hat', skipOffstage: false);
    // Nov 27 has nothing: the list goes to Saturday the 28th.
    await tester.tap(find.bySemanticsLabel('Friday, November 27'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(hat).dy, lessThan(700));
    expect(tester.getTopLeft(hat).dy, greaterThan(0));
  });

  testWidgets('List shows every day of the month that has events', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final vm = schedule();
    addTearDown(vm.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ScheduleScreen(viewModel: vm),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('List'), findsOneWidget);
    await tester.tap(find.text('List'));
    await tester.pumpAndSettle();
    expect(vm.view, ScheduleView.list);
    expect(find.text('November 2026'), findsOneWidget);
    // No grid, but the days with events, in order.
    expect(find.byKey(const ValueKey('picked-week')), findsNothing);
    expect(find.text('Thursday practice'), findsOneWidget);
    expect(find.text('Tempo run'), findsOneWidget);
    expect(find.text('Snowmelt Hat'), findsOneWidget);
    expect(find.text('Nothing scheduled'), findsNothing);
    final first = tester.getTopLeft(find.text('Thursday practice')).dy;
    final later = tester.getTopLeft(find.text('Snowmelt Hat')).dy;
    expect(first, lessThan(later));
    // Next month is empty.
    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing scheduled this month'), findsOneWidget);
  });
  // H2: Week, Month and List, light and dark, phone and tablet.
  group('H2 Schedule redesign', () {
    for (final view in ScheduleView.values) {
      Widget screen() {
        final vm = schedule()..setView(view);
        addTearDown(vm.dispose);
        return ScheduleScreen(viewModel: vm);
      }

      testWidgets(
        '${view.label}: goldens at phone and tablet widths',
        skip: goldenSkip != null,
        (tester) async {
          await expectGoldens(
            tester,
            screen(),
            'schedule_h2_${view.name}',
            widths: const [GoldenWidth.phone, GoldenWidth.tablet],
            height: 860,
          );
        },
      );

      for (final theme in GoldenTheme.values) {
        testWidgets('${view.label}: meets guidelines, ${theme.name}', (
          tester,
        ) async {
          await pumpInApp(tester, screen(), theme: theme, height: 860);
          await expectAccessible(tester);
        });
      }

      testWidgets('${view.label}: fits at text scale 2.0', (tester) async {
        await expectNoOverflowWithLargeText(tester, screen(), height: 860);
      });
    }

    testWidgets('the three views are one control: Week, Month, List', (
      tester,
    ) async {
      final vm = schedule();
      addTearDown(vm.dispose);
      await pumpInApp(tester, ScheduleScreen(viewModel: vm), height: 860);
      for (final label in ['Week', 'Month', 'List']) {
        expect(find.text(label), findsOneWidget);
      }
    });
  });
}
