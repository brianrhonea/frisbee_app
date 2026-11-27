// Sprint 4 (B5): saving an event on top of another asks first. Parity:
// website event editor.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:frisbee_app/domain/models/recurrence.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/team_event.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/schedule/view_models/event_editor_viewmodel.dart';
import 'package:frisbee_app/data/repositories/schedule/schedule_settings_repository.dart';
import 'package:frisbee_app/ui/schedule/view_models/event_overlap.dart';
import 'package:frisbee_app/ui/schedule/view_models/schedule_viewmodel.dart';
import 'package:frisbee_app/ui/schedule/widgets/event_editor_screen.dart';

import '../testing/fakes.dart';
import '../ui_harness/harness.dart';

void main() {
  final day = DateTime(2026, 11, 20);
  TeamEvent at(
    int h, {
    int? endH,
    String id = 'x',
    String title = 'Practice',
    EventSeries? series,
  }) => TeamEvent(
    id: id,
    title: title,
    startsAt: DateTime(2026, 11, 20, h),
    endsAt: endH == null ? null : DateTime(2026, 11, 20, endH),
    series: series,
  );

  group('firstOverlap', () {
    test('finds an event whose time crosses the draft', () {
      final known = [at(18, endH: 20, title: 'Practice')];
      expect(firstOverlap(at(19, endH: 21, id: ''), known)?.title, 'Practice');
      // Inside, around and sharing the start all overlap.
      expect(firstOverlap(at(18, endH: 19, id: ''), known), isNotNull);
      expect(firstOverlap(at(17, endH: 21, id: ''), known), isNotNull);
    });

    test('back to back is not an overlap', () {
      final known = [at(18, endH: 20)];
      expect(firstOverlap(at(20, endH: 21, id: ''), known), isNull);
      expect(firstOverlap(at(16, endH: 18, id: ''), known), isNull);
    });

    test('an event with no end counts as an hour', () {
      final known = [at(18)];
      expect(
        firstOverlap(at(18, endH: 19, id: '').copyWith(), known),
        isNotNull,
      );
      expect(firstOverlap(at(19, endH: 20, id: ''), known), isNull);
      expect(firstOverlap(at(17, endH: 18, id: ''), known), isNull);
    });

    test('an event spanning days overlaps on its later days', () {
      final known = [
        TeamEvent(
          id: 'hat',
          title: 'Hat',
          startsAt: DateTime(2026, 11, 20, 9),
          endsAt: DateTime(2026, 11, 22, 17),
        ),
      ];
      final draft = TeamEvent(
        id: '',
        title: 'Run',
        startsAt: DateTime(2026, 11, 21, 7),
        endsAt: DateTime(2026, 11, 21, 8),
      );
      expect(firstOverlap(draft, known)?.title, 'Hat');
    });

    test('the event being edited, and its own series, are left out', () {
      final series = EventSeries(
        id: 's1',
        index: 0,
        count: 3,
        freq: RepeatFrequency.weekly,
        until: DateTime(2026, 12, 18),
      );
      final known = [
        at(18, endH: 20, id: 'self'),
        at(18, endH: 20, id: 'sibling', series: series),
      ];
      expect(
        firstOverlap(at(18, endH: 20, id: 'self', series: series), known),
        isNull,
      );
    });

    test('a repeating draft is checked on every date', () {
      final next = TeamEvent(
        id: 'later',
        title: 'Social',
        startsAt: DateTime(2026, 11, 27, 18),
        endsAt: DateTime(2026, 11, 27, 20),
      );
      final repeat = Repeat(
        freq: RepeatFrequency.weekly,
        until: DateTime(2026, 12, 18),
      );
      final draft = at(18, endH: 19, id: '');
      expect(firstOverlap(draft, [next]), isNull);
      expect(firstOverlap(draft, [next], repeat: repeat)?.title, 'Social');
    });
  });

  test('the schedule hands the editor every event it has loaded', () async {
    final teams = FakeTeamRepository();
    final events = FakeEventRepository();
    teams.teams['t1'] = Team(
      id: 't1',
      name: 'Flyers',
      division: Division.mixed,
      level: CompetitionLevel.club,
      ownerId: testUser.uid,
      members: {testUser.uid: TeamRole.owner},
    );
    events.events['far'] = TeamEvent(
      id: 'far',
      title: 'Next month',
      startsAt: DateTime(2026, 12, 20, 18),
    );
    events.mine[testUser.uid] = {
      'run': TeamEvent(
        id: 'run',
        title: 'Tempo run',
        startsAt: DateTime(2026, 11, 20, 7),
      ),
    };
    final vm = ScheduleViewModel(
      authRepository: FakeAuthRepository(user: testUser),
      teamRepository: teams,
      eventRepository: events,
      settingsRepository: ScheduleSettingsRepositoryMemory(),
      clock: () => DateTime(2026, 11, 19, 9),
    );
    addTearDown(vm.dispose);
    await pumpEventQueue();
    // Not just the week on screen.
    expect(
      [for (final e in vm.knownEvents) e.title],
      ['Tempo run', 'Next month'],
    );
  });

  group('the editor', () {
    late FakeEventRepository events;

    Future<EventEditorViewModel> pump(
      WidgetTester tester, {
      String? teamId,
      List<TeamEvent>? known,
      GoldenTheme theme = GoldenTheme.light,
    }) async {
      events = FakeEventRepository();
      final teams = FakeTeamRepository();
      if (teamId != null) {
        teams.teams[teamId] = Team(
          id: teamId,
          name: 'Flyers',
          division: Division.mixed,
          level: CompetitionLevel.club,
          ownerId: testUser.uid,
          members: {testUser.uid: TeamRole.owner},
        );
      }
      final vm = EventEditorViewModel(
        teamId: teamId,
        eventId: null,
        eventRepository: events,
        teamRepository: teams,
        authRepository: FakeAuthRepository(user: testUser),
        initialDay: day,
        knownEvents: known == null ? null : () => known,
      );
      addTearDown(vm.dispose);
      await tester.runAsync(pumpEventQueue);
      tester.view.physicalSize = const Size(390 * 3, 1800 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp.router(
          theme: theme == GoldenTheme.dark ? AppTheme.dark : AppTheme.light,
          routerConfig: GoRouter(
            routes: [
              GoRoute(
                path: '/',
                builder: (_, _) => EventEditorScreen(viewModel: vm),
              ),
            ],
            errorBuilder: (_, _) => const Text('Opened'),
          ),
        ),
      );
      await tester.pump();
      return vm;
    }

    Future<void> submit(
      WidgetTester tester, {
      String title = 'Scrimmage',
    }) async {
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Title'),
        title,
      );
      await tester.tap(find.text('Create event'));
      await tester.pumpAndSettle();
    }

    final practice = at(
      18,
      endH: 19,
      id: 'p1',
      title: 'Thursday practice',
    ).copyWith();

    testWidgets('a personal event on top of another asks first', (
      tester,
    ) async {
      await pump(tester, known: [practice]);
      await submit(tester);
      expect(find.text('Overlapping event'), findsOneWidget);
      // (The time's space before PM may be a no-break one.)
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Text &&
              RegExp(
                r'^This overlaps with Thursday practice \(Fri, Nov 20, '
                r'6:00\sPM – 7:00\sPM\)\. Save anyway\?$',
              ).hasMatch(w.data ?? ''),
        ),
        findsOneWidget,
      );
      // Nothing is saved until the user says so.
      expect(events.mine, isEmpty);

      // Go back: the form stays, nothing saved.
      await tester.tap(find.text('Go back'));
      await tester.pumpAndSettle();
      expect(find.text('Overlapping event'), findsNothing);
      expect(find.text('Create event'), findsOneWidget);
      expect(events.mine, isEmpty);

      // Save anyway: saved.
      await tester.tap(find.text('Create event'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save anyway'));
      await tester.pumpAndSettle();
      expect(events.mine[testUser.uid], hasLength(1));
    });

    testWidgets('a team event asks too', (tester) async {
      await pump(tester, teamId: 't1', known: [practice]);
      await submit(tester);
      expect(find.text('Overlapping event'), findsOneWidget);
      await tester.tap(find.text('Save anyway'));
      await tester.pumpAndSettle();
      expect(events.events, hasLength(1));
    });

    testWidgets('no overlap saves without asking', (tester) async {
      await pump(
        tester,
        known: [at(8, endH: 9, id: 'early', title: 'Morning run')],
      );
      await submit(tester);
      expect(find.text('Overlapping event'), findsNothing);
      expect(events.mine[testUser.uid], hasLength(1));
    });

    testWidgets('an editor opened without a schedule never asks', (
      tester,
    ) async {
      await pump(tester);
      await submit(tester);
      expect(find.text('Overlapping event'), findsNothing);
      expect(events.mine[testUser.uid], hasLength(1));
    });

    for (final theme in GoldenTheme.values) {
      testWidgets('the warning meets guidelines, ${theme.name}', (
        tester,
      ) async {
        await pump(tester, known: [practice], theme: theme);
        await submit(tester);
        expect(find.text('Overlapping event'), findsOneWidget);
        await expectAccessible(tester);
      });
    }
  });
}
