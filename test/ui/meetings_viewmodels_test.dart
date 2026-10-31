import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/meeting/meeting_settings_repository.dart';
import 'package:frisbee_app/data/services/meeting_call.dart';
import 'package:frisbee_app/data/services/meeting_presence.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/meeting.dart';
import 'package:frisbee_app/domain/models/notification.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/team_event.dart';
import 'package:frisbee_app/ui/meetings/view_models/meeting_alerts_viewmodel.dart';
import 'package:frisbee_app/ui/meetings/view_models/meeting_detail_viewmodel.dart';
import 'package:frisbee_app/ui/meetings/view_models/meeting_editor_viewmodel.dart';
import 'package:frisbee_app/ui/meetings/view_models/meeting_room_viewmodel.dart';
import 'package:frisbee_app/ui/schedule/view_models/schedule_viewmodel.dart';
import 'package:frisbee_app/ui/teams/view_models/team_detail_viewmodel.dart';
import 'package:frisbee_app/utils/result.dart';

import '../testing/fakes.dart';
import '../testing/meeting_fakes.dart';

const coach = AppUser(uid: 'c', displayName: 'Casey');
const player = AppUser(uid: 'p1', displayName: 'Pat');
const other = AppUser(uid: 'p2', displayName: 'Robin');

void main() {
  late FakeTeamRepository teams;
  late FakeMeetingRepository meetings;
  late FakeMeetingMediaService media;
  late FakeMeetingSettingsRepository settings;
  late MeetingPresence presence;

  setUp(() {
    teams = FakeTeamRepository();
    meetings = FakeMeetingRepository();
    media = FakeMeetingMediaService();
    settings = FakeMeetingSettingsRepository();
    presence = MeetingPresence();
    teams.teams['t1'] = teamWith({
      'o': TeamRole.owner,
      'c': TeamRole.coach,
      'p1': TeamRole.player,
      'p2': TeamRole.player,
    });
    meetings.meetings['m1'] = TeamMeeting(
      id: 'm1',
      title: 'Film',
      startsAt: DateTime(2030, 1, 1, 19),
      inviteUsers: const {'p1'},
    );
  });

  MeetingRoomViewModel room(AppUser user) => MeetingRoomViewModel(
    teamId: 't1',
    meetingId: 'm1',
    meetingRepository: meetings,
    teamRepository: teams,
    authRepository: FakeAuthRepository(user: user),
    media: media,
    settingsRepository: settings,
    filePicker: FakeFilePickerService(),
    presence: presence,
  );

  void requireApproval() {
    final m = meetings.meetings['m1']!;
    meetings.meetings['m1'] = TeamMeeting(
      id: m.id,
      title: m.title,
      startsAt: m.startsAt,
      inviteUsers: m.inviteUsers,
      requireApproval: true,
    );
  }

  group('MeetingRoomViewModel lobby', () {
    test('admins can start before it begins; invitees wait', () async {
      final admin = room(coach);
      final invitee = room(player);
      final outsider = room(other);
      await pumpEventQueue();
      expect(admin.lobbyState, LobbyState.canStart);
      expect(admin.isEarly, isTrue);
      expect(invitee.lobbyState, LobbyState.waitingToStart);
      expect(outsider.lobbyState, LobbyState.unavailable);
      for (final vm in [admin, invitee, outsider]) {
        vm.dispose();
      }
    });

    test('starting opens the meeting and joins with the lobby setup', () async {
      settings.saved = const MeetingSettings(
        cameraOn: true,
        micOn: false,
        audioInputId: 'mic2',
      );
      final vm = room(coach);
      await pumpEventQueue();
      expect(vm.preview, isNotNull);
      expect(vm.selected(MediaDeviceKind.audioInput)?.label, 'Headset');

      await vm.start.execute();
      expect(vm.start.completed, isTrue, reason: '${vm.start.result}');
      expect(meetings.meetings['m1']!.isLive, isTrue);
      expect(vm.stage, RoomStage.inCall);
      final setup = media.lastCall.setup!;
      expect(setup.cameraOn, isTrue);
      expect(setup.micOn, isFalse);
      expect(setup.audioInputId, 'mic2');
      expect(
        media.previews.single.disposed,
        isTrue,
        reason: 'the call needs the camera',
      );
      expect(vm.chat, isNotNull);
      vm.dispose();
      expect(media.lastCall.left, isTrue);
    });

    test('invitees who asked to join go in once it starts', () async {
      final vm = room(player);
      await pumpEventQueue();
      vm.setWantsIn(true);
      expect(vm.stage, RoomStage.lobby);
      meetings.setStatus('m1', MeetingStatus.live);
      await pumpEventQueue();
      expect(vm.stage, RoomStage.inCall);
      vm.dispose();
    });

    test('with approval on, invitees ask and join when let in', () async {
      requireApproval();
      meetings.setStatus('m1', MeetingStatus.live);
      final vm = room(player);
      final admin = room(coach);
      await pumpEventQueue();
      expect(vm.lobbyState, LobbyState.canAsk);
      expect(admin.lobbyState, LobbyState.canJoin);

      await vm.askToJoin.execute();
      await pumpEventQueue();
      expect(vm.lobbyState, LobbyState.waitingForApproval);
      expect(admin.pendingRequests.map((r) => r.name), ['Pat']);
      expect(meetings.tokenRequests, 0);

      await admin.decide.execute((uid: 'p1', admit: true));
      await pumpEventQueue();
      expect(vm.stage, RoomStage.inCall);
      expect(admin.pendingRequests, isEmpty);
      vm.dispose();
      admin.dispose();
    });

    test('turned away invitees can ask again', () async {
      requireApproval();
      meetings.setStatus('m1', MeetingStatus.live);
      final vm = room(player);
      final admin = room(coach);
      await pumpEventQueue();
      await vm.askToJoin.execute();
      await pumpEventQueue();
      await admin.decide.execute((uid: 'p1', admit: false));
      await pumpEventQueue();
      expect(vm.lobbyState, LobbyState.canAsk);
      expect(vm.myRequest?.isDenied, isTrue);
      expect(vm.stage, RoomStage.lobby);
      vm.dispose();
      admin.dispose();
    });

    test('a refused join token keeps the user in the lobby', () async {
      meetings.setStatus('m1', MeetingStatus.live);
      meetings.token = Result.error(Exception('An admin needs to let you in'));
      final vm = room(player);
      await pumpEventQueue();
      await vm.join.execute();
      expect(vm.join.error, isTrue);
      expect(vm.stage, RoomStage.lobby);
      expect(media.calls, isEmpty);
      vm.dispose();
    });

    test('camera and mic permission problems are explained', () async {
      media.cameraAllowed = false;
      media.micAllowed = false;
      final vm = room(player);
      await pumpEventQueue();
      expect(vm.micOn, isFalse, reason: 'mic starts on, but was refused');
      expect(vm.mediaNotice, contains('microphone'));
      await vm.toggleCamera.execute();
      expect(vm.cameraOn, isFalse);
      expect(vm.mediaNotice, contains('camera'));
      vm.dispose();
    });

    test('picking a camera restarts the preview and is remembered', () async {
      settings.saved = const MeetingSettings(cameraOn: true);
      final vm = room(player);
      await pumpEventQueue();
      final cam = vm.devicesOf(MediaDeviceKind.videoInput).single;
      await vm.useDevice.execute(cam);
      expect(media.previews.last.deviceId, 'cam1');
      expect(media.previews.first.disposed, isTrue);
      expect(settings.saved.videoInputId, 'cam1');
      vm.dispose();
    });

    test('the room marks the user present for alerts', () async {
      final vm = room(player);
      expect(presence.isIn('t1', 'm1'), isTrue);
      vm.dispose();
      expect(presence.isIn('t1', 'm1'), isFalse);
    });
  });

  group('MeetingRoomViewModel call', () {
    Future<MeetingRoomViewModel> inCall() async {
      meetings.setStatus('m1', MeetingStatus.live);
      final vm = room(coach);
      await pumpEventQueue();
      await vm.join.execute();
      media.lastCall.setRemotes(const [
        CallParticipant(uid: 'p1', name: 'Pat'),
        CallParticipant(uid: 'o', name: 'Olive'),
      ]);
      return vm;
    }

    test('volumes are the meeting level times each person, per user', () async {
      final vm = await inCall();
      final call = media.lastCall;
      expect(call.volumes, {'p1': 1, 'o': 1});
      vm.setOutputVolume(0.5);
      vm.setVolumeOf('p1', 2);
      expect(call.volumes, {'p1': 1, 'o': 0.5});
      vm.saveVolumes();
      expect(settings.saved.volumeOf('p1'), 2);
      expect(settings.saved.outputVolume, 0.5);

      vm.toggleAudioMuted();
      expect(call.volumes, {'p1': 0, 'o': 0});
      vm.toggleAudioMuted();
      expect(call.volumes['p1'], 1);
      vm.dispose();
    });

    test('mic, camera and screen sharing go through the call', () async {
      final vm = await inCall();
      final micBefore = vm.micOn;
      await vm.toggleMic.execute();
      expect(vm.micOn, !micBefore);
      await vm.toggleCamera.execute();
      expect(media.lastCall.cameraOn, isTrue);
      await vm.setScreenSharing.execute((on: true, sourceId: 'window:7'));
      expect(media.lastCall.screenSource, 'window:7');
      expect(vm.presenter?.isLocal, isTrue);
      final mic = vm.devicesOf(MediaDeviceKind.audioInput).first;
      await vm.useDevice.execute(mic);
      expect(media.lastCall.usedDevices, [mic]);
      vm.dispose();
    });

    test('the meeting ending elsewhere hangs up', () async {
      final vm = await inCall();
      meetings.setStatus('m1', MeetingStatus.ended);
      await pumpEventQueue();
      expect(vm.stage, RoomStage.left);
      expect(vm.endNotice, 'The meeting has ended.');
      expect(media.lastCall.left, isTrue);
      expect(vm.chat, isNull);
      vm.dispose();
    });

    test('a lost call says why; leaving lets you rejoin', () async {
      final vm = await inCall();
      media.lastCall.end(CallEndReason.connectionLost);
      await pumpEventQueue();
      expect(vm.stage, RoomStage.left);
      expect(vm.endNotice, contains('connection'));
      vm.backToLobby();
      expect(vm.stage, RoomStage.lobby);
      expect(vm.lobbyState, LobbyState.canJoin);
      vm.dispose();
    });

    test('admins end the meeting for everyone', () async {
      final vm = await inCall();
      await vm.endMeeting.execute();
      expect(meetings.ended, ['m1']);
      expect(vm.stage, RoomStage.left);
      vm.dispose();
    });

    test('chat counts messages from others while hidden', () async {
      final vm = await inCall();
      final chat = vm.chat!;
      await pumpEventQueue();
      await meetings.sendMessage('t1', 'm1', author: player, text: 'Hi');
      await pumpEventQueue();
      expect(chat.unread, 1);
      await chat.send.execute('Hello');
      await pumpEventQueue();
      expect(chat.unread, 1, reason: 'your own messages are not unread');
      chat.visible = true;
      expect(chat.unread, 0);
      expect(chat.canAttach, isFalse);
      expect(chat.canDelete(chat.messages.first), isTrue, reason: 'admins');
      vm.dispose();
    });
  });

  group('MeetingEditorViewModel', () {
    test('new meetings invite everyone; only admins may edit', () async {
      final vm = MeetingEditorViewModel(
        teamId: 't1',
        meetingId: null,
        meetingRepository: meetings,
        teamRepository: teams,
        authRepository: FakeAuthRepository(user: coach),
      );
      await pumpEventQueue();
      expect(vm.load.completed, isTrue);
      expect(vm.initial.inviteRoles, {TeamRole.player});
      expect(vm.invitableMembers.map((m) => m.uid), ['p1', 'p2']);

      final denied = MeetingEditorViewModel(
        teamId: 't1',
        meetingId: null,
        meetingRepository: meetings,
        teamRepository: teams,
        authRepository: FakeAuthRepository(user: player),
      );
      await pumpEventQueue();
      expect(denied.load.error, isTrue);
    });

    test(
      'saving drops people already invited by role, and non-members',
      () async {
        final vm = MeetingEditorViewModel(
          teamId: 't1',
          meetingId: null,
          meetingRepository: meetings,
          teamRepository: teams,
          authRepository: FakeAuthRepository(user: coach),
        );
        await pumpEventQueue();
        await vm.save.execute(
          vm.initial.copyWith(
            title: 'Sync',
            inviteRoles: {},
            inviteUsers: {'p1', 'gone', 'c'},
          ),
        );
        final saved = meetings.meetings[(vm.save.result as Ok<String>).value]!;
        expect(saved.inviteUsers, {'p1'});

        await vm.save.execute(
          vm.initial.copyWith(title: 'All', inviteUsers: {'p1'}),
        );
        final all = meetings.meetings[(vm.save.result as Ok<String>).value]!;
        expect(all.inviteUsers, isEmpty);
      },
    );
  });

  group('MeetingDetailViewModel', () {
    test('RSVPs count invitees only', () async {
      final vm = MeetingDetailViewModel(
        teamId: 't1',
        meetingId: 'm1',
        meetingRepository: meetings,
        teamRepository: teams,
        authRepository: FakeAuthRepository(user: player),
      );
      await pumpEventQueue();
      await vm.setRsvp.execute(MeetingRsvp.attending);
      await meetings.setRsvp('t1', 'm1', 'p2', MeetingRsvp.attending);
      await pumpEventQueue();
      expect(vm.myRsvp, MeetingRsvp.attending);
      expect(vm.responses[MeetingRsvp.attending], hasLength(1));
      expect(vm.inviteeCount, 3);
      expect(vm.noResponse, hasLength(2));
      expect(vm.canEdit, isFalse);
      vm.dispose();
    });
  });

  group('schedules', () {
    test(
      'team events tab and schedule show meetings the user can see',
      () async {
        final teamVm = TeamDetailViewModel(
          teamId: 't1',
          teamRepository: teams,
          playRepository: FakePlayRepository(),
          eventRepository: FakeEventRepository(),
          meetingRepository: meetings,
          authRepository: FakeAuthRepository(user: player),
          clock: () => DateTime(2029),
        );
        final hidden = TeamDetailViewModel(
          teamId: 't1',
          teamRepository: teams,
          playRepository: FakePlayRepository(),
          eventRepository: FakeEventRepository(),
          meetingRepository: meetings,
          authRepository: FakeAuthRepository(user: other),
        );
        final schedule = ScheduleViewModel(
          authRepository: FakeAuthRepository(user: player),
          teamRepository: teams,
          eventRepository: FakeEventRepository(),
          meetingRepository: meetings,
          clock: () => DateTime(2030, 1, 1),
        );
        await pumpEventQueue();
        expect(teamVm.upcomingEvents.single.type, EventType.meeting);
        expect(hidden.events, isEmpty);
        final entry = schedule.eventsOn(DateTime(2030, 1, 1)).single;
        expect(entry.isMeeting, isTrue);
        expect(schedule.canDelete(entry), isFalse);

        meetings.setStatus('m1', MeetingStatus.ended);
        await pumpEventQueue();
        expect(teamVm.events, isEmpty, reason: 'ended meetings drop off');
        teamVm.dispose();
        hidden.dispose();
        schedule.dispose();
      },
    );
  });

  group('MeetingAlertsViewModel', () {
    AppNotification notice(String id, DateTime at, {String? route}) =>
        AppNotification(
          id: id,
          category: NotificationCategory.meetings,
          title: 'Film has started',
          route: route ?? '/team-meetings/t1/m1/room',
          createdAt: at,
        );

    test('pops up new "meeting started" notices once', () async {
      final now = DateTime(2030, 1, 1, 19);
      final notifications = FakeNotificationRepository(
        feed: [
          notice(
            'meetingStarted_t1_old',
            now.subtract(const Duration(hours: 1)),
          ),
        ],
      );
      final vm = MeetingAlertsViewModel(
        authRepository: FakeAuthRepository(user: player),
        notificationRepository: notifications,
        presence: presence,
        clock: () => now,
      );
      await pumpEventQueue();
      expect(vm.takeAlert(), isNull, reason: 'from before the app opened');

      notifications.feed.insert(
        0,
        notice('meetingStarted_t1_m1', now.add(const Duration(seconds: 1))),
      );
      notifications.feed.insert(
        0,
        AppNotification(
          id: 'meeting_t1_m1',
          category: NotificationCategory.meetings,
          title: 'Invited',
          createdAt: now.add(const Duration(seconds: 2)),
        ),
      );
      notifications.emit();
      await pumpEventQueue();
      final alert = vm.takeAlert();
      expect(alert?.id, 'meetingStarted_t1_m1');
      expect(vm.takeAlert(), isNull);

      notifications.emit();
      await pumpEventQueue();
      expect(vm.takeAlert(), isNull, reason: 'shown once');

      vm.opened(alert!);
      await pumpEventQueue();
      expect(
        notifications.feed.firstWhere((n) => n.id == alert.id).read,
        isTrue,
      );
      vm.dispose();
    });

    test('skips the meeting the user is already in', () async {
      final now = DateTime(2030, 1, 1, 19);
      final notifications = FakeNotificationRepository();
      final vm = MeetingAlertsViewModel(
        authRepository: FakeAuthRepository(user: player),
        notificationRepository: notifications,
        presence: presence,
        clock: () => now,
      );
      presence.enter('t1', 'm1');
      notifications.feed.add(
        notice('meetingStarted_t1_m1', now.add(const Duration(seconds: 1))),
      );
      notifications.emit();
      await pumpEventQueue();
      expect(vm.takeAlert(), isNull);
      vm.dispose();
    });
  });
}
