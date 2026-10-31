import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:frisbee_app/data/repositories/meeting/meeting_settings_repository.dart';
import 'package:frisbee_app/data/services/meeting_call.dart';
import 'package:frisbee_app/data/services/meeting_presence.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/meeting.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/meetings/view_models/meeting_detail_viewmodel.dart';
import 'package:frisbee_app/ui/meetings/view_models/meeting_editor_viewmodel.dart';
import 'package:frisbee_app/ui/meetings/view_models/meeting_room_viewmodel.dart';
import 'package:frisbee_app/ui/meetings/widgets/meeting_detail_screen.dart';
import 'package:frisbee_app/ui/meetings/widgets/meeting_editor_screen.dart';
import 'package:frisbee_app/ui/meetings/widgets/meeting_room_screen.dart';

import '../testing/fakes.dart';
import '../testing/meeting_fakes.dart';

const coach = AppUser(uid: 'c', displayName: 'Casey');
const player = AppUser(uid: 'p1', displayName: 'Pat');

void main() {
  late FakeTeamRepository teams;
  late FakeMeetingRepository meetings;
  late FakeMeetingMediaService media;

  setUp(() {
    teams = FakeTeamRepository();
    meetings = FakeMeetingRepository();
    media = FakeMeetingMediaService();
    teams.teams['t1'] = teamWith({
      'o': TeamRole.owner,
      'c': TeamRole.coach,
      'p1': TeamRole.player,
      'p2': TeamRole.player,
    });
    meetings.meetings['m1'] = TeamMeeting(
      id: 'm1',
      title: 'Film review',
      startsAt: DateTime(2030, 1, 1, 19),
      inviteRoles: const {TeamRole.player},
    );
  });

  Future<void> pump(WidgetTester tester, Widget child, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: child));
    await tester.pumpAndSettle();
  }

  MeetingRoomViewModel room(AppUser user) => MeetingRoomViewModel(
    teamId: 't1',
    meetingId: 'm1',
    meetingRepository: meetings,
    teamRepository: teams,
    authRepository: FakeAuthRepository(user: user),
    media: media,
    settingsRepository: FakeMeetingSettingsRepository(
      const MeetingSettings(cameraOn: true),
    ),
    filePicker: FakeFilePickerService(),
    presence: MeetingPresence(),
  );

  for (final size in const [Size(390, 844), Size(1280, 800)]) {
    testWidgets('lobby lets an admin start, then shows the call at $size', (
      tester,
    ) async {
      final vm = room(coach);
      addTearDown(vm.dispose);
      await pump(tester, MeetingRoomScreen(viewModel: vm), size);

      expect(find.text('Film review'), findsOneWidget);
      expect(find.text('video:preview:default:mirrored'), findsOneWidget);
      expect(find.text('Microphone'), findsOneWidget);
      expect(find.text('Meeting volume'), findsOneWidget);

      await tester.ensureVisible(find.text('Start meeting early'));
      await tester.tap(find.text('Start meeting early'));
      await tester.pumpAndSettle();
      expect(vm.stage, RoomStage.inCall);

      media.lastCall.setRemotes(const [
        CallParticipant(uid: 'p1', name: 'Pat', micOn: true, isSpeaking: true),
        CallParticipant(uid: 'p2', name: 'Robin'),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Me (you)'), findsOneWidget);
      expect(find.text('Pat'), findsOneWidget);
      expect(find.text('3 in call'), findsOneWidget);
      expect(find.byTooltip('Share screen'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Tapping someone sets how loud they are, for this user only.
      await tester.tap(find.text('Robin'));
      await tester.pumpAndSettle();
      expect(
        find.text('Only changes how loud Robin is for you.'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Mute for me'));
      await tester.pumpAndSettle();
      expect(media.lastCall.volumes['p2'], 0);
      Navigator.of(tester.element(find.text('Robin').last)).pop();
      await tester.pumpAndSettle();

      // Chat.
      await tester.tap(find.byTooltip('Chat'));
      await tester.pumpAndSettle();
      expect(find.text('Meeting chat'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'Can you hear me?');
      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();
      expect(meetings.messages['m1'], isNotEmpty);
    });
  }

  testWidgets('screen sharing shows the shared screen large', (tester) async {
    meetings.setStatus('m1', MeetingStatus.live);
    final vm = room(player);
    addTearDown(vm.dispose);
    await pump(tester, MeetingRoomScreen(viewModel: vm), const Size(1280, 800));
    await tester.tap(find.text('Join meeting'));
    await tester.pumpAndSettle();

    media.lastCall.setRemotes(const [
      CallParticipant(uid: 'p2', name: 'Robin', screen: FakeCallVideo('deck')),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Robin is presenting'), findsOneWidget);
    expect(find.text('video:deck'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invitees ask to join when approval is required', (tester) async {
    final m = meetings.meetings['m1']!;
    meetings.meetings['m1'] = TeamMeeting(
      id: m.id,
      title: m.title,
      startsAt: m.startsAt,
      inviteRoles: m.inviteRoles,
      requireApproval: true,
      status: MeetingStatus.live,
    );
    final vm = room(player);
    addTearDown(vm.dispose);
    await pump(tester, MeetingRoomScreen(viewModel: vm), const Size(390, 844));
    await tester.ensureVisible(find.text('Ask to join'));
    await tester.tap(find.text('Ask to join'));
    // The waiting spinner never settles.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Waiting for an admin to let you in'), findsOneWidget);
    expect(meetings.requests['m1']!.keys, ['p1']);
  });

  testWidgets('meeting page RSVPs and links to the room', (tester) async {
    final vm = MeetingDetailViewModel(
      teamId: 't1',
      meetingId: 'm1',
      meetingRepository: meetings,
      teamRepository: teams,
      authRepository: FakeAuthRepository(user: player),
    );
    addTearDown(vm.dispose);
    await pump(
      tester,
      MeetingDetailScreen(viewModel: vm),
      const Size(390, 844),
    );
    expect(find.text('Go to meeting room'), findsOneWidget);
    expect(find.text('Everyone'), findsOneWidget);
    expect(find.byTooltip('Edit'), findsNothing);
    await tester.tap(find.text('Attending'));
    await tester.pumpAndSettle();
    expect(meetings.meetings['m1']!.rsvpOf('p1'), MeetingRsvp.attending);
  });

  testWidgets('editor schedules a meeting for picked people', (tester) async {
    final vm = MeetingEditorViewModel(
      teamId: 't1',
      meetingId: null,
      meetingRepository: meetings,
      teamRepository: teams,
      authRepository: FakeAuthRepository(user: coach),
    );
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: '/edit',
      routes: [
        GoRoute(
          path: '/edit',
          builder: (_, _) => MeetingEditorScreen(viewModel: vm),
        ),
        GoRoute(
          path: '/team-meetings/:teamId/:meetingId',
          builder: (_, state) =>
              Text('meeting ${state.pathParameters['meetingId']}'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Captains sync');
    await tester.tap(find.text('All players'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(CheckboxListTile).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.ensureVisible(find.text('Schedule meeting'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Require admin approval to join'));
    await tester.tap(find.text('Schedule meeting'));
    await tester.pumpAndSettle();
    expect(find.text('meeting m2'), findsOneWidget);
    final saved = meetings.meetings.values.firstWhere(
      (m) => m.title == 'Captains sync',
    );
    expect(saved.inviteRoles, isEmpty);
    expect(saved.inviteUsers, hasLength(1));
    expect(saved.requireApproval, isTrue);
  });
}
