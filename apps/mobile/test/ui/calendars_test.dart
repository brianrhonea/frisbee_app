import 'dart:convert';

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/calendar/calendar_repository_api.dart';
import 'package:frisbee_app/data/services/api_client.dart';
import 'package:frisbee_app/domain/models/calendar.dart';
import 'package:frisbee_app/domain/models/player_profile.dart';
import 'package:frisbee_app/domain/models/schedule_entry.dart';
import 'package:frisbee_app/domain/models/team_event.dart';
import 'package:frisbee_app/ui/calendar/view_models/calendars_viewmodel.dart';
import 'package:frisbee_app/ui/calendar/widgets/calendars_screen.dart';
import 'package:frisbee_app/ui/schedule/view_models/event_editor_viewmodel.dart';
import 'package:frisbee_app/ui/schedule/view_models/schedule_viewmodel.dart';
import 'package:frisbee_app/ui/schedule/widgets/schedule_widgets.dart';
import 'package:frisbee_app/utils/ics.dart';
import 'package:frisbee_app/utils/result.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../testing/fakes.dart';

// Calendars as in Outlook or Apple Calendar (docs/requirements.md U11, D4):
// invites that share nothing until accepted, Can view / Can edit, events
// on any calendar the user may change, Add to calendar (.ics) and the
// subscription link.
void main() {
  const me = CalendarPerson(uid: 'u1', name: 'Alex');
  const pat = CalendarPerson(uid: 'pat', name: 'Pat Player', username: 'pat');
  final now = DateTime(2026, 11, 13, 9);

  const myCalendar = CalendarInfo(
    id: 'u1',
    name: 'My calendar',
    color: CalendarColor.green,
    owner: me,
    role: CalendarRole.owner,
    isDefault: true,
    members: [(person: me, role: CalendarRole.owner)],
  );
  const training = CalendarInfo(
    id: 'cal1',
    name: 'Training',
    color: CalendarColor.blue,
    owner: me,
    role: CalendarRole.owner,
    members: [(person: me, role: CalendarRole.owner)],
  );
  const patsView = CalendarInfo(
    id: 'pat',
    name: 'My calendar',
    color: CalendarColor.purple,
    owner: pat,
    role: CalendarRole.view,
    isDefault: true,
  );
  const patsEdit = CalendarInfo(
    id: 'patTeam',
    name: 'Club',
    color: CalendarColor.red,
    owner: pat,
    role: CalendarRole.edit,
  );

  TeamEvent event(String id, String title, DateTime at) =>
      TeamEvent(id: id, title: title, type: EventType.workout, startsAt: at);

  group('CalendarRepositoryApi', () {
    ApiClient api(
      http.Response Function(http.Request) answer,
      List<http.Request> asked,
    ) => ApiClient(
      baseUrl: Uri.parse('https://api.test'),
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'u1')),
      client: MockClient((req) async {
        asked.add(req);
        return answer(req);
      }),
    );

    http.Response json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

    test('reads events in local time, notes only when sent', () async {
      final asked = <http.Request>[];
      final repo = CalendarRepositoryApi(
        api: api(
          (_) => json({
            'events': [
              {
                'id': 'e1',
                'calendarId': 'pat',
                'title': 'Track',
                'type': 'workout',
                'startsAt': '2026-11-15T17:00:00.000Z',
                'endsAt': null,
                'location': 'Track',
              },
              {'id': 'bad', 'calendarId': 'pat', 'title': 'No date'},
            ],
          }),
          asked,
        ),
      );
      final r = await repo.events(
        DateTime.utc(2026, 11, 13),
        DateTime.utc(2026, 11, 20),
      );
      expect(asked.single.url.path, '/v1/me/calendar-events');
      expect(
        asked.single.url.queryParameters['from'],
        '2026-11-13T00:00:00.000Z',
      );
      final e = (r as Ok<List<CalendarEntry>>).value.single;
      expect(e.calendarId, 'pat');
      expect(e.event.startsAt, DateTime.utc(2026, 11, 15, 17).toLocal());
      expect(e.event.startsAt.isUtc, isFalse);
      expect(e.event.notes, isEmpty);
    });

    test('takes 204s, and sends what the API expects', () async {
      final asked = <http.Request>[];
      final repo = CalendarRepositoryApi(
        api: api((_) => http.Response('', 204), asked),
      );
      expect(
        await repo.invite('cal1', 'pat', CalendarRole.edit),
        isA<Ok<void>>(),
      );
      expect(await repo.accept('cal1'), isA<Ok<void>>());
      expect(
        await repo.update('cal1', color: CalendarColor.red),
        isA<Ok<void>>(),
      );
      expect(
        await repo.saveEvent(
          'cal1',
          event('e9', 'Gym', DateTime.utc(2026, 11, 15, 17)),
        ),
        isA<Ok<String>>(),
      );
      expect(
        [for (final r in asked) '${r.method} ${r.url.path}'],
        [
          'POST /v1/calendars/cal1/invites',
          'POST /v1/me/calendar-invites/cal1/accept',
          'PATCH /v1/calendars/cal1',
          'PATCH /v1/calendars/cal1/events/e9',
        ],
      );
      expect(jsonDecode(asked[0].body), {'uid': 'pat', 'role': 'edit'});
      expect(jsonDecode(asked[2].body), {'color': 'red'});
      expect(jsonDecode(asked[3].body), {
        'title': 'Gym',
        'type': 'workout',
        'startsAt': '2026-11-15T17:00:00.000Z',
        'endsAt': null,
        'location': '',
        'notes': '',
      });
    });

    test('is off without an API', () async {
      final repo = CalendarRepositoryApi(api: null);
      expect(repo.enabled, isFalse);
      expect(await repo.calendars(), isA<Error<List<CalendarInfo>>>());
    });
  });

  group('calendars on the Schedule tab', () {
    late FakeCalendarRepository calendars;

    ScheduleViewModel schedule() => ScheduleViewModel(
      authRepository: FakeAuthRepository(user: testUser),
      teamRepository: FakeTeamRepository(),
      eventRepository: FakeEventRepository(),
      calendarRepository: calendars,
      clock: () => now,
    );

    setUp(() {
      calendars = FakeCalendarRepository()
        ..calendarList = [myCalendar, training, patsView, patsEdit]
        ..eventsBy['u1'] = [
          event('mine', 'Already live', DateTime(2026, 11, 14, 7)),
        ]
        ..eventsBy['cal1'] = [event('t1', 'Tempo', DateTime(2026, 11, 14, 8))]
        ..eventsBy['pat'] = [event('p1', 'Track', DateTime(2026, 11, 14, 17))]
        ..eventsBy['patTeam'] = [
          event('c1', 'Club run', DateTime(2026, 11, 14, 18)),
        ]
        ..inviteList = [
          const CalendarInvite(
            calendarId: 'sam',
            calendarName: 'Family',
            color: CalendarColor.pink,
            role: CalendarRole.view,
            from: CalendarPerson(uid: 'sam', name: 'Sam'),
          ),
        ];
    });

    test(
      'shows other calendars in their colors, not My calendar twice',
      () async {
        final vm = schedule();
        await pumpEventQueue();
        final day = vm.eventsOn(DateTime(2026, 11, 14));
        expect(day.map((e) => e.key), [
          'cal-cal1/t1',
          'cal-pat/p1',
          'cal-patTeam/c1',
        ]);
        expect(day.every((e) => e.isOnCalendar && !e.isPersonal), isTrue);
        expect(day[0].isShared, isFalse);
        expect(day[1].isShared, isTrue);
        expect(vm.invites.single.calendarName, 'Family');

        vm.setFilter(ScheduleFilter.personal);
        expect(vm.eventsOn(DateTime(2026, 11, 14)), hasLength(3));
        vm.setFilter(ScheduleFilter.team);
        expect(vm.eventsOn(DateTime(2026, 11, 14)), isEmpty);
        vm.dispose();
      },
    );

    test('lets owners and editors delete, never viewers', () async {
      final vm = schedule();
      await pumpEventQueue();
      final [own, viewOnly, editable] = vm.eventsOn(DateTime(2026, 11, 14));
      expect(vm.canDelete(own), isTrue);
      expect(vm.canDelete(viewOnly), isFalse);
      expect(vm.canDelete(editable), isTrue);

      await vm.deleteEvent.execute(editable);
      expect(calendars.deleted, [('patTeam', 'c1')]);
      expect(vm.eventsOn(DateTime(2026, 11, 14)).map((e) => e.event.id), [
        't1',
        'p1',
      ]);

      vm.removeWithUndo(viewOnly);
      expect(
        vm.eventsOn(DateTime(2026, 11, 14)),
        hasLength(2),
        reason: 'never hidden',
      );
      vm.dispose();
    });

    test('accepting an invite reloads', () async {
      final vm = schedule();
      await pumpEventQueue();
      final loads = calendars.eventLoads;
      expect(await vm.answerInvite(vm.invites.single, true), isA<Ok<void>>());
      expect(calendars.calls, contains('accept sam'));
      expect(vm.invites, isEmpty);
      expect(calendars.eventLoads, loads + 1);
      vm.dispose();
    });

    test('a failed load leaves the schedule as it was', () async {
      calendars.fail = true;
      final vm = schedule();
      await pumpEventQueue();
      expect(vm.eventsOn(DateTime(2026, 11, 14)), isEmpty);
      vm.dispose();
    });
  });

  group('the event editor', () {
    EventEditorViewModel editor(
      FakeCalendarRepository calendars,
      FakeEventRepository events,
    ) => EventEditorViewModel(
      teamId: null,
      eventId: null,
      eventRepository: events,
      teamRepository: FakeTeamRepository(),
      authRepository: FakeAuthRepository(user: testUser),
      calendarRepository: calendars,
    );

    test(
      'offers calendars the user may change, and saves to the one picked',
      () async {
        final calendars = FakeCalendarRepository()
          ..calendarList = [myCalendar, training, patsView, patsEdit];
        final events = FakeEventRepository();
        final vm = editor(calendars, events);
        await pumpEventQueue();
        expect(vm.canChooseSchedule, isTrue);
        expect(vm.editableCalendars.map((c) => c.id), ['cal1', 'patTeam']);
        expect(vm.isMyCalendar, isTrue);

        vm.setCalendar('pat'); // view only
        expect(vm.calendarId, isNull);
        vm.setCalendar('patTeam');
        expect(vm.calendarId, 'patTeam');
        expect(vm.isPersonal, isTrue);
        expect(vm.scheduleCalendar!.isShared, isTrue);

        await vm.save.execute(
          event('', 'Club run', DateTime(2026, 11, 20, 18)),
        );
        expect(vm.save.result, isA<Ok<String>>());
        expect(calendars.saved.single.$1, 'patTeam');
        expect(
          events.mine['u1'],
          isNull,
          reason: "not saved into the user's own events",
        );

        vm.setCalendar(null);
        await vm.save.execute(event('', 'Gym', DateTime(2026, 11, 21, 7)));
        expect(events.mine['u1']!.values.single.title, 'Gym');
        vm.dispose();
      },
    );

    test('edits an event on another calendar through the API', () async {
      final calendars = FakeCalendarRepository()
        ..calendarList = [patsEdit]
        ..eventsBy['patTeam'] = [
          event('c1', 'Club run', DateTime(2026, 11, 14, 18)),
        ];
      final vm = EventEditorViewModel(
        teamId: null,
        calendarId: 'patTeam',
        eventId: 'c1',
        eventRepository: FakeEventRepository(),
        teamRepository: FakeTeamRepository(),
        authRepository: FakeAuthRepository(user: testUser),
        calendarRepository: calendars,
      );
      await pumpEventQueue();
      expect(vm.initial.title, 'Club run');
      await vm.save.execute(vm.initial.copyWith(title: 'Long run'));
      expect(calendars.saved.single.$1, 'patTeam');
      expect(calendars.saved.single.$2.id, 'c1');
      expect(calendars.saved.single.$2.title, 'Long run');
      vm.dispose();
    });
  });

  group('CalendarsViewModel', () {
    late FakeCalendarRepository calendars;
    late FakeProfileRepository profiles;

    setUp(() {
      calendars = FakeCalendarRepository()
        ..calendarList = [myCalendar, training, patsView];
      profiles = FakeProfileRepository()
        ..profiles['pat'] = const PlayerProfile(
          uid: 'pat',
          name: 'Pat Player',
          username: 'pat',
        )
        ..profiles['u1'] = const PlayerProfile(uid: 'u1', name: 'Pat Me');
    });

    CalendarsViewModel vm() => CalendarsViewModel(
      calendarRepository: calendars,
      profileRepository: profiles,
      uid: 'u1',
    );

    test('splits the user\'s calendars from shared ones', () async {
      final v = vm();
      await pumpEventQueue();
      expect(v.mine.map((c) => c.id), ['u1', 'cal1']);
      expect(v.shared.map((c) => c.id), ['pat']);
      v.dispose();
    });

    test(
      'invites with a role, leaves, and makes the subscription link',
      () async {
        final v = vm();
        await pumpEventQueue();
        await v.search.execute('pat');
        expect(v.resultsFor(training).map((p) => p.uid), ['pat']);
        await v.invite(training, 'pat', CalendarRole.edit);
        await v.leave(patsView);
        await v.resetFeed();
        expect(
          calendars.calls,
          containsAll(['invite cal1 pat edit', 'remove pat u1', 'resetFeed']),
        );
        expect(v.feed.isOn, isTrue);
        expect(v.feed.webcal, startsWith('webcal://'));
        await v.stopFeed();
        expect(v.feed.isOn, isFalse);
        v.dispose();
      },
    );

    test('search leaves out people already on the calendar', () async {
      final v = vm();
      await pumpEventQueue();
      await v.search.execute('pat');
      const withPat = CalendarInfo(
        id: 'cal1',
        name: 'Training',
        color: CalendarColor.blue,
        owner: me,
        role: CalendarRole.owner,
        pending: [(person: pat, role: CalendarRole.view)],
      );
      expect(v.resultsFor(withPat), isEmpty);
      v.dispose();
    });

    test('a failed change says so and keeps the list', () async {
      final v = vm();
      await pumpEventQueue();
      calendars.fail = true;
      await v.create('Track', CalendarColor.red);
      expect(v.change.error, isTrue);
      expect(v.mine.map((c) => c.id), ['u1', 'cal1']);
      v.dispose();
    });
  });

  group('Add to calendar', () {
    test('writes an iCalendar file the calendar apps accept', () {
      final ics = Ics.event(
        TeamEvent(
          id: 'e1',
          title: 'Track; easy, then strides',
          startsAt: DateTime.utc(2026, 11, 15, 17),
          location: 'High school track',
          notes: 'Bring spikes',
        ),
        uid: 'cal1-e1@stall10.app',
        now: DateTime.utc(2026, 11, 13, 12),
      );
      expect(ics.endsWith('\r\n'), isTrue);
      expect(ics, contains('UID:cal1-e1@stall10.app\r\n'));
      expect(
        ics,
        contains('DTSTART:20261115T170000Z\r\nDTEND:20261115T180000Z\r\n'),
      );
      expect(
        ics,
        contains(
          r'SUMMARY:Track\; easy\, then strides'
          '\r\n',
        ),
      );
      expect(ics, contains('DESCRIPTION:Bring spikes\r\n'));
      expect(Ics.fileName('Track; easy!'), 'Track easy.ics');
    });

    test('folds long lines at 75 octets without splitting characters', () {
      final line = 'SUMMARY:${'é' * 60}';
      final parts = Ics.fold(line).split('\r\n');
      expect(parts.length, greaterThan(1));
      for (final (i, p) in parts.indexed) {
        expect(utf8.encode(p).length, lessThanOrEqualTo(75));
        if (i > 0) expect(p.startsWith(' '), isTrue);
      }
      expect(
        [
          for (final (i, p) in parts.indexed) i == 0 ? p : p.substring(1),
        ].join(),
        line,
      );
    });
  });

  group('widgets', () {
    testWidgets('an event on a shared calendar opens in a sheet', (
      tester,
    ) async {
      final entry = ScheduleEntry(
        calendar: patsView,
        event: TeamEvent(
          id: 'e1',
          title: 'Track',
          type: EventType.workout,
          startsAt: DateTime(2026, 11, 14, 17),
          location: 'High school track',
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ScheduleEventRow(entry: entry, large: true)),
        ),
      );
      expect(find.text('MY CALENDAR'), findsOneWidget);
      await tester.tap(find.text('Track'));
      await tester.pumpAndSettle();
      expect(
        find.text("On Pat Player's My calendar · can view"),
        findsOneWidget,
      );
      expect(find.text('Add to calendar'), findsOneWidget);
      expect(find.text('Edit'), findsNothing);
    });

    testWidgets('Calendars: invites, calendars, and the link', (tester) async {
      final calendars = FakeCalendarRepository()
        ..calendarList = [myCalendar, training, patsView]
        ..inviteList = [
          const CalendarInvite(
            calendarId: 'sam',
            calendarName: 'Family',
            color: CalendarColor.pink,
            role: CalendarRole.edit,
            from: CalendarPerson(uid: 'sam', name: 'Sam'),
          ),
        ];
      final vm = CalendarsViewModel(
        calendarRepository: calendars,
        profileRepository: FakeProfileRepository(),
        uid: 'u1',
      );
      addTearDown(vm.dispose);
      await tester.pumpWidget(
        MaterialApp(home: CalendarsScreen(viewModel: vm)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sam invited you to Family'), findsOneWidget);
      expect(find.text('Training'), findsOneWidget);
      expect(find.text('Pat Player · Can view'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Accept'));
      await tester.pumpAndSettle();
      expect(calendars.calls, contains('accept sam'));
      expect(find.text('Sam invited you to Family'), findsNothing);

      await tester.scrollUntilVisible(
        find.text('Get a subscription link'),
        200,
      );
      await tester.tap(find.text('Get a subscription link'));
      await tester.pumpAndSettle();
      expect(
        find.text('Subscribe in Apple Calendar or Outlook'),
        findsOneWidget,
      );
    });

    testWidgets('without an API, Calendars says so', (tester) async {
      final vm = CalendarsViewModel(
        calendarRepository: FakeCalendarRepository(enabled: false),
        profileRepository: FakeProfileRepository(),
        uid: 'u1',
      );
      addTearDown(vm.dispose);
      await tester.pumpWidget(
        MaterialApp(home: CalendarsScreen(viewModel: vm)),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Calendars need a connection to Stall 10.'),
        findsOneWidget,
      );
    });
  });
}
