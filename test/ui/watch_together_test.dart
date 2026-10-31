import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/services/synced_video.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/meeting.dart';
import 'package:frisbee_app/domain/models/meeting_playback.dart';
import 'package:frisbee_app/domain/models/team_video.dart';
import 'package:frisbee_app/domain/models/video_folder.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/meetings/view_models/watch_together_viewmodel.dart';
import 'package:frisbee_app/ui/meetings/widgets/watch_together_view.dart';

import '../testing/meeting_fakes.dart';
import '../testing/video_fakes.dart';

const coach = AppUser(uid: 'c', displayName: 'Casey');
const captain = AppUser(uid: 'cap', displayName: 'Cam');
const player = AppUser(uid: 'p1', displayName: 'Pat');

/// A player that does what it's told, instantly, unless [blocked].
class FakeSyncedController implements SyncedVideoController {
  Duration position = Duration.zero;
  Duration duration = const Duration(minutes: 10);
  bool playing = false;
  bool ready = true;

  /// Like a platform that won't autoplay.
  bool blocked = false;
  double volume = 1;
  final calls = <String>[];

  @override
  Future<void> play() async {
    calls.add('play');
    if (!blocked) playing = true;
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    playing = false;
  }

  @override
  Future<void> seekTo(Duration p) async {
    calls.add('seek ${p.inSeconds}');
    position = p;
  }

  @override
  Future<void> setVolume(double v) async => volume = v;

  @override
  Future<PlayerStatus?> status() async =>
      ready ? (position: position, duration: duration, playing: playing) : null;
}

void main() {
  late FakeMeetingRepository meetings;
  late FakeVideoRepository videos;
  late DateTime now;

  setUp(() {
    now = DateTime(2026, 11, 2, 19);
    meetings = FakeMeetingRepository()..serverNow = () => now;
    meetings.meetings['m1'] = TeamMeeting(
      id: 'm1',
      title: 'Film',
      startsAt: DateTime(2026, 11, 2, 19),
      status: MeetingStatus.live,
    );
    videos = FakeVideoRepository();
    videos.videos['t1'] = [
      const TeamVideo(id: 'v1', youtubeId: 'dQw4w9WgXcQ', title: 'Zone O'),
      const TeamVideo(
        id: 'v2',
        title: 'Tryouts',
        folderId: 'f1',
        file: VideoFile(path: 'p', name: 'tryouts.mkv', size: 1),
      ),
    ];
    videos.folders['t1'] = [const VideoFolder(id: 'f1', name: 'Game film')];
  });

  WatchTogetherViewModel watcher(AppUser user, {bool admin = false}) {
    final vm = WatchTogetherViewModel(
      teamId: 't1',
      meetingId: 'm1',
      meetingRepository: meetings,
      videoRepository: videos,
      user: user,
      canControl: admin,
      clock: () => now,
      autoTick: false,
    );
    addTearDown(vm.dispose);
    return vm;
  }

  test('the presenter plays a video and everyone follows', () async {
    final host = watcher(coach, admin: true);
    final viewer = watcher(player);
    final hostPlayer = FakeSyncedController();
    final viewerPlayer = FakeSyncedController();
    await pumpEventQueue();

    await host.show.execute('v1');
    await pumpEventQueue();
    expect(viewer.active, isTrue);
    expect(viewer.video?.title, 'Zone O');
    expect(viewer.isPresenter, isFalse);
    expect(host.controlling, isTrue);
    host.attach(hostPlayer);
    viewer.attach(viewerPlayer);
    await pumpEventQueue();

    await host.play.execute();
    await pumpEventQueue();
    expect(hostPlayer.playing, isTrue);
    expect(viewerPlayer.playing, isTrue);

    // Time passes on both; the viewer's player lags behind and catches up.
    now = now.add(const Duration(seconds: 30));
    hostPlayer.position = const Duration(seconds: 30);
    viewerPlayer.position = const Duration(seconds: 20);
    await viewer.tick();
    expect(viewerPlayer.calls.last, 'seek 30');

    // Small drift is left alone, so playback doesn't stutter.
    viewerPlayer.position = const Duration(seconds: 29);
    viewerPlayer.calls.clear();
    await viewer.tick();
    expect(viewerPlayer.calls, isEmpty);

    // Pause and seek follow.
    await host.pause.execute();
    await pumpEventQueue();
    expect(viewerPlayer.playing, isFalse);
    await host.seek.execute(const Duration(minutes: 4));
    await pumpEventQueue();
    expect(viewerPlayer.position, const Duration(minutes: 4));
    expect(hostPlayer.position, const Duration(minutes: 4));

    await host.stop.execute();
    await pumpEventQueue();
    expect(viewer.active, isFalse);
  });

  test('the presenter keeps everyone in step while it plays', () async {
    final host = watcher(coach, admin: true);
    final hostPlayer = FakeSyncedController();
    await pumpEventQueue();
    await host.show.execute('v1');
    await pumpEventQueue();
    host.attach(hostPlayer);
    await host.play.execute();
    await pumpEventQueue();
    final writes = meetings.playbackWrites.length;

    now = now.add(const Duration(seconds: 5));
    await host.tick();
    expect(meetings.playbackWrites, hasLength(writes));

    // After the heartbeat interval, its real position is written, e.g.
    // after it buffered for a few seconds.
    now = now.add(const Duration(seconds: 6));
    hostPlayer.position = const Duration(seconds: 8);
    await host.tick();
    expect(meetings.playbackWrites.last.position, const Duration(seconds: 8));
    expect(meetings.playbackWrites.last.playing, isTrue);

    // At the end it's written as paused, so viewers stop too.
    hostPlayer
      ..position = hostPlayer.duration
      ..playing = false;
    await host.tick();
    expect(meetings.playbackWrites.last.playing, isFalse);
  });

  test('someone joining late starts where everyone is', () async {
    meetings.playback['m1'] = MeetingPlayback(
      videoId: 'v1',
      playing: true,
      position: const Duration(minutes: 2),
      presenterId: 'c',
      presenterName: 'Casey',
      updatedAt: now.subtract(const Duration(seconds: 15)),
    );
    final late = watcher(player);
    final p = FakeSyncedController();
    await pumpEventQueue();
    late.attach(p);
    await pumpEventQueue();
    expect(p.playing, isTrue);
    expect(p.position, const Duration(minutes: 2, seconds: 15));
  });

  test('says to tap when the platform will not autoplay', () async {
    final host = watcher(coach, admin: true);
    final viewer = watcher(player);
    final p = FakeSyncedController()..blocked = true;
    await pumpEventQueue();
    await host.show.execute('v1');
    await pumpEventQueue();
    await host.play.execute();
    await pumpEventQueue();
    viewer.attach(p);
    await pumpEventQueue();
    for (var i = 0; i < 3; i++) {
      await viewer.tick();
    }
    expect(viewer.needsTap, isTrue);
    p.blocked = false;
    await viewer.tick();
    await viewer.tick();
    expect(viewer.needsTap, isFalse);
  });

  test('only admins drive; another admin can take over', () async {
    final host = watcher(coach, admin: true);
    final other = watcher(captain, admin: true);
    final viewer = watcher(player);
    await pumpEventQueue();

    await viewer.show.execute('v1');
    expect(viewer.show.error, isTrue);
    expect(meetings.playback, isEmpty);

    await host.show.execute('v1');
    await pumpEventQueue();
    expect(other.controlling, isFalse);
    expect(other.canControl, isTrue);
    await other.takeControl.execute();
    await pumpEventQueue();
    expect(other.controlling, isTrue);
    expect(host.controlling, isFalse);
    expect(viewer.playback?.presenterName, 'Cam');
  });

  test('uploads stream from Storage, and the call volume applies', () async {
    final vm = watcher(player);
    meetings.playback['m1'] = const MeetingPlayback(
      videoId: 'v2',
      playing: false,
      position: Duration.zero,
      presenterId: 'c',
      presenterName: 'Casey',
    );
    await pumpEventQueue();
    expect(vm.fileUrl, 'https://files.test/tryouts.mkv');
    final p = FakeSyncedController();
    vm.attach(p);
    vm.setVolume(0.4);
    expect(p.volume, 0.4);
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: child),
      ),
    );
    await tester.pump();
  }

  Widget fakePlayer(
    TeamVideo v,
    String? url,
    ValueChanged<SyncedVideoController?> onController,
  ) => Text('synced:${v.id}');

  testWidgets('the presenter gets controls; viewers see who presents', (
    tester,
  ) async {
    final host = watcher(coach, admin: true);
    await tester.runAsync(() async {
      await pumpEventQueue();
      await host.show.execute('v1');
      await pumpEventQueue();
    });
    await pump(
      tester,
      ListenableBuilder(
        listenable: host,
        builder: (_, _) =>
            WatchTogetherStage(viewModel: host, player: fakePlayer),
      ),
    );
    expect(find.text('synced:v1'), findsOneWidget);
    expect(find.text('You are presenting · Zone O'), findsOneWidget);
    expect(find.byTooltip('Play for everyone'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);

    final viewer = watcher(player);
    await tester.runAsync(pumpEventQueue);
    await pump(
      tester,
      ListenableBuilder(
        listenable: viewer,
        builder: (_, _) =>
            WatchTogetherStage(viewModel: viewer, player: fakePlayer),
      ),
    );
    expect(find.text('Casey is presenting · Zone O'), findsOneWidget);
    expect(find.byTooltip('Play for everyone'), findsNothing);
    expect(find.text('Take control'), findsNothing);
  });

  testWidgets('admins pick a team video by folder', (tester) async {
    final host = watcher(coach, admin: true);
    await tester.runAsync(pumpEventQueue);
    String? picked;
    await pump(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () async => picked = await showVideoPicker(context, host),
          child: const Text('pick'),
        ),
      ),
    );
    await tester.tap(find.text('pick'));
    await tester.pumpAndSettle();
    expect(find.text('Zone O'), findsOneWidget);
    expect(find.text('Tryouts'), findsOneWidget);
    await tester.tap(find.text('Game film'));
    await tester.pumpAndSettle();
    expect(find.text('Zone O'), findsNothing);
    expect(find.text('MKV · 1 MB'), findsOneWidget);
    await tester.tap(find.text('Tryouts'));
    await tester.pumpAndSettle();
    expect(picked, 'v2');
  });

  test('clockOf', () {
    expect(clockOf(const Duration(seconds: 65)), '1:05');
    expect(
      clockOf(const Duration(hours: 1, minutes: 2, seconds: 5)),
      '1:02:05',
    );
  });
}
