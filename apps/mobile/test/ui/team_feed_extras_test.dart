// Team feed extras (redesign F24): pinned posts first, comment counts and
// threads, and the "Post to the team" box.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/team_post.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/teams/view_models/team_home_viewmodel.dart';
import 'package:frisbee_app/ui/teams/widgets/team_home_screen.dart';
import 'package:frisbee_app/utils/result.dart';

import '../testing/fakes.dart';

void main() {
  late FakeTeamRepository teams;
  late FakeTeamPostRepository posts;
  final now = DateTime(2026, 11, 20, 12);

  TeamPost post(
    String id,
    String body, {
    int hoursAgo = 1,
    DateTime? pinnedAt,
    int comments = 0,
    bool isPublic = false,
  }) => TeamPost(
    id: id,
    body: body,
    isPublic: isPublic,
    createdAt: now.subtract(Duration(hours: hoursAgo)),
    pinnedAt: pinnedAt,
    commentCount: comments,
  );

  setUp(() {
    teams = FakeTeamRepository();
    posts = FakeTeamPostRepository()
      ..posts['t1'] = [
        post('new', 'Newest news'),
        post('old', 'Old rules', hoursAgo: 90, pinnedAt: now, comments: 2),
        post('mid', 'Field moved', hoursAgo: 5, comments: 1),
      ];
  });

  void addTeam(Map<String, TeamRole> members) {
    final team = teamWith(members);
    teams.teams[team.id] = team;
    teams.listings[team.id] = TeamListing.of(team);
  }

  TeamHomeViewModel homeVm() => TeamHomeViewModel(
    teamId: 't1',
    teamRepository: teams,
    eventRepository: FakeEventRepository(),
    teamPostRepository: posts,
    authRepository: FakeAuthRepository(user: testUser),
    filePicker: FakeFilePickerService(),
    clock: () => now,
  );

  group('arrangeTeamFeed', () {
    test('pinned first, newest pin first, each post once, capped', () {
      final pinned = [
        for (var i = 0; i < 4; i++)
          post(
            'p$i',
            'x',
            hoursAgo: i,
            pinnedAt: now.add(Duration(hours: i)),
          ),
      ];
      final f = arrangeTeamFeed(pinned, [
        post(
          'p3',
          'x',
          hoursAgo: 3,
          pinnedAt: now.add(const Duration(hours: 3)),
        ),
        post('p2', 'unpinned since', hoursAgo: 2),
        post('plain', 'y', hoursAgo: 10),
      ]);
      expect(f.pinned.map((p) => p.id), ['p3', 'p1', 'p0']);
      expect(f.rest.map((p) => p.id), ['p2', 'plain']);
    });

    test('labels comment counts', () {
      expect(teamPostCommentLabel(0), 'Comment');
      expect(teamPostCommentLabel(1), '1 comment');
      expect(teamPostCommentLabel(7), '7 comments');
      expect(TeamPost.fromMap('a', const {'commentCount': -1}).commentCount, 0);
      expect(TeamPost.fromMap('a', const {}).commentCount, 0);
      expect(TeamPost.fromMap('a', const {}).isPinned, isFalse);
    });
  });

  group('TeamHomeViewModel', () {
    test('lists pinned posts first, then the newest', () async {
      addTeam({testUser.uid: TeamRole.player, 'owner': TeamRole.owner});
      final vm = homeVm();
      await pumpEventQueue();
      expect(vm.pinnedPosts.map((p) => p.id), ['old']);
      expect(vm.posts.map((p) => p.id), ['old', 'new', 'mid']);
      expect(vm.canPin, isFalse);
      expect(vm.canComment, isTrue);
      vm.dispose();
    });

    test('admins pin and unpin; a full feed swaps one out', () async {
      addTeam({testUser.uid: TeamRole.coach, 'owner': TeamRole.owner});
      final vm = homeVm();
      await pumpEventQueue();
      expect(vm.canPin, isTrue);
      await vm.pinPost.execute((postId: 'new', unpin: null));
      await vm.pinPost.execute((postId: 'mid', unpin: null));
      await pumpEventQueue();
      expect(vm.pinnedPosts.map((p) => p.id).toSet(), {'old', 'new', 'mid'});
      posts.posts['t1']!.add(post('fourth', 'Fourth'));
      await vm.pinPost.execute((postId: 'fourth', unpin: null));
      expect(vm.pinPost.result, isA<Error<void>>());
      await vm.pinPost.execute((postId: 'fourth', unpin: 'old'));
      await vm.unpinPost.execute('new');
      await pumpEventQueue();
      expect(vm.pinnedPosts.map((p) => p.id).toSet(), {'fourth', 'mid'});
      expect(posts.pinCalls.last, 'unpin new');
      vm.dispose();
    });

    test('without the API there are no pins or comment writes', () async {
      addTeam({testUser.uid: TeamRole.coach, 'owner': TeamRole.owner});
      posts.canUseFeedExtras = false;
      final vm = homeVm();
      await pumpEventQueue();
      expect(vm.canPin, isFalse);
      expect(vm.canComment, isFalse);
      vm.dispose();
    });

    test('a comment thread adds and deletes', () async {
      addTeam({testUser.uid: TeamRole.player, 'owner': TeamRole.owner});
      posts.commenter = testUser.uid;
      posts.comments['t1/old'] = [
        TeamPostComment(
          id: 'c0',
          authorId: 'owner',
          authorName: 'O',
          body: 'Read these',
          createdAt: now,
        ),
      ];
      final home = homeVm();
      final vm = home.commentsFor(posts.posts['t1']![1]);
      await pumpEventQueue();
      expect(vm.comments.map((c) => c.body), ['Read these']);
      await vm.add.execute('   ');
      expect(vm.add.result, isA<Error<void>>());
      await vm.add.execute('  Got it  ');
      await pumpEventQueue();
      expect(vm.comments.map((c) => c.body), ['Read these', 'Got it']);
      // A player deletes their own, not someone else's.
      expect(vm.canDelete(vm.comments.first), isFalse);
      expect(vm.canDelete(vm.comments.last), isTrue);
      await vm.delete.execute(vm.comments.last.id);
      await pumpEventQueue();
      expect(vm.comments, hasLength(1));
      vm.dispose();
      home.dispose();
    });
  });

  group('TeamHomeScreen', () {
    Future<void> pump(WidgetTester tester, TeamHomeViewModel vm) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: TeamHomeScreen(viewModel: vm),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('members see the pinned post first with comment counts', (
      tester,
    ) async {
      addTeam({testUser.uid: TeamRole.player, 'owner': TeamRole.owner});
      await pump(tester, homeVm());
      expect(find.text('Pinned'), findsOneWidget);
      final pinnedY = tester.getTopLeft(find.text('Old rules')).dy;
      expect(pinnedY, lessThan(tester.getTopLeft(find.text('Newest news')).dy));
      expect(find.text('2 comments'), findsOneWidget);
      expect(find.text('1 comment'), findsOneWidget);
      expect(find.text('Comment'), findsOneWidget);
      // Players don't post or pin.
      expect(find.text('Post to the team…'), findsNothing);
      expect(find.byTooltip('Post options'), findsNothing);

      await tester.tap(find.text('2 comments'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'On it');
      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();
      expect(find.text('On it'), findsOneWidget);
      expect(posts.comments['t1/old']!.single.body, 'On it');
    });

    testWidgets('admins post from the box and pin, picking one to swap', (
      tester,
    ) async {
      addTeam({testUser.uid: TeamRole.coach, 'owner': TeamRole.owner});
      posts.posts['t1']!.addAll([
        post(
          'p2',
          'Second pin',
          hoursAgo: 20,
          pinnedAt: now.subtract(const Duration(hours: 1)),
        ),
        post(
          'p3',
          'Third pin',
          hoursAgo: 30,
          pinnedAt: now.subtract(const Duration(hours: 2)),
        ),
      ]);
      await pump(tester, homeVm());
      expect(find.text('Pinned'), findsNWidgets(3));

      await tester.tap(find.text('Post to the team…'));
      await tester.pumpAndSettle();
      expect(find.text('New post'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // "Newest news" isn't pinned: its menu offers Pin.
      final menus = find.byTooltip('Post options');
      await tester.ensureVisible(menus.at(3));
      await tester.pumpAndSettle();
      await tester.tap(menus.at(3));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pin to the top'));
      await tester.pumpAndSettle();
      expect(find.text('Unpin one to pin this'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(SimpleDialog),
          matching: find.text('Third pin'),
        ),
      );
      await tester.pumpAndSettle();
      expect(posts.pinCalls.last, 'pin new unpin p3');
      expect(find.text('Pinned'), findsNWidgets(3));
    });

    testWidgets('outsiders see no comments', (tester) async {
      addTeam({'owner': TeamRole.owner});
      posts.posts['t1']!.add(
        post(
          'pub',
          'Public pinned',
          isPublic: true,
          pinnedAt: now,
          comments: 4,
        ),
      );
      await pump(tester, homeVm());
      expect(find.text('Public pinned'), findsOneWidget);
      expect(find.text('Pinned'), findsOneWidget);
      expect(find.text('4 comments'), findsNothing);
      expect(find.text('Old rules'), findsNothing);
    });
  });
}
