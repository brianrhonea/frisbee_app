import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/team_video.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/videos/view_models/team_videos_viewmodel.dart';
import 'package:frisbee_app/ui/videos/view_models/video_editor_viewmodel.dart';
import 'package:frisbee_app/ui/videos/view_models/video_viewmodel.dart';
import 'package:frisbee_app/ui/videos/widgets/video_editor_screen.dart';
import 'package:frisbee_app/ui/videos/widgets/video_screen.dart';
import 'package:frisbee_app/ui/videos/widgets/videos_tab.dart';
import 'package:go_router/go_router.dart';

import '../testing/fakes.dart';
import '../testing/video_fakes.dart';

const coach = AppUser(uid: 'c', displayName: 'Casey');
const player = AppUser(uid: 'p1', displayName: 'Pat');
const film = 'dQw4w9WgXcQ';

void main() {
  late FakeTeamRepository teams;
  late FakeVideoRepository videos;
  late FakeYouTubeInfoService youtube;

  setUp(() {
    teams = FakeTeamRepository();
    teams.teams['t1'] = teamWith({
      'o': TeamRole.owner,
      'c': TeamRole.coach,
      'p1': TeamRole.player,
    });
    videos = FakeVideoRepository();
    youtube = FakeYouTubeInfoService({
      film: (title: 'Zone offense film', channel: 'Northside Flyers'),
    });
  });

  Future<void> seed() => videos.saveVideo(
    't1',
    const TeamVideo(
      id: '',
      youtubeId: film,
      title: 'Zone offense film',
      description: 'Watch before Thursday.',
    ),
    coach,
  );

  VideoEditorViewModel editor(AppUser user, {String? videoId}) =>
      VideoEditorViewModel(
        teamId: 't1',
        videoId: videoId,
        videoRepository: videos,
        teamRepository: teams,
        authRepository: FakeAuthRepository(user: user),
        youTubeInfo: youtube,
      );

  group('VideoEditorViewModel', () {
    test('only admins can post', () async {
      final vm = editor(player);
      addTearDown(vm.dispose);
      await pumpEventQueue();
      expect(vm.load.error, isTrue);
      await vm.save.execute(
        const TeamVideo(id: '', youtubeId: film, title: 'x'),
      );
      expect(vm.save.error, isTrue);
      expect(videos.videos['t1'], isNull);
    });

    test('checks pasted links with YouTube', () async {
      final vm = editor(coach);
      addTearDown(vm.dispose);
      await pumpEventQueue();
      expect(vm.linkCheck, LinkCheck.empty);

      await vm.checkLink('https://vimeo.com/1');
      expect(vm.linkCheck, LinkCheck.invalid);
      expect(vm.youtubeId, isNull);

      await vm.checkLink('https://youtu.be/$film?si=x');
      expect(vm.linkCheck, LinkCheck.embeddable);
      expect(vm.youtubeId, film);
      expect(vm.youTubeTitle, 'Zone offense film');
      expect(vm.channel, 'Northside Flyers');

      // The same video again isn't looked up twice.
      await vm.checkLink('https://www.youtube.com/watch?v=$film');
      expect(youtube.lookedUp, [film]);

      await vm.checkLink('https://youtu.be/privateVid1');
      expect(vm.linkCheck, LinkCheck.notEmbeddable);

      youtube.offline = true;
      await vm.checkLink('https://youtu.be/offlineVid1');
      expect(vm.linkCheck, LinkCheck.unknown);
    });

    test("uses YouTube's title when none is typed", () async {
      final vm = editor(coach);
      addTearDown(vm.dispose);
      await pumpEventQueue();
      await vm.checkLink(film);
      await vm.save.execute(const TeamVideo(id: '', youtubeId: film));
      final v = videos.videos['t1']!.single;
      expect(v.title, 'Zone offense film');
      expect(v.authorName, 'Casey');
    });

    test('needs a title and a real video id', () async {
      final vm = editor(coach);
      addTearDown(vm.dispose);
      await pumpEventQueue();
      await vm.save.execute(const TeamVideo(id: '', youtubeId: 'nope'));
      expect(vm.save.error, isTrue);
      // An id YouTube didn't recognise, and no title typed.
      await vm.save.execute(const TeamVideo(id: '', youtubeId: 'abcdefghijk'));
      expect(vm.save.error, isTrue);
      expect(videos.videos['t1'], isNull);
    });

    test('editing starts from the saved video', () async {
      await seed();
      final vm = editor(coach, videoId: 'v1');
      addTearDown(vm.dispose);
      await pumpEventQueue();
      expect(vm.initial.title, 'Zone offense film');
      expect(vm.linkCheck, LinkCheck.embeddable);
      await vm.save.execute(vm.initial.copyWith(title: 'Week 2 film'));
      expect(videos.videos['t1']!.single.title, 'Week 2 film');
      expect(videos.videos['t1']!.single.authorName, 'Casey');
    });
  });

  test('TeamVideosViewModel: everyone watches, admins remove', () async {
    await seed();
    final watcher = TeamVideosViewModel(
      teamId: 't1',
      videoRepository: videos,
      teamRepository: teams,
      authRepository: FakeAuthRepository(user: player),
    );
    final admin = TeamVideosViewModel(
      teamId: 't1',
      videoRepository: videos,
      teamRepository: teams,
      authRepository: FakeAuthRepository(user: coach),
    );
    addTearDown(watcher.dispose);
    addTearDown(admin.dispose);
    await pumpEventQueue();
    expect(watcher.videos.single.title, 'Zone offense film');
    expect(watcher.canEdit, isFalse);
    expect(admin.canEdit, isTrue);
    await admin.deleteVideo.execute('v1');
    await pumpEventQueue();
    expect(watcher.videos, isEmpty);
  });

  Future<void> pump(WidgetTester tester, Widget child, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: child));
    await tester.pumpAndSettle();
  }

  for (final size in const [Size(390, 844), Size(1280, 800)]) {
    testWidgets('Videos tab lists videos; only admins add at $size', (
      tester,
    ) async {
      final vm = TeamVideosViewModel(
        teamId: 't1',
        videoRepository: videos,
        teamRepository: teams,
        authRepository: FakeAuthRepository(user: player),
      );
      addTearDown(vm.dispose);
      await pump(tester, VideosTab(viewModel: vm), size);
      expect(find.text('No videos yet'), findsOneWidget);
      expect(find.text('Add video'), findsNothing);

      await seed();
      await tester.pumpAndSettle();
      expect(find.text('Zone offense film'), findsOneWidget);
      expect(find.text('Casey · Nov 1, 2026'), findsOneWidget);
      expect(find.byTooltip('Video options'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('admins see Add video and video options', (tester) async {
    await seed();
    final vm = TeamVideosViewModel(
      teamId: 't1',
      videoRepository: videos,
      teamRepository: teams,
      authRepository: FakeAuthRepository(user: coach),
    );
    addTearDown(vm.dispose);
    await pump(tester, VideosTab(viewModel: vm), const Size(390, 844));
    expect(find.text('Add video'), findsOneWidget);
    await tester.tap(find.byTooltip('Video options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(videos.videos['t1'], isEmpty);
  });

  testWidgets('video page plays the video and shows its description', (
    tester,
  ) async {
    await seed();
    final vm = VideoViewModel(
      teamId: 't1',
      videoId: 'v1',
      videoRepository: videos,
      teamRepository: teams,
      authRepository: FakeAuthRepository(user: player),
    );
    addTearDown(vm.dispose);
    await pump(
      tester,
      VideoScreen(viewModel: vm, player: fakePlayer),
      const Size(1280, 800),
    );
    expect(find.text('player:$film'), findsOneWidget);
    expect(find.text('Zone offense film'), findsOneWidget);
    expect(find.text('Watch before Thursday.'), findsOneWidget);
    expect(find.text('Open on YouTube'), findsOneWidget);
    expect(find.byTooltip('Edit'), findsNothing);
  });

  testWidgets('pasting a link fills the title, then saving opens the video', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final vm = editor(coach);
    final router = GoRouter(
      initialLocation: '/new',
      routes: [
        GoRoute(
          path: '/new',
          builder: (_, _) => VideoEditorScreen(viewModel: vm),
        ),
        GoRoute(
          path: '/team-videos/:teamId/:videoId',
          builder: (_, state) =>
              Text('video ${state.pathParameters['videoId']}'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );

    await tester.enterText(
      find.byType(TextField).first,
      'https://youtu.be/$film',
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ready to play in the app'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
      'Zone offense film',
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Add video'));
    await tester.pumpAndSettle();
    expect(find.text('video v1'), findsOneWidget);
    expect(videos.videos['t1']!.single.youtubeId, film);
  });

  testWidgets('warns when YouTube will not play a video here', (tester) async {
    final vm = editor(coach);
    addTearDown(vm.dispose);
    await pump(tester, VideoEditorScreen(viewModel: vm), const Size(390, 900));
    await tester.enterText(
      find.byType(TextField).first,
      'https://youtu.be/privateVid1',
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.textContaining('"Allow embedding" is on'), findsOneWidget);
  });
}
