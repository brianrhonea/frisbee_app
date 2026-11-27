// TEMPORARY (redesign subtask 3c): phone screenshots of the schedule,
// event and meeting screens on fake data. Skipped unless asked for:
//   flutter test test/screenshots/schedule_test.dart \
//     --dart-define=SCREENSHOTS=<out dir> [--dart-define=SHOT_THEME=dark]
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/auth/auth_repository.dart';
import 'package:frisbee_app/data/repositories/calendar/calendar_repository.dart';
import 'package:frisbee_app/data/repositories/event/event_repository.dart';
import 'package:frisbee_app/data/repositories/group_tournament/group_tournament_repository.dart';
import 'package:frisbee_app/data/repositories/meeting/meeting_repository.dart';
import 'package:frisbee_app/data/repositories/meeting/meeting_settings_repository.dart';
import 'package:frisbee_app/data/repositories/team/team_repository.dart';
import 'package:frisbee_app/data/repositories/user_post/user_post_repository.dart';
import 'package:frisbee_app/data/services/meeting_call.dart';
import 'package:frisbee_app/data/services/meeting_presence.dart';
import 'package:frisbee_app/domain/models/meeting.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/team_event.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/meetings/view_models/meeting_detail_viewmodel.dart';
import 'package:frisbee_app/ui/meetings/view_models/meeting_editor_viewmodel.dart';
import 'package:frisbee_app/ui/meetings/view_models/meeting_room_viewmodel.dart';
import 'package:frisbee_app/ui/meetings/widgets/meeting_detail_screen.dart';
import 'package:frisbee_app/ui/meetings/widgets/meeting_editor_screen.dart';
import 'package:frisbee_app/ui/meetings/widgets/meeting_room_screen.dart';
import 'package:frisbee_app/ui/schedule/view_models/event_detail_viewmodel.dart';
import 'package:frisbee_app/ui/schedule/view_models/event_editor_viewmodel.dart';
import 'package:frisbee_app/ui/schedule/view_models/my_event_detail_viewmodel.dart';
import 'package:frisbee_app/ui/schedule/view_models/schedule_viewmodel.dart';
import 'package:frisbee_app/ui/schedule/widgets/event_detail_screen.dart';
import 'package:frisbee_app/ui/schedule/widgets/my_event_detail_screen.dart';
import 'package:frisbee_app/ui/schedule/widgets/team_events_tab.dart';
import 'package:frisbee_app/ui/schedule/widgets/event_editor_screen.dart';
import 'package:frisbee_app/ui/schedule/widgets/schedule_screen.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'shot_env.dart';
import '../testing/fakes.dart';
import '../testing/group_tournament_fakes.dart';
import '../testing/meeting_fakes.dart';
import '../testing/social_fakes.dart';
import '../testing/video_fakes.dart';

const _out = String.fromEnvironment('SCREENSHOTS');
const _dark = String.fromEnvironment('SHOT_THEME') == 'dark';

Future<void> _loadFonts() async {
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final f in files) {
      final bytes = File(f).readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  await family('Inter', [
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold'])
      'assets/fonts/Inter-$w.ttf',
  ]);
  await family('Barlow Condensed', [
    for (final w in ['Bold', 'ExtraBold', 'ExtraBoldItalic'])
      'assets/fonts/BarlowCondensed-$w.ttf',
  ]);
  var dir = File(Platform.resolvedExecutable).parent;
  const icons = 'bin/cache/artifacts/material_fonts/materialicons-regular.otf';
  while (!File('${dir.path}/$icons').existsSync() && dir.parent != dir) {
    dir = dir.parent;
  }
  await family('MaterialIcons', ['${dir.path}/$icons']);
}

void main() {
  final skip = _out.isEmpty ? 'pass --dart-define=SCREENSHOTS=<dir>' : null;

  final shot = GlobalKey();
  final me = testUser.uid;
  final now = DateTime.now();
  DateTime at(int days, int hour, [int minute = 0]) =>
      DateTime(now.year, now.month, now.day + days, hour, minute);

  Team team() => Team(
    id: 't1',
    name: 'Northside Flyers',
    division: Division.mixed,
    level: CompetitionLevel.club,
    city: 'Denver',
    ownerId: me,
    createdAt: DateTime(2019),
    members: {
      me: TeamRole.owner,
      'coach': TeamRole.coach,
      'sam': TeamRole.player,
      'jo': TeamRole.player,
      'ava': TeamRole.player,
      'dev': TeamRole.player,
    },
    memberNames: {
      me: 'Test User',
      'coach': 'Riley Chen',
      'sam': 'Sam Ortiz',
      'jo': 'Jo Park',
      'ava': 'Ava Brooks',
      'dev': 'Dev Patel',
    },
  );

  Future<void> capture(WidgetTester tester, String name) async {
    await tester.pumpAndSettle();
    final boundary =
        shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory(_out).createSync(recursive: true);
      File('$_out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
  }

  Future<void> size(WidgetTester tester) async {
    await tester.runAsync(_loadFonts);
    tester.view.physicalSize = const Size(shotWidth * 3.0, shotHeight * 3.0);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  testWidgets('schedule and event screens', skip: skip != null, (tester) async {
    await size(tester);
    final teams = FakeTeamRepository()..teams['t1'] = team();
    final events = FakeEventRepository()
      ..events['e1'] = TeamEvent(
        id: 'e1',
        title: 'Thursday practice: zone offense and end-zone sets',
        startsAt: at(0, 18),
        endsAt: at(0, 20),
        location: 'Washington Park, Field 2',
        notes:
            'Bring dark and light jerseys. Zone offence focus before '
            "Snowmelt Hat. Carpool from Sam's at 5:30.",
        rsvps: {
          me: RsvpStatus.going,
          'sam': RsvpStatus.going,
          'coach': RsvpStatus.going,
          'jo': RsvpStatus.maybe,
          'dev': RsvpStatus.notGoing,
        },
        poll: const EventPoll(
          question: 'Who can drive?',
          options: [
            PollOption(id: 'a', text: 'I can take 3'),
            PollOption(id: 'b', text: 'Need a ride'),
          ],
        ),
        votes: {
          me: ['a'],
          'sam': ['b'],
        },
      )
      ..events['e2'] = TeamEvent(
        id: 'e2',
        title: 'Team dinner before the hat',
        type: EventType.social,
        startsAt: at(1, 18, 30),
        location: "Sam's place",
        rsvps: const {'sam': RsvpStatus.going, 'jo': RsvpStatus.maybe},
      )
      ..events['e3'] = TeamEvent(
        id: 'e3',
        title: 'Snowmelt Hat',
        type: EventType.tournament,
        startsAt: at(2, 9),
        location: 'Fields 1–4',
        rsvps: {me: RsvpStatus.going},
      );
    events.mine[me] = {
      'p1': TeamEvent(
        id: 'p1',
        title: 'Tempo run',
        type: EventType.workout,
        startsAt: at(0, 7),
        endsAt: at(0, 7, 45),
        location: 'City Park loop',
        notes:
            '10 min easy warm-up. 3 × 10 min at threshold pace, 2 min jog '
            'between. Finish with 6 strides and 10 min easy.',
      ),
    };
    final meetings = FakeMeetingRepository()
      ..meetings['m1'] = TeamMeeting(
        id: 'm1',
        title: 'Film review: Mile High Open',
        startsAt: at(0, 20, 30),
        endsAt: at(0, 21, 30),
        inviteRoles: const {TeamRole.player, TeamRole.coach},
      );
    final posts = FakeUserPostRepository();
    final auth = FakeAuthRepository(user: testUser);
    final calendars = FakeCalendarRepository();
    Future<void> pump(Widget child) async {
      await tester.pumpWidget(
        RepaintBoundary(
          key: shot,
          child: MultiProvider(
            providers: [
              ChangeNotifierProvider<AuthRepository>.value(value: auth),
              Provider<TeamRepository>.value(value: teams),
              Provider<EventRepository>.value(value: events),
              Provider<MeetingRepository>.value(value: meetings),
              Provider<CalendarRepository?>.value(value: calendars),
              Provider<UserPostRepository?>.value(value: posts),
              Provider<GroupTournamentRepository>.value(
                value: FakeGroupTournamentRepository(),
              ),
            ],
            child: MaterialApp.router(
              debugShowCheckedModeBanner: false,
              theme: _dark ? AppTheme.dark : AppTheme.light,
              routerConfig: GoRouter(
                routes: [GoRoute(path: '/', builder: (_, _) => child)],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> close() async {
      final nav = tester.state<NavigatorState>(find.byType(Navigator).last);
      nav.pop();
      await tester.pumpAndSettle();
    }

    final schedule = ScheduleViewModel(
      authRepository: auth,
      teamRepository: teams,
      eventRepository: events,
      meetingRepository: meetings,
      calendarRepository: calendars,
      clock: () => at(0, 12),
    );
    addTearDown(schedule.dispose);
    await pump(
      ScheduleScreen(
        viewModel: schedule,
        profile: const Padding(
          padding: EdgeInsets.all(10),
          child: CircleAvatar(child: Text('A')),
        ),
      ),
    );
    await capture(tester, '01-schedule-week');
    schedule.nextWeek();
    await capture(tester, '01b-schedule-next-week');
    schedule.goToToday();
    await tester.pumpAndSettle();
    final ctx = tester.element(find.byType(ScheduleScreen));
    showEventDetails(ctx, teamId: 't1', eventId: 'e2');
    await capture(tester, '06-rsvp-sheet');
    await close();
    showEventEditor(ctx, day: now);
    await capture(tester, '04b-editor-panel');
    await close();

    final detail = EventDetailViewModel(
      teamId: 't1',
      eventId: 'e1',
      eventRepository: events,
      teamRepository: teams,
      authRepository: auth,
      tournamentRepository: FakeGroupTournamentRepository(),
    );
    addTearDown(detail.dispose);
    await pump(EventDetailScreen(viewModel: detail));
    await capture(tester, '03-team-event');
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -600));
    await capture(tester, '03b-team-event-scrolled');
    final tourney = EventDetailViewModel(
      teamId: 't1',
      eventId: 'e3',
      eventRepository: events,
      teamRepository: teams,
      authRepository: auth,
      tournamentRepository: FakeGroupTournamentRepository(),
    );
    addTearDown(tourney.dispose);
    await pump(EventDetailScreen(viewModel: tourney));
    await capture(tester, '03c-tournament-event');

    final editor = EventEditorViewModel(
      teamId: 't1',
      eventId: null,
      initialDay: now,
      eventRepository: events,
      teamRepository: teams,
      authRepository: auth,
      postRepository: posts,
      calendarRepository: calendars,
    );
    addTearDown(editor.dispose);
    await pump(EventEditorScreen(viewModel: editor));
    await capture(tester, '04-event-editor');
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -700));
    await capture(tester, '04c-event-editor-scrolled');

    final mine = MyEventDetailViewModel(
      eventId: 'p1',
      eventRepository: events,
      authRepository: auth,
    );
    addTearDown(mine.dispose);
    await pump(MyEventDetailScreen(viewModel: mine));
    await capture(tester, '05-personal-event');

    await pump(
      Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final e in events.events.values)
              TeamEventCard(event: e, uid: me, onTap: () {}),
          ],
        ),
      ),
    );
    await capture(tester, '07-team-schedule');
    await pump(const SizedBox());
  });

  Future<void> pumpScreen(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      RepaintBoundary(
        key: shot,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _dark ? AppTheme.dark : AppTheme.light,
          home: child,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('meeting screens', skip: skip != null, (tester) async {
    await size(tester);
    final teams = FakeTeamRepository()..teams['t1'] = team();
    final meetings = FakeMeetingRepository()
      ..meetings['m1'] = TeamMeeting(
        id: 'm1',
        title: 'Film review: Mile High Open',
        startsAt: at(0, 20, 30),
        endsAt: at(0, 21, 30),
        notes:
            '1. Semi vs Boulder Gold: our zone breaks\n'
            '2. End-zone sets that worked\n'
            '3. Lines and goals for Snowmelt Hat',
        inviteRoles: const {TeamRole.player, TeamRole.coach},
        requireApproval: true,
        rsvps: {
          me: MeetingRsvp.attending,
          'sam': MeetingRsvp.attending,
          'dev': MeetingRsvp.notAttending,
        },
      );
    final auth = FakeAuthRepository(user: testUser);

    final detail = MeetingDetailViewModel(
      teamId: 't1',
      meetingId: 'm1',
      meetingRepository: meetings,
      teamRepository: teams,
      authRepository: auth,
    );
    addTearDown(detail.dispose);
    await pumpScreen(tester, MeetingDetailScreen(viewModel: detail));
    await capture(tester, '10-meeting-detail');

    final editor = MeetingEditorViewModel(
      teamId: 't1',
      meetingId: null,
      meetingRepository: meetings,
      teamRepository: teams,
      authRepository: auth,
    );
    addTearDown(editor.dispose);
    await pumpScreen(tester, MeetingEditorScreen(viewModel: editor));
    await capture(tester, '11-meeting-editor');

    final media = FakeMeetingMediaService();
    final room = MeetingRoomViewModel(
      teamId: 't1',
      meetingId: 'm1',
      meetingRepository: meetings,
      teamRepository: teams,
      authRepository: auth,
      media: media,
      settingsRepository: FakeMeetingSettingsRepository(
        const MeetingSettings(cameraOn: true),
      ),
      filePicker: FakeFilePickerService(),
      presence: MeetingPresence(),
      videoRepository: FakeVideoRepository(),
    );
    addTearDown(room.dispose);
    await pumpScreen(tester, MeetingRoomScreen(viewModel: room));
    await capture(tester, '12-meeting-lobby');
    await tester.ensureVisible(find.textContaining('Start meeting'));
    await tester.tap(find.textContaining('Start meeting'));
    await tester.pumpAndSettle();
    media.lastCall.setRemotes(const [
      CallParticipant(
        uid: 'coach',
        name: 'Riley Chen',
        micOn: true,
        isSpeaking: true,
      ),
      CallParticipant(uid: 'sam', name: 'Sam Ortiz', micOn: true),
      CallParticipant(uid: 'dev', name: 'Dev Patel'),
    ]);
    await capture(tester, '13-meeting-room');
    await pumpScreen(tester, const SizedBox());
  });
}
