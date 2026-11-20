// TEMPORARY (redesign subtask 3g): phone screenshots of the playbook and
// video screens on fake data. Skipped unless asked for:
//   flutter test test/screenshots/play_test.dart \
//     --dart-define=SCREENSHOTS=<out dir> [--dart-define=SHOT_THEME=dark]
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/play.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/team_video.dart';
import 'package:frisbee_app/domain/models/video_folder.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/playbook/view_models/play_editor_viewmodel.dart';
import 'package:frisbee_app/ui/playbook/widgets/playbook_tab.dart';
import 'package:frisbee_app/ui/playbook/view_models/whiteboard_viewmodel.dart';
import 'package:frisbee_app/ui/playbook/widgets/whiteboard_screen.dart';
import 'package:frisbee_app/ui/teams/view_models/team_detail_viewmodel.dart';
import 'package:frisbee_app/ui/videos/view_models/team_videos_viewmodel.dart';
import 'package:frisbee_app/ui/videos/widgets/videos_tab.dart';
import 'package:frisbee_app/ui/playbook/widgets/play_editor_screen.dart';
import 'package:frisbee_app/ui/videos/view_models/video_editor_viewmodel.dart';
import 'package:frisbee_app/ui/videos/view_models/video_viewmodel.dart';
import 'package:frisbee_app/ui/videos/widgets/video_editor_screen.dart';
import 'package:frisbee_app/ui/videos/widgets/video_screen.dart';

import '../testing/fakes.dart';
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

PlayElement _o(String id, String label, double x, double y) => PlayElement(
  id: id,
  kind: ElementKind.offense,
  position: FieldPoint(x, y),
  label: label,
);

PlayElement _d(String id, double x, double y) =>
    PlayElement(id: id, kind: ElementKind.defense, position: FieldPoint(x, y));

final _vert = Play(
  id: 'p1',
  name: 'Vert stack: ho flow',
  notes:
      'Our go-to against person D. Run it off the pull when the wind is '
      'behind us.',
  updatedBy: 'coach',
  elements: [
    _o('h1', 'H1', 0.4, 0.78),
    _o('h2', 'H2', 0.62, 0.82),
    _o('c1', 'C1', 0.5, 0.62),
    _o('c2', 'C2', 0.5, 0.55),
    _o('c3', 'C3', 0.5, 0.48),
    _o('c4', 'C4', 0.5, 0.41),
    _o('c5', 'C5', 0.5, 0.34),
    _d('d1', 0.44, 0.75),
    _d('d2', 0.55, 0.6),
    _d('d3', 0.55, 0.45),
    const PlayElement(
      id: 'disc',
      kind: ElementKind.disc,
      position: FieldPoint(0.43, 0.76),
    ),
    const PlayElement(
      id: 'cone1',
      kind: ElementKind.cone,
      position: FieldPoint(0.1, 0.9),
    ),
  ],
  arrows: const [
    PlayArrow(
      id: 'a1',
      kind: ArrowKind.cut,
      points: [
        FieldPoint(0.5, 0.34),
        FieldPoint(0.62, 0.28),
        FieldPoint(0.75, 0.2),
      ],
    ),
    PlayArrow(
      id: 'a2',
      kind: ArrowKind.throw_,
      points: [
        FieldPoint(0.43, 0.76),
        FieldPoint(0.6, 0.5),
        FieldPoint(0.74, 0.22),
      ],
    ),
  ],
  steps: const [
    PlayStep(
      id: 's1',
      note: 'H1 swings to break side.',
      paths: {
        'h2': [FieldPoint(0.75, 0.8)],
      },
    ),
    PlayStep(
      id: 's2',
      note:
          'C5 starts deep, plants and breaks to the open side once the '
          'mark shifts.',
      paths: {
        'c5': [FieldPoint(0.62, 0.28), FieldPoint(0.75, 0.2)],
      },
    ),
    PlayStep(id: 's3', note: 'Reset to H2 if the huck isn\'t on.'),
  ],
);

final _plays = [
  _vert,
  Play(
    id: 'p2',
    name: 'Ho stack: under',
    elements: [
      _o('a', '1', 0.2, 0.7),
      _o('b', '2', 0.5, 0.72),
      _o('c', '3', 0.8, 0.7),
      _o('d', '4', 0.15, 0.45),
      _o('e', '5', 0.85, 0.45),
    ],
  ),
  Play(
    id: 'p3',
    name: '3-person cup',
    category: PlayCategory.defense,
    elements: [
      _d('a', 0.45, 0.6),
      _d('b', 0.55, 0.58),
      _d('c', 0.5, 0.5),
      _o('h', 'H', 0.5, 0.65),
    ],
  ),
  Play(
    id: 'p4',
    name: 'Force flick, person',
    category: PlayCategory.defense,
    steps: const [
      PlayStep(id: 's'),
      PlayStep(id: 't'),
    ],
    elements: [_o('a', '1', 0.5, 0.6), _d('b', 0.45, 0.58)],
  ),
  Play(
    id: 'p5',
    name: 'Pull plays: left',
    category: PlayCategory.pull,
    elements: [_o('a', '1', 0.3, 0.2), _o('b', '2', 0.7, 0.2)],
  ),
];

Widget _fakeYouTube(String id) => const AspectRatio(
  aspectRatio: 16 / 9,
  child: ColoredBox(
    color: Colors.black,
    child: Center(
      child: Icon(Icons.play_circle_fill, color: Colors.white, size: 56),
    ),
  ),
);

void main() {
  final skip = _out.isEmpty ? 'pass --dart-define=SCREENSHOTS=<dir>' : null;

  final shot = GlobalKey();
  final me = testUser.uid;
  late FakeTeamRepository teams;
  late FakeVideoRepository videos;
  late FakePlayRepository plays;
  late FakeAuthRepository auth;

  void seed({required bool owner}) {
    auth = FakeAuthRepository(user: testUser);
    teams = FakeTeamRepository();
    teams.teams['t1'] = Team(
      id: 't1',
      name: 'Northside Flyers',
      division: Division.mixed,
      level: CompetitionLevel.club,
      city: 'Denver',
      ownerId: owner ? me : 'coach',
      members: {
        me: owner ? TeamRole.owner : TeamRole.player,
        'coach': owner ? TeamRole.coach : TeamRole.owner,
        'jo': TeamRole.player,
      },
      memberNames: {me: 'Test User', 'coach': 'Riley Chen', 'jo': 'Jo Park'},
    );
    plays = FakePlayRepository();
    for (final p in _plays) {
      plays.plays[p.id] = p;
    }
    plays.plays['w1'] = const Play(
      id: 'w1',
      name: 'Zone talk',
      kind: PlayKind.whiteboard,
      elements: [
        PlayElement(
          id: 'o1',
          kind: ElementKind.offense,
          position: FieldPoint(0.4, 0.4),
          label: '1',
        ),
      ],
      drawings: [
        PlayDrawing(
          id: 'k1',
          color: DrawingColor.amber,
          points: [
            FieldPoint(0.2, 0.3),
            FieldPoint(0.5, 0.5),
            FieldPoint(0.7, 0.4),
          ],
        ),
      ],
    );
    videos = FakeVideoRepository();
    videos.folders['t1'] = const [
      VideoFolder(id: 'f1', name: 'Mile High Open'),
      VideoFolder(id: 'f2', name: 'Practice film'),
      VideoFolder(id: 'f3', name: 'Highlights'),
    ];
    videos.videos['t1'] = [
      TeamVideo(
        id: 'v1',
        youtubeId: 'dQw4w9WgXcQ',
        folderId: 'f1',
        title: 'Pool A vs Boulder Gold',
        description: 'Full game, end zone camera. Second half starts at 24:30.',
        authorId: 'coach',
        authorName: 'Riley Chen',
        createdAt: DateTime(2026, 11, 15),
      ),
      TeamVideo(
        id: 'v2',
        folderId: 'f1',
        title: 'Quarterfinal vs Mesa Mayhem',
        file: const VideoFile(
          path: 'teams/t1/videos/v2/qf.mp4',
          name: 'qf.mp4',
          size: 1200 * 1024 * 1024,
        ),
        authorId: 'jo',
        authorName: 'Jo Park',
        createdAt: DateTime(2026, 11, 16),
      ),
      TeamVideo(
        id: 'v3',
        youtubeId: 'abcdefghijk',
        title: 'Saturday highlights',
        authorId: 'coach',
        authorName: 'Riley Chen',
        createdAt: DateTime(2026, 11, 14),
      ),
    ];
  }

  /// One screen at phone size. (Not through the router, which pulls in
  /// every area's pages; [tab] screens get an app bar like the team's.)
  Future<void> pumpScreen(
    WidgetTester tester,
    Widget screen, {
    String? tab,
  }) async {
    await tester.runAsync(_loadFonts);
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepaintBoundary(
        key: shot,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _dark ? AppTheme.dark : AppTheme.light,
          home: tab == null
              ? screen
              : Scaffold(
                  appBar: AppBar(title: Text('Northside Flyers · $tab')),
                  body: screen,
                ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

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

  TeamDetailViewModel team() => TeamDetailViewModel(
    teamId: 't1',
    teamRepository: teams,
    playRepository: plays,
    eventRepository: FakeEventRepository(),
    authRepository: auth,
  );

  PlayEditorViewModel play() => PlayEditorViewModel(
    teamId: 't1',
    playId: 'p1',
    playRepository: plays,
    teamRepository: teams,
    authRepository: auth,
  );

  for (final owner in [true, false]) {
    final who = owner ? 'owner' : 'player';
    testWidgets('playbook ($who)', skip: skip != null, (tester) async {
      seed(owner: owner);
      final vm = team();
      addTearDown(vm.dispose);
      await pumpScreen(tester, PlaybookTab(viewModel: vm), tab: 'Playbook');
      await capture(tester, '01-playbook-$who');
      await tester.tap(find.text('Whiteboard'));
      await capture(tester, '01b-playbook-whiteboard-$who');

      final p = play();
      addTearDown(p.dispose);
      await pumpScreen(tester, PlayEditorScreen(viewModel: p));
      await capture(tester, '02-play-$who-setup');
      p.selectStep(2);
      await capture(tester, '02b-play-$who-step2');
    });

    testWidgets('videos ($who)', skip: skip != null, (tester) async {
      seed(owner: owner);
      final vm = TeamVideosViewModel(
        teamId: 't1',
        videoRepository: videos,
        teamRepository: teams,
        authRepository: auth,
      );
      addTearDown(vm.dispose);
      await pumpScreen(tester, VideosTab(viewModel: vm), tab: 'Videos');
      await capture(tester, '04-videos-$who');
      await tester.tap(find.text('Mile High Open (2)'));
      await capture(tester, '04b-videos-folder-$who');
    });
  }

  testWidgets('whiteboard', skip: skip != null, (tester) async {
    seed(owner: true);
    final wb = WhiteboardViewModel(
      teamId: 't1',
      playId: null,
      playRepository: plays,
      teamRepository: teams,
      authRepository: auth,
    );
    addTearDown(wb.dispose);
    await pumpScreen(tester, WhiteboardScreen(viewModel: wb));
    for (final (i, c) in DrawingColor.values.indexed) {
      wb
        ..setColor(c)
        ..addStroke([
          for (var k = 0; k <= 20; k++)
            FieldPoint(
              0.15 + 0.2 * i + 0.05 * (k.isEven ? 1 : 0),
              0.3 + k / 40,
            ),
        ]);
    }
    wb
      ..setTool(WhiteboardTool.offense)
      ..placeAt(const FieldPoint(0.3, 0.25))
      ..setTool(WhiteboardTool.defense)
      ..placeAt(const FieldPoint(0.35, 0.28))
      ..setTool(WhiteboardTool.cone)
      ..placeAt(const FieldPoint(0.8, 0.2))
      ..setColor(DrawingColor.turf);
    await capture(tester, '05-whiteboard');
  });

  testWidgets('play editor tools', skip: skip != null, (tester) async {
    seed(owner: true);
    final p = play();
    addTearDown(p.dispose);
    await pumpScreen(tester, PlayEditorScreen(viewModel: p));
    p.setTool(EditorTool.cut);
    p.select('c5');
    await capture(tester, '03-play-editor-tools');
    p.addStep();
    await capture(tester, '03b-play-editor-new-step');

    // A play with no steps, opened over a page so it has a back button.
    final still = PlayEditorViewModel(
      teamId: 't1',
      playId: 'p2',
      playRepository: plays,
      teamRepository: teams,
      authRepository: auth,
    );
    addTearDown(still.dispose);
    await pumpScreen(tester, const Scaffold());
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .push(
          MaterialPageRoute<void>(
            builder: (_) => PlayEditorScreen(viewModel: still),
          ),
        );
    await capture(tester, '03c-play-editor-no-steps');
  });

  testWidgets('video page and editor', skip: skip != null, (tester) async {
    seed(owner: true);
    final vm = VideoViewModel(
      teamId: 't1',
      videoId: 'v1',
      videoRepository: videos,
      teamRepository: teams,
      authRepository: auth,
    );
    addTearDown(vm.dispose);
    await pumpScreen(tester, VideoScreen(viewModel: vm, player: _fakeYouTube));
    await capture(tester, '05-video');

    final editor = VideoEditorViewModel(
      teamId: 't1',
      videoId: null,
      initialFolderId: 'f1',
      videoRepository: videos,
      teamRepository: teams,
      authRepository: auth,
      youTubeInfo: FakeYouTubeInfoService({
        'k3Fq9xLm2Wd': (
          title: 'Pool A vs Boulder Gold',
          channel: 'Front Range Ultimate',
        ),
      }),
      filePicker: FakeFilePickerService(),
    );
    addTearDown(editor.dispose);
    await pumpScreen(tester, VideoEditorScreen(viewModel: editor));
    await capture(tester, '06-video-editor-empty');
    await tester.enterText(
      find.byType(TextField).first,
      'https://youtu.be/k3Fq9xLm2Wd',
    );
    await tester.pump(const Duration(milliseconds: 500));
    await capture(tester, '06b-video-editor');
    await tester.enterText(find.byType(TextField).first, 'not a link');
    await tester.pump(const Duration(milliseconds: 500));
    await capture(tester, '06d-video-editor-invalid');
    await tester.tap(find.text('Upload file'));
    await capture(tester, '06c-video-editor-upload');
  });
}
