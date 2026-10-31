import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/services/file_picker_service.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/team_video.dart';
import 'package:frisbee_app/domain/models/video_folder.dart';
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
  late FakeFilePickerService picker;

  setUp(() {
    teams = FakeTeamRepository();
    teams.teams['t1'] = teamWith({
      'o': TeamRole.owner,
      'c': TeamRole.coach,
      'p1': TeamRole.player,
    });
    videos = FakeVideoRepository();
    picker = FakeFilePickerService();
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

  VideoEditorViewModel editor(
    AppUser user, {
    String? videoId,
    String? folderId,
  }) => VideoEditorViewModel(
    teamId: 't1',
    videoId: videoId,
    initialFolderId: folderId,
    videoRepository: videos,
    teamRepository: teams,
    authRepository: FakeAuthRepository(user: user),
    youTubeInfo: youtube,
    filePicker: picker,
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

  group('uploads', () {
    const mb = 1024 * 1024;
    PickedFile mp4(String name, int size) => PickedFile(
      name: name,
      size: size,
      read: () async => throw UnimplementedError(),
      path: 'C:/film/$name',
    );

    test('upload an MP4 with a title and see progress', () async {
      final vm = editor(coach);
      addTearDown(vm.dispose);
      await pumpEventQueue();
      vm.source = VideoSource.upload;
      picker.nextVideo = mp4('tryouts.mp4', 120 * mb);
      await vm.pickFile();
      expect(vm.fileProblem, isNull);
      final progress = <double?>[];
      vm.addListener(() => progress.add(vm.uploadProgress));
      await vm.save.execute(
        const TeamVideo(id: '', title: 'Tryouts', description: 'Day 1'),
      );
      expect(vm.save.completed, isTrue);
      expect(progress, containsAllInOrder([0, 0.5, 1, null]));
      final v = videos.videos['t1']!.single;
      expect(v.isYouTube, isFalse);
      expect(v.file!.size, 120 * mb);
      expect(v.title, 'Tryouts');
      expect(videos.uploaded, ['tryouts.mp4']);
    });

    test('MKV and other video files upload; other files are refused', () async {
      final vm = editor(coach);
      addTearDown(vm.dispose);
      await pumpEventQueue();
      vm.source = VideoSource.upload;
      picker.nextVideo = mp4('notes.pdf', mb);
      await vm.pickFile();
      expect(vm.fileProblem, contains("can't play that kind of file"));
      picker.nextVideo = mp4('Scrimmage.MKV', 300 * mb);
      await vm.pickFile();
      expect(vm.fileProblem, isNull);
      await vm.save.execute(const TeamVideo(id: '', title: 'Scrimmage'));
      final f = videos.videos['t1']!.single.file!;
      expect(f.contentType, 'video/x-matroska');
      expect(f.format, 'MKV');
      expect(VideoFile.baseName('Scrimmage.MKV'), 'Scrimmage');
    });

    test('files over 500 MB are refused', () async {
      final vm = editor(coach);
      addTearDown(vm.dispose);
      await pumpEventQueue();
      vm.source = VideoSource.upload;
      picker.nextVideo = mp4('full_game.mp4', 501 * mb);
      await vm.pickFile();
      expect(vm.fileProblem, contains('up to 500 MB'));
      await vm.save.execute(const TeamVideo(id: '', title: 'Game'));
      expect(vm.save.error, isTrue);
      expect(videos.uploaded, isEmpty);
    });

    test('the team stops at 5 GB of uploads', () async {
      videos.videos['t1'] = [
        for (var i = 0; i < 10; i++)
          TeamVideo(
            id: 'old$i',
            title: 'Old $i',
            file: VideoFile(path: 'p$i', name: 'old$i.mp4', size: 500 * mb),
          ),
      ];
      final vm = editor(coach);
      addTearDown(vm.dispose);
      await pumpEventQueue();
      expect(vm.usedBytes, 5000 * mb);
      vm.source = VideoSource.upload;
      picker.nextVideo = mp4('one_more.mp4', 200 * mb);
      await vm.pickFile();
      expect(vm.fileProblem, contains('Remove an uploaded video'));
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

  group('folders', () {
    TeamVideosViewModel list(AppUser user) => TeamVideosViewModel(
      teamId: 't1',
      videoRepository: videos,
      teamRepository: teams,
      authRepository: FakeAuthRepository(user: user),
    );

    test('filter by folder, move videos, and unsort on delete', () async {
      await seed();
      await videos.saveVideo(
        't1',
        const TeamVideo(id: '', youtubeId: 'abcdefghijk', title: 'Nationals'),
        coach,
      );
      final vm = list(coach);
      addTearDown(vm.dispose);
      await pumpEventQueue();
      await vm.saveFolder.execute(const VideoFolder(id: '', name: 'Game film'));
      await vm.saveFolder.execute(
        const VideoFolder(id: '', name: 'Film review'),
      );
      await pumpEventQueue();
      expect(vm.folders.map((f) => f.name), ['Film review', 'Game film']);
      final game = vm.folders.last;

      await vm.moveVideo.execute((videoId: 'v2', folderId: game.id));
      await pumpEventQueue();
      vm.filter = InFolder(game.id);
      expect(vm.visibleVideos.map((v) => v.title), ['Nationals']);
      expect(vm.countIn(const UnsortedVideos()), 1);
      expect(vm.folderOf(videos.videos['t1']![1])?.name, 'Game film');

      await vm.saveFolder.execute(VideoFolder(id: game.id, name: 'Games'));
      await pumpEventQueue();
      expect(vm.currentFolder?.name, 'Games');

      await vm.deleteFolder.execute(game.id);
      await pumpEventQueue();
      expect(vm.filter, isA<AllVideos>());
      expect(vm.folders.map((f) => f.name), ['Film review']);
      expect(vm.videos, hasLength(2));
      expect(vm.countIn(const UnsortedVideos()), 2);
    });

    test('players see folders but cannot change them', () async {
      videos.folders['t1'] = [const VideoFolder(id: 'f1', name: 'Highlights')];
      final vm = list(player);
      addTearDown(vm.dispose);
      await pumpEventQueue();
      expect(vm.folders.single.name, 'Highlights');
      expect(vm.canEdit, isFalse);
    });

    test('new videos start in the folder being viewed', () async {
      videos.folders['t1'] = [const VideoFolder(id: 'f1', name: 'Highlights')];
      final vm = editor(coach, folderId: 'f1');
      addTearDown(vm.dispose);
      await pumpEventQueue();
      expect(vm.initial.folderId, 'f1');
      await vm.save.execute(
        vm.initial.copyWith(youtubeId: film, title: 'Layout D'),
      );
      expect(videos.videos['t1']!.single.folderId, 'f1');

      final gone = editor(coach, folderId: 'deleted');
      addTearDown(gone.dispose);
      await pumpEventQueue();
      expect(gone.initial.folderId, '');
    });

    testWidgets('admins make a folder and file a video in it', (tester) async {
      await seed();
      final vm = list(coach);
      addTearDown(vm.dispose);
      await pump(tester, VideosTab(viewModel: vm), const Size(1280, 800));
      await tester.tap(find.text('New folder'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Film review');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();
      expect(find.text('Film review (0)'), findsOneWidget);
      expect(find.text('Nothing in Film review yet'), findsOneWidget);

      await tester.tap(find.text('All (1)'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Video options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move to folder'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Film review').last);
      await tester.pumpAndSettle();
      expect(find.text('Film review (1)'), findsOneWidget);
      expect(find.text('Film review · Casey · Nov 1, 2026'), findsOneWidget);

      await tester.tap(find.text('Film review (1)'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Folder options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete "Film review"'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Its video moves to Unsorted'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Delete folder'));
      await tester.pumpAndSettle();
      expect(find.text('All (1)'), findsOneWidget);
      expect(find.text('Zone offense film'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('players filter by folder with no admin controls', (
      tester,
    ) async {
      await seed();
      videos.folders['t1'] = [const VideoFolder(id: 'f1', name: 'Highlights')];
      final vm = list(player);
      addTearDown(vm.dispose);
      await pump(tester, VideosTab(viewModel: vm), const Size(390, 844));
      expect(find.text('Highlights (0)'), findsOneWidget);
      expect(find.text('Unsorted (1)'), findsOneWidget);
      expect(find.text('New folder'), findsNothing);
      await tester.tap(find.text('Highlights (0)'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Folder options'), findsNothing);
      expect(
        find.text('Videos your coaches file here will show up.'),
        findsOneWidget,
      );
    });
  });

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

  testWidgets('uploaded videos play from Storage', (tester) async {
    videos.videos['t1'] = [
      const TeamVideo(
        id: 'f1',
        title: 'Tryouts day 1',
        file: VideoFile(
          path: 'teams/t1/videos/f1/tryouts.mp4',
          name: 'tryouts.mp4',
          size: 120 * 1024 * 1024,
        ),
      ),
    ];
    final vm = VideoViewModel(
      teamId: 't1',
      videoId: 'f1',
      videoRepository: videos,
      teamRepository: teams,
      authRepository: FakeAuthRepository(user: player),
    );
    addTearDown(vm.dispose);
    await pump(
      tester,
      VideoScreen(
        viewModel: vm,
        player: fakePlayer,
        filePlayer: fakeFilePlayer,
      ),
      const Size(1280, 800),
    );
    expect(
      find.text('file player:https://files.test/tryouts.mp4'),
      findsOneWidget,
    );
    expect(find.text('Open on YouTube'), findsNothing);
    expect(find.textContaining('120 MB'), findsOneWidget);
  });

  testWidgets('admins see upload space and MP4 cards', (tester) async {
    videos.videos['t1'] = [
      const TeamVideo(
        id: 'f1',
        title: 'Tryouts day 1',
        file: VideoFile(
          path: 'p',
          name: 'tryouts.mp4',
          size: 1024 * 1024 * 1024,
        ),
      ),
    ];
    final vm = TeamVideosViewModel(
      teamId: 't1',
      videoRepository: videos,
      teamRepository: teams,
      authRepository: FakeAuthRepository(user: coach),
    );
    addTearDown(vm.dispose);
    await pump(tester, VideosTab(viewModel: vm), const Size(390, 844));
    expect(find.text('Uploads: 1.0 GB of 5.0 GB used'), findsOneWidget);
    expect(find.text('MP4 · 1.0 GB'), findsOneWidget);
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
