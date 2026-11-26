// #24: a feed that failed to load says so; it must not say "You're all caught
// up." or "No posts yet.", or show the join prompt for teams it couldn't load.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/user_post.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/core/ui/layout.dart' show UnderlineTabs;
import 'package:frisbee_app/ui/home/view_models/home_viewmodel.dart';
import 'package:frisbee_app/ui/home/widgets/home_screen.dart';
import 'package:frisbee_app/ui/posts/view_models/home_feed.dart';

import '../testing/fakes.dart';
import '../testing/social_fakes.dart';

/// Fails the first author query (and the teams query) until [fixed].
class _FlakyUserPosts extends FakeUserPostRepository {
  bool failing = true;

  @override
  Stream<List<UserPost>> watchPostsByAuthors(
    List<String> authorIds, {
    int limit = 50,
    Set<String> includePrivate = const {},
  }) => failing
      ? Stream.error(Exception('permission-denied'))
      : super.watchPostsByAuthors(
          authorIds,
          limit: limit,
          includePrivate: includePrivate,
        );
}

class _FlakyTeams extends FakeTeamRepository {
  bool failing = true;

  @override
  Stream<List<Team>> watchMyTeams(String uid) => failing
      ? Stream.error(Exception('unavailable'))
      : super.watchMyTeams(uid);
}

Finder feedTab(String label) =>
    find.descendant(of: find.byType(UnderlineTabs), matching: find.text(label));

void main() {
  final now = DateTime(2026, 10, 28, 9);
  late _FlakyUserPosts userPosts;
  late _FlakyTeams teams;

  HomeFeed feed({bool teamsOnly = false}) => HomeFeed(
    uid: testUser.uid,
    followRepository: FakeFollowRepository(),
    teamRepository: teams,
    teamPostRepository: FakeTeamPostRepository(),
    userPostRepository: userPosts,
    teamsOnly: teamsOnly,
  );

  setUp(() {
    userPosts = _FlakyUserPosts();
    teams = _FlakyTeams()..failing = false;
  });

  group('HomeFeed.error', () {
    test('a failing live query is an error, not an empty feed', () async {
      final f = feed();
      await pumpEventQueue();
      expect(f.loaded, isTrue);
      expect(f.error, isTrue);
      f.dispose();
    });

    test('refresh tries again and clears the error', () async {
      final f = feed();
      await pumpEventQueue();
      expect(f.error, isTrue);
      userPosts.failing = false;
      await f.refresh();
      await pumpEventQueue();
      expect(f.error, isFalse);
      f.dispose();
    });

    test(
      'a failing teams stream is an error and refresh listens again',
      () async {
        userPosts.failing = false;
        teams.failing = true;
        final f = feed();
        await pumpEventQueue();
        expect(f.loaded, isTrue);
        expect(f.error, isTrue);
        expect(f.teams, isEmpty);
        teams.failing = false;
        await f.refresh();
        await pumpEventQueue();
        expect(f.error, isFalse);
        f.dispose();
      },
    );

    test('no error when everything loads', () async {
      userPosts.failing = false;
      final f = feed();
      await pumpEventQueue();
      expect(f.error, isFalse);
      f.dispose();
    });
  });

  group('Home screen', () {
    Future<HomeViewModel> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final vm = await tester.runAsync(() async {
        final vm = HomeViewModel(
          authRepository: FakeAuthRepository(user: testUser),
          teamRepository: teams,
          eventRepository: FakeEventRepository(),
          teamPostRepository: FakeTeamPostRepository(),
          followRepository: FakeFollowRepository(),
          userPostRepository: userPosts,
          filePicker: FakeFilePickerService(),
          clock: () => now,
        );
        await pumpEventQueue();
        return vm;
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: HomeScreen(viewModel: vm!),
        ),
      );
      await tester.pump();
      return vm;
    }

    testWidgets('Following shows the error and Try again, not "caught up"', (
      tester,
    ) async {
      await pump(tester);
      await tester.ensureVisible(feedTab('Following'));
      await tester.tap(feedTab('Following'));
      await tester.pump();
      await tester.pump();
      expect(find.text("Couldn't load posts."), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text("You're all caught up."), findsNothing);
      expect(find.textContaining('No posts yet'), findsNothing);
      expect(find.text('Get started'), findsNothing);

      // Trying again, with the problem gone, shows the real state.
      userPosts.failing = false;
      await tester.tap(find.text('Try again'));
      await tester.runAsync(pumpEventQueue);
      await tester.pump();
      await tester.pump();
      expect(find.text("Couldn't load posts."), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Your teams that failed to load says so, with no join card or '
        '"caught up"', (tester) async {
      userPosts.failing = false;
      teams.failing = true;
      await pump(tester);
      await tester.pump();
      expect(find.textContaining("Couldn't load"), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Get started'), findsNothing);
      expect(find.text("You're all caught up."), findsNothing);
      expect(find.textContaining('No team posts yet'), findsNothing);
    });

    testWidgets('with no error the empty feed still says so', (tester) async {
      userPosts.failing = false;
      await pump(tester);
      await tester.ensureVisible(feedTab('Following'));
      await tester.tap(feedTab('Following'));
      await tester.pump();
      await tester.pump();
      expect(find.text("Couldn't load posts."), findsNothing);
    });
  });
}
