import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/calendar/calendar_share_repository_api.dart';
import 'package:frisbee_app/data/services/api_client.dart';
import 'package:frisbee_app/domain/models/player_profile.dart';
import 'package:frisbee_app/domain/models/schedule_entry.dart';
import 'package:frisbee_app/domain/models/shared_calendar.dart';
import 'package:frisbee_app/domain/models/team_event.dart';
import 'package:frisbee_app/ui/calendar/view_models/calendar_sharing_viewmodel.dart';
import 'package:frisbee_app/ui/calendar/widgets/calendar_sharing_screen.dart';
import 'package:frisbee_app/ui/schedule/view_models/schedule_viewmodel.dart';
import 'package:frisbee_app/ui/schedule/widgets/schedule_widgets.dart';
import 'package:frisbee_app/utils/result.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../testing/fakes.dart';

void main() {
  const pat = CalendarPerson(uid: 'pat', name: 'Pat Player', username: 'pat');
  final now = DateTime(2026, 11, 13, 9);

  group('CalendarShareRepositoryApi', () {
    test(
      'reads shared calendars without notes, and sends the window',
      () async {
        Uri? asked;
        final repo = CalendarShareRepositoryApi(
          api: ApiClient(
            baseUrl: Uri.parse('https://api.test'),
            auth: MockFirebaseAuth(
              signedIn: true,
              mockUser: MockUser(uid: 'u1'),
            ),
            client: MockClient((req) async {
              asked = req.url;
              return http.Response(
                jsonEncode({
                  'calendars': [
                    {
                      'owner': {
                        'uid': 'pat',
                        'name': 'Pat Player',
                        'username': 'pat',
                        'photoUrl': null,
                      },
                      'events': [
                        {
                          'id': 'e1',
                          'title': 'Track',
                          'type': 'workout',
                          'startsAt': '2026-11-15T17:00:00.000Z',
                          'endsAt': null,
                          'location': 'Track',
                        },
                      ],
                    },
                  ],
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            }),
          ),
        );
        final r = await repo.shared(
          DateTime.utc(2026, 11, 13),
          DateTime.utc(2026, 11, 20),
        );
        expect(asked!.path, '/v1/me/calendar/shared');
        expect(asked!.queryParameters['from'], '2026-11-13T00:00:00.000Z');
        final calendars = (r as Ok<List<SharedCalendar>>).value;
        expect(calendars.single.owner.name, 'Pat Player');
        final e = calendars.single.events.single;
        expect(e.type, EventType.workout);
        expect(e.startsAt, DateTime.utc(2026, 11, 15, 17));
        expect(e.notes, isEmpty);
      },
    );

    test('is off without an API', () async {
      final repo = CalendarShareRepositoryApi(api: null);
      expect(repo.enabled, isFalse);
      expect(await repo.viewers(), isA<Error<List<CalendarPerson>>>());
    });
  });

  group('shared calendars on the Schedule tab', () {
    late FakeCalendarShareRepository shares;

    ScheduleViewModel schedule() => ScheduleViewModel(
      authRepository: FakeAuthRepository(user: testUser),
      teamRepository: FakeTeamRepository(),
      eventRepository: FakeEventRepository(),
      calendarShareRepository: shares,
      clock: () => now,
    );

    setUp(() {
      shares = FakeCalendarShareRepository()
        ..calendars = [
          SharedCalendar(
            owner: pat,
            events: [
              TeamEvent(
                id: 'e1',
                title: 'Track',
                type: EventType.workout,
                startsAt: DateTime(2026, 11, 14, 17),
              ),
            ],
          ),
        ];
    });

    test('shows them read-only, apart from the user\'s own', () async {
      final vm = schedule();
      await pumpEventQueue();
      final entry = vm.eventsOn(DateTime(2026, 11, 14)).single;
      expect(entry.isShared, isTrue);
      expect(entry.isPersonal, isFalse);
      expect(entry.sharedBy, pat);
      expect(entry.key, 'shared-pat/e1');
      expect(vm.canDelete(entry), isFalse);

      vm.removeWithUndo(entry);
      expect(
        vm.eventsOn(DateTime(2026, 11, 14)),
        hasLength(1),
        reason: 'never hidden for deleting',
      );

      vm.setFilter(ScheduleFilter.personal);
      expect(vm.eventsOn(DateTime(2026, 11, 14)), isEmpty);
      vm.setFilter(ScheduleFilter.team);
      expect(vm.eventsOn(DateTime(2026, 11, 14)), isEmpty);
      vm.setFilter(ScheduleFilter.all);
      expect(vm.eventsOn(DateTime(2026, 11, 14)), hasLength(1));
      vm.dispose();
    });

    test('loads once for nearby weeks, and again when asked', () async {
      final vm = schedule();
      await pumpEventQueue();
      expect(shares.sharedLoads, 1);
      await vm.refreshShared();
      expect(shares.sharedLoads, 2);
      vm.dispose();
    });

    test('a failed load leaves the schedule as it was', () async {
      shares.fail = true;
      final vm = schedule();
      await pumpEventQueue();
      expect(vm.eventsOn(DateTime(2026, 11, 14)), isEmpty);
      vm.dispose();
    });

    test('a personal event stays the user\'s', () {
      final own = ScheduleEntry(
        event: TeamEvent(id: 'x', title: 'Gym', startsAt: now),
      );
      expect(own.isPersonal, isTrue);
      expect(own.key, 'me/x');
    });
  });

  group('CalendarSharingViewModel', () {
    late FakeCalendarShareRepository shares;
    late FakeProfileRepository profiles;

    setUp(() {
      shares = FakeCalendarShareRepository()..people['pat'] = pat;
      profiles = FakeProfileRepository()
        ..profiles['pat'] = const PlayerProfile(
          uid: 'pat',
          name: 'Pat Player',
          username: 'pat',
        )
        ..profiles['u1'] = const PlayerProfile(uid: 'u1', name: 'Pat Me');
    });

    CalendarSharingViewModel vm() => CalendarSharingViewModel(
      calendarShareRepository: shares,
      profileRepository: profiles,
      uid: 'u1',
    );

    test('adds and removes people, saving each change', () async {
      final v = vm();
      await pumpEventQueue();
      expect(v.viewers, isEmpty);
      await v.add.execute(pat);
      expect(v.viewers!.map((p) => p.uid), ['pat']);
      expect(shares.viewerList.single.uid, 'pat');
      await v.remove.execute(pat);
      expect(v.viewers, isEmpty);
      expect(shares.viewerList, isEmpty);
      v.dispose();
    });

    test('search leaves out the user and anyone already on the list', () async {
      final v = vm();
      await pumpEventQueue();
      await v.search.execute('pat');
      expect(v.results.map((p) => p.uid), ['pat']);
      await v.add.execute(pat);
      await v.search.execute('pat');
      expect(v.results, isEmpty);
      v.dispose();
    });

    test('a failed save keeps the list as it was', () async {
      final v = vm();
      await pumpEventQueue();
      shares.fail = true;
      await v.add.execute(pat);
      expect(v.add.error, isTrue);
      expect(v.viewers, isEmpty);
      v.dispose();
    });
  });

  group('widgets', () {
    testWidgets('Calendar sharing: search, share, then remove', (tester) async {
      final shares = FakeCalendarShareRepository()..people['pat'] = pat;
      final profiles = FakeProfileRepository()
        ..profiles['pat'] = const PlayerProfile(
          uid: 'pat',
          name: 'Pat Player',
          username: 'pat',
        );
      final vm = CalendarSharingViewModel(
        calendarShareRepository: shares,
        profileRepository: profiles,
        uid: 'u1',
      );
      addTearDown(vm.dispose);
      await tester.pumpWidget(
        MaterialApp(home: CalendarSharingScreen(viewModel: vm)),
      );
      await tester.pumpAndSettle();
      expect(
        find.text("You aren't sharing your calendar with anyone."),
        findsOneWidget,
      );

      await tester.enterText(find.byType(TextField), 'pat');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Share'));
      await tester.pumpAndSettle();
      expect(shares.viewerList.single.uid, 'pat');
      expect(find.widgetWithText(TextButton, 'Remove'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Remove'));
      await tester.pumpAndSettle();
      expect(shares.viewerList, isEmpty);
    });

    testWidgets('a shared event opens read-only in a sheet', (tester) async {
      final entry = ScheduleEntry(
        sharedBy: pat,
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
      expect(find.text('PAT'), findsOneWidget);
      await tester.tap(find.text('Track'));
      await tester.pumpAndSettle();
      expect(
        find.text("On Pat Player's calendar, shared with you."),
        findsOneWidget,
      );
      expect(find.text('High school track'), findsWidgets);
    });

    testWidgets('without an API, sharing says so', (tester) async {
      final vm = CalendarSharingViewModel(
        calendarShareRepository: FakeCalendarShareRepository(enabled: false),
        profileRepository: FakeProfileRepository(),
        uid: 'u1',
      );
      addTearDown(vm.dispose);
      await tester.pumpWidget(
        MaterialApp(home: CalendarSharingScreen(viewModel: vm)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('needs a connection'), findsOneWidget);
    });
  });
}
