// Notes, clips and comments on a team video, and tagging it to an event
// (redesign F4, F5, F6).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/team_event.dart';
import 'package:frisbee_app/domain/models/team_video.dart';
import 'package:frisbee_app/domain/models/video_comment.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/schedule/view_models/event_detail_viewmodel.dart';
import 'package:frisbee_app/ui/videos/view_models/video_viewmodel.dart';
import 'package:frisbee_app/ui/videos/widgets/video_screen.dart';

import '../testing/fakes.dart';
import '../testing/video_fakes.dart';

const coach = AppUser(uid: 'c', displayName: 'Casey');
const player = AppUser(uid: 'p1', displayName: 'Pat');
const other = AppUser(uid: 'p2', displayName: 'Sam');
const film = 'dQw4w9WgXcQ';

void main() {
  late FakeTeamRepository teams;
  late FakeVideoRepository videos;
  late FakeEventRepository events;

  setUp(() {
    teams = FakeTeamRepository();
    teams.teams['t1'] = teamWith({
      'o': TeamRole.owner,
      'c': TeamRole.coach,
      'p1': TeamRole.player,
      'p2': TeamRole.player,
    });
    videos = FakeVideoRepository()
      ..uid = player.uid
      ..name = 'Pat';
    videos.videos['t1'] = [
      TeamVideo(
        id: 'v1',
        youtubeId: film,
        title: 'Regionals film',
        authorId: coach.uid,
        createdAt: DateTime(2026, 11, 1),
      ),
    ];
    events = FakeEventRepository();
    events.events['e1'] = TeamEvent(
      id: 'e1',
      title: 'Regionals',
      type: EventType.tournament,
      startsAt: DateTime.now().subtract(const Duration(days: 3)),
    );
    FakeVideoController.last = null;
  });

  VideoViewModel page(AppUser user) {
    final vm = VideoViewModel(
      teamId: 't1',
      videoId: 'v1',
      videoRepository: videos,
      teamRepository: teams,
      authRepository: FakeAuthRepository(user: user),
      eventRepository: events,
    );
    addTearDown(vm.dispose);
    return vm;
  }

  VideoComment note(String id, String author, int at, {int? end}) =>
      VideoComment(
        id: id,
        authorId: author,
        authorName: author,
        body: 'note $id',
        atMs: at,
        endMs: end,
        createdAt: DateTime(2026, 11, 2),
      );

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(430, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: child));
    await tester.pumpAndSettle();
  }

  group('view model', () {
    test('lists notes by time and comments oldest first', () async {
      videos.comments['t1/v1'] = [
        note('n2', 'p2', 90000),
        VideoComment(
          id: 'm2',
          authorId: 'p2',
          body: 'later',
          createdAt: DateTime(2026, 11, 3),
        ),
        note('n1', 'p1', 5000, end: 9000),
        VideoComment(
          id: 'm1',
          authorId: 'c',
          body: 'first',
          createdAt: DateTime(2026, 11, 1),
        ),
      ];
      final vm = page(player);
      await pumpEventQueue();
      expect(vm.notes.map((c) => c.id), ['n1', 'n2']);
      expect(vm.comments.map((c) => c.id), ['m1', 'm2']);
      expect(vm.notes.first.timeLabel, '0:05–0:09');
      expect(vm.notes.first.isClip, isTrue);
    });

    test('members comment; authors and admins delete', () async {
      videos.comments['t1/v1'] = [note('mine', 'p1', 0), note('sam', 'p2', 0)];
      final pat = page(player);
      final casey = page(coach);
      await pumpEventQueue();
      expect(pat.canComment, isTrue);
      expect(
        pat.canDelete(pat.notes.firstWhere((c) => c.id == 'mine')),
        isTrue,
      );
      expect(
        pat.canDelete(pat.notes.firstWhere((c) => c.id == 'sam')),
        isFalse,
      );
      expect(
        casey.canDelete(casey.notes.firstWhere((c) => c.id == 'sam')),
        isTrue,
      );
      expect(pat.canTag, isFalse);
      expect(casey.canTag, isTrue);
    });

    test('nothing to write without the API', () async {
      videos.extras = false;
      videos.comments['t1/v1'] = [note('mine', 'p1', 0)];
      final vm = page(player);
      final casey = page(coach);
      await pumpEventQueue();
      expect(vm.notes, hasLength(1));
      expect(vm.canComment, isFalse);
      expect(vm.canDelete(vm.notes.single), isFalse);
      expect(casey.canTag, isFalse);
    });

    test(
      'marks a clip at the player\'s times, then plays notes from theirs',
      () async {
        final vm = page(player);
        await pumpEventQueue();
        final player0 = FakeVideoController();
        vm.attachPlayer(player0);
        await pumpEventQueue();
        expect(vm.canSeek, isTrue);

        player0.position = const Duration(seconds: 83);
        await vm.markStart();
        // An end before the start is ignored.
        player0.position = const Duration(seconds: 80);
        await vm.markEnd();
        expect(vm.noteEndMs, isNull);
        player0.position = const Duration(seconds: 100);
        await vm.markEnd();
        expect((vm.noteStartMs, vm.noteEndMs), (83000, 100000));

        await vm.addNote('Watch the mark');
        await pumpEventQueue();
        final saved = videos.comments['t1/v1']!.single;
        expect(
          (saved.atMs, saved.endMs, saved.body),
          (83000, 100000, 'Watch the mark'),
        );
        expect(vm.noteStartMs, isNull);
        expect(vm.notes.single.id, saved.id);

        await vm.seekTo(vm.notes.single);
        expect(player0.seeks, [const Duration(seconds: 83)]);
        expect(player0.playing, isTrue);
      },
    );

    test('a note with nothing marked is pinned where the player is', () async {
      final vm = page(player);
      final p = FakeVideoController()..position = const Duration(seconds: 7);
      vm.attachPlayer(p);
      await vm.addNote('Here');
      expect(videos.comments['t1/v1']!.single.atMs, 7000);
      expect(videos.comments['t1/v1']!.single.endMs, isNull);
    });

    test("a player that hasn't loaded yet pins notes at the start", () async {
      final vm = page(player);
      vm.attachPlayer(FakeVideoController()..ready = false);
      expect(await vm.addNote('Pull'), isTrue);
      expect(videos.comments['t1/v1']!.single.atMs, 0);
      // No player at all: nothing to pin to.
      vm.attachPlayer(null);
      expect(await vm.addNote('Lost'), isFalse);
      expect(videos.comments['t1/v1'], hasLength(1));
    });

    test('admins tag an event; the page reads it, and untag', () async {
      final vm = page(coach);
      await pumpEventQueue();
      expect(vm.taggableEvents.map((e) => e.id), ['e1']);
      await vm.tagEvent.execute('e1');
      await pumpEventQueue();
      expect(videos.tagged.single, ('v1', 'e1'));
      expect(vm.taggedEvent?.title, 'Regionals');
      await vm.tagEvent.execute(null);
      await pumpEventQueue();
      expect(vm.taggedEvent, isNull);
      expect(vm.taggedMissing, isFalse);
    });

    test('a tag to a deleted event says so', () async {
      await videos.tagEvent('t1', 'v1', 'gone');
      final vm = page(player);
      await pumpEventQueue();
      expect(vm.taggedMissing, isTrue);
    });

    test("the event page lists the videos tagged to it", () async {
      await videos.tagEvent('t1', 'v1', 'e1');
      final vm = EventDetailViewModel(
        teamId: 't1',
        eventId: 'e1',
        eventRepository: events,
        teamRepository: teams,
        authRepository: FakeAuthRepository(user: player),
        videoRepository: videos,
      );
      addTearDown(vm.dispose);
      await pumpEventQueue();
      expect(vm.videos.map((v) => v.title), ['Regionals film']);
    });
  });

  group('video page', () {
    testWidgets(
      'tapping a note plays from there; members add notes and comments',
      (tester) async {
        videos.comments['t1/v1'] = [note('n1', 'p2', 83000)];
        final vm = page(player);
        await pump(tester, VideoScreen(viewModel: vm, player: fakePlayer));
        expect(find.text('Notes · 1'), findsOneWidget);
        expect(find.text('1:23'), findsOneWidget);
        // Sam's note isn't Pat's to delete.
        expect(find.byTooltip('Delete'), findsNothing);

        await tester.tap(find.text('note n1'));
        await tester.pumpAndSettle();
        expect(FakeVideoController.last!.seeks, [const Duration(seconds: 83)]);

        FakeVideoController.last!.position = const Duration(seconds: 10);
        await tester.tap(find.text('Mark start'));
        await tester.pumpAndSettle();
        expect(find.text('At 0:10'), findsOneWidget);
        await tester.enterText(find.byType(TextField).first, 'Cut under');
        await tester.tap(find.byTooltip('Post').first);
        await tester.pumpAndSettle();
        expect(find.text('Notes · 2'), findsOneWidget);
        expect(find.text('0:10'), findsOneWidget);

        await tester.enterText(find.byType(TextField).last, 'Great game');
        await tester.tap(find.byTooltip('Post').last);
        await tester.pumpAndSettle();
        expect(find.text('Comments · 1'), findsOneWidget);
        expect(find.text('Great game'), findsOneWidget);

        // Their own comment and note: Delete.
        expect(find.byTooltip('Delete'), findsNWidgets(2));
        await tester.tap(find.byTooltip('Delete').last);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
        await tester.pumpAndSettle();
        expect(find.text('Great game'), findsNothing);
      },
    );

    testWidgets('admins tag a game; everyone sees it', (tester) async {
      final vm = page(coach);
      await pump(tester, VideoScreen(viewModel: vm, player: fakePlayer));
      await tester.tap(find.text('Tag a game or event'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Regionals'));
      await tester.pumpAndSettle();
      expect(videos.tagged.single, ('v1', 'e1'));
      expect(find.text('Regionals'), findsOneWidget);
      expect(find.byTooltip('Remove tag'), findsOneWidget);
    });

    testWidgets('players see the tag but not the tagging', (tester) async {
      await videos.tagEvent('t1', 'v1', 'e1');
      final vm = page(player);
      await pump(tester, VideoScreen(viewModel: vm, player: fakePlayer));
      expect(find.text('Regionals'), findsOneWidget);
      expect(find.byTooltip('Remove tag'), findsNothing);
      expect(find.text('Tag a game or event'), findsNothing);
    });

    testWidgets('without the API, notes read but no composers', (tester) async {
      videos.extras = false;
      final vm = page(player);
      await pump(tester, VideoScreen(viewModel: vm, player: fakePlayer));
      expect(find.text('Notes'), findsNothing);
      expect(find.text('Comments'), findsNothing);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('a failed comment says why and keeps the text', (tester) async {
      final vm = page(player);
      await pump(tester, VideoScreen(viewModel: vm, player: fakePlayer));
      videos.failWith = Exception('Slow down');
      await tester.enterText(find.byType(TextField).last, 'Hello');
      await tester.tap(find.byTooltip('Post').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('Slow down'), findsOneWidget);
      expect(find.text('Hello'), findsOneWidget);
    });
  });
}
