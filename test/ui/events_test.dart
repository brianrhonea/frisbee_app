import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/schedule_entry.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/team_event.dart';
import 'package:frisbee_app/domain/models/tournament.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/events/widgets/events_screen.dart';
import 'package:frisbee_app/ui/schedule/view_models/my_schedule.dart';
import 'package:frisbee_app/ui/schedule/view_models/schedule_viewmodel.dart';
import 'package:frisbee_app/ui/schedule/widgets/schedule_screen.dart';
import 'package:frisbee_app/ui/tournaments/view_models/tournaments_viewmodel.dart';

import '../testing/fakes.dart';

void main() {
  final now = DateTime(2026, 10, 28, 9);

  TeamEvent event(String id, String title, DateTime at, [EventType? type]) =>
      TeamEvent(
        id: id,
        title: title,
        startsAt: at,
        type: type ?? EventType.practice,
      );

  late FakeTeamRepository teams;
  late FakeEventRepository events;

  setUp(() {
    teams = FakeTeamRepository();
    events = FakeEventRepository();
    for (final id in ['t1', 't2']) {
      teams.teams[id] = teamWith({testUser.uid: TeamRole.owner}, id: id);
    }
    events.byTeam['t1'] = {
      'a': event('a', 'Practice A', DateTime(2026, 10, 30, 18)),
      'old': event('old', 'Old', DateTime(2026, 10, 1, 18)),
    };
    events.mine[testUser.uid] = {
      'p': event('p', 'Pickup P', DateTime(2026, 10, 29, 19), EventType.other),
    };
    events.byTeam['t2'] = {
      'b': event('b', 'Lift B', DateTime(2026, 10, 29, 7), EventType.workout),
      'c': event('c', 'Cup C', DateTime(2026, 10, 30, 8), EventType.tournament),
    };
  });

  group('MySchedule', () {
    test('merges teams, sorts, and drops teams the user leaves', () async {
      final feed = MySchedule(
        teamRepository: teams,
        eventRepository: events,
        uid: testUser.uid,
        clock: () => now,
      );
      await pumpEventQueue();
      expect(feed.entries.map((e) => e.event.id), ['old', 'b', 'p', 'c', 'a']);
      expect(feed.upcoming().map((e) => e.event.id), ['b', 'p', 'c', 'a']);
      expect(feed.upcoming().map((e) => e.team?.id), ['t2', null, 't2', 't1']);
      expect(feed.prioritized(limit: 2).map((e) => e.event.id), ['b', 'p']);
      expect(
        feed.prioritized(limit: 2, personal: false).map((e) => e.event.id),
        ['b', 'c'],
      );
      expect(
        feed
            .inRange(DateTime(2026, 10, 30), DateTime(2026, 10, 31))
            .map((e) => e.event.id),
        ['c', 'a'],
      );

      await teams.deleteTeam(teams.teams['t2']!);
      await pumpEventQueue();
      expect(feed.entries.map((e) => e.event.id), ['old', 'p', 'a']);
      feed.dispose();
    });

    testWidgets('retries personal events after a failed listen', (
      tester,
    ) async {
      final flaky = _FlakyEventRepository()
        ..mine[testUser.uid] = {
          'p': event('p', 'Pickup P', DateTime(2026, 10, 29, 19)),
        };
      final feed = MySchedule(
        teamRepository: teams,
        eventRepository: flaky,
        uid: testUser.uid,
        clock: () => now,
      );
      await tester.pump();
      expect(feed.entries.where((e) => e.isPersonal), isEmpty);

      await tester.pump(const Duration(seconds: 3));
      expect(flaky.myListens, 2);
      expect(feed.entries.where((e) => e.isPersonal).single.event.id, 'p');
      feed.dispose();
    });

    test('is empty and loaded without a user', () {
      final feed = MySchedule(
        teamRepository: teams,
        eventRepository: events,
        uid: null,
      );
      expect(feed.teamsLoaded, isTrue);
      expect(feed.entries, isEmpty);
      feed.dispose();
    });
  });

  group('ScheduleViewModel', () {
    Future<ScheduleViewModel> load() async {
      final vm = ScheduleViewModel(
        authRepository: FakeAuthRepository(user: testUser),
        teamRepository: teams,
        eventRepository: events,
        clock: () => now,
      );
      await pumpEventQueue();
      return vm;
    }

    ScheduleEntry entryOf(ScheduleViewModel vm, String id) => vm
        .eventsOn(DateTime(2026, 10, 29))
        .followedBy(vm.eventsOn(DateTime(2026, 10, 30)))
        .firstWhere((e) => e.event.id == id);

    test('only editors can delete team events; anyone their own', () async {
      teams.teams['t2'] = teamWith({
        'boss': TeamRole.owner,
        testUser.uid: TeamRole.player,
      }, id: 't2');
      final vm = await load();
      expect(vm.canDelete(entryOf(vm, 'p')), isTrue);
      expect(vm.canDelete(entryOf(vm, 'a')), isTrue);
      expect(vm.canDelete(entryOf(vm, 'b')), isFalse);

      await vm.deleteEvent.execute(entryOf(vm, 'b'));
      expect(vm.deleteEvent.error, isTrue);
      expect(events.byTeam['t2'], contains('b'));

      await vm.deleteEvent.execute(entryOf(vm, 'a'));
      await vm.deleteEvent.execute(entryOf(vm, 'p'));
      await pumpEventQueue();
      expect(events.byTeam['t1'], isNot(contains('a')));
      expect(events.mine[testUser.uid], isEmpty);
      vm.dispose();
    });

    test('swiped events hide until undone or deleted on leave', () async {
      final vm = await load();
      final day = DateTime(2026, 10, 29);
      final pickup = entryOf(vm, 'p');

      vm.removeWithUndo(pickup);
      expect(vm.eventsOn(day).map((e) => e.event.id), ['b']);
      expect(events.mine[testUser.uid], contains('p'));

      vm.undoRemove(pickup);
      expect(vm.eventsOn(day).map((e) => e.event.id), ['b', 'p']);

      vm.removeWithUndo(pickup);
      vm.dispose();
      await pumpEventQueue();
      expect(events.mine[testUser.uid], isEmpty);
    });

    test('shows a week from today and filters team vs personal', () async {
      final vm = await load();
      expect(vm.days.first, DateTime(2026, 10, 28));
      expect(vm.days.last, DateTime(2026, 11, 3));
      expect(vm.weekCount, 4);
      expect(vm.eventsOn(DateTime(2026, 10, 29)).map((e) => e.event.id), [
        'b',
        'p',
      ]);

      vm.setFilter(ScheduleFilter.personal);
      expect(vm.weekCount, 1);
      vm.setFilter(ScheduleFilter.team);
      expect(vm.weekCount, 3);
      expect(vm.eventsOn(DateTime(2026, 10, 29)).single.event.id, 'b');
    });

    test('moves between weeks and back to today', () async {
      final vm = await load();
      vm.selectDay(DateTime(2026, 10, 30));
      expect(vm.selectedDay, DateTime(2026, 10, 30));

      vm.nextWeek();
      expect(vm.weekStart, DateTime(2026, 11, 4));
      expect(vm.selectedDay, DateTime(2026, 11, 4));
      expect(vm.isCurrentWeek, isFalse);
      expect(vm.weekCount, 0);

      vm.previousWeek();
      vm.previousWeek();
      expect(vm.weekStart, DateTime(2026, 10, 21));

      vm.goToToday();
      expect(vm.isCurrentWeek, isTrue);
      expect(vm.selectedDay, DateTime(2026, 10, 28));
    });
  });

  testWidgets('schedule tab tags team and personal events', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final vm = await tester.runAsync(() async {
      final vm = ScheduleViewModel(
        authRepository: FakeAuthRepository(user: testUser),
        teamRepository: teams,
        eventRepository: events,
        clock: () => now,
      );
      await pumpEventQueue();
      return vm;
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ScheduleScreen(viewModel: vm!),
      ),
    );
    await tester.pump();

    expect(find.text('Lift B'), findsOneWidget);
    expect(find.text('Pickup P'), findsOneWidget);
    expect(find.text('PERSONAL'), findsOneWidget);
    expect(find.text('New event'), findsOneWidget);

    await tester.tap(find.text('Personal').first);
    await tester.pump();
    expect(find.text('Lift B'), findsNothing);
    expect(find.text('Pickup P'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('swipe right deletes events the user may delete', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    teams.teams['t2'] = teamWith({
      'boss': TeamRole.owner,
      testUser.uid: TeamRole.player,
    }, id: 't2');
    final vm = await tester.runAsync(() async {
      final vm = ScheduleViewModel(
        authRepository: FakeAuthRepository(user: testUser),
        teamRepository: teams,
        eventRepository: events,
        clock: () => now,
      );
      await pumpEventQueue();
      return vm;
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ScheduleScreen(viewModel: vm!),
      ),
    );
    await tester.pump();

    // A player can't swipe team events.
    expect(
      find.ancestor(
        of: find.text('Lift B'),
        matching: find.byType(Dismissible),
      ),
      findsNothing,
    );
    await tester.drag(find.text('Lift B'), const Offset(500, 0));
    await tester.pumpAndSettle();
    expect(find.text('Lift B'), findsOneWidget);

    await tester.drag(find.text('Pickup P'), const Offset(500, 0));
    await tester.pumpAndSettle();
    expect(find.text('Pickup P'), findsNothing);
    expect(find.text('Undo'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Pickup P'), findsOneWidget);
    expect(events.mine[testUser.uid], contains('p'));
  });

  testWidgets('events tab lists only USA Ultimate tournaments', (tester) async {
    final vm = TournamentsViewModel(
      tournamentRepository: FakeTournamentRepository([
        Tournament(
          id: 'fc',
          name: 'Fall Classic',
          url: '',
          startDate: DateTime.now().add(const Duration(days: 10)),
        ),
      ]),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: EventsScreen(viewModel: vm),
      ),
    );
    await tester.pump();
    expect(find.text('Fall Classic'), findsOneWidget);
    expect(find.text('Lift B'), findsNothing);
    expect(find.text('Show other events'), findsNothing);
  });
}

/// Denies the first personal-events listen, like a read made before the
/// rules allowed it.
class _FlakyEventRepository extends FakeEventRepository {
  int myListens = 0;

  @override
  Stream<List<TeamEvent>> watchMyEvents(String uid) {
    myListens++;
    if (myListens == 1) return Stream.error(Exception('permission-denied'));
    return super.watchMyEvents(uid);
  }
}
