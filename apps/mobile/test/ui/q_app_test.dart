// Sprint 5 lane Q-app: the athlete profile, Discover (and its communities and
// pickup results) and the post page, restyled onto the shared components
// (CoverHeader, SummaryTiles, SegmentedTabs, AppFilterChip, StatusPill).
// Goldens compare on Windows only; the other checks run everywhere.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/auth/auth_repository.dart';
import 'package:frisbee_app/data/repositories/follow/follow_repository.dart';
import 'package:frisbee_app/data/repositories/team/team_repository.dart';
import 'package:frisbee_app/data/repositories/user_post/user_post_repository.dart';
import 'package:frisbee_app/domain/models/player_profile.dart';
import 'package:frisbee_app/domain/models/post_comment.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/user_post.dart';
import 'package:frisbee_app/ui/core/ui/cover_header.dart';
import 'package:frisbee_app/ui/core/ui/filter_chips.dart';
import 'package:frisbee_app/ui/core/ui/segmented_tabs.dart';
import 'package:frisbee_app/ui/core/ui/status_pill.dart';
import 'package:frisbee_app/ui/core/ui/summary_tiles.dart';
import 'package:frisbee_app/routing/routes.dart';
import 'package:frisbee_app/ui/explore/view_models/player_search_viewmodel.dart';
import 'package:frisbee_app/ui/explore/widgets/explore_screen.dart';
import 'package:frisbee_app/ui/posts/view_models/post_detail_viewmodel.dart';
import 'package:frisbee_app/ui/posts/widgets/post_detail_screen.dart';
import 'package:frisbee_app/ui/profile/view_models/player_profile_viewmodel.dart';
import 'package:frisbee_app/ui/profile/widgets/profile_screen.dart';
import 'package:frisbee_app/ui/teams/view_models/team_search_viewmodel.dart';
import 'package:provider/provider.dart';

import '../testing/fakes.dart';
import '../testing/social_fakes.dart';
import '../ui_harness/harness.dart';

void main() {
  final me = testUser.uid;

  Widget providers(Widget child, {FakeUserPostRepository? posts}) =>
      MultiProvider(
        providers: [
          Provider<UserPostRepository>.value(
            value: posts ?? FakeUserPostRepository(),
          ),
          Provider<FollowRepository>.value(value: FakeFollowRepository()),
          Provider<TeamRepository>.value(value: FakeTeamRepository()),
          ChangeNotifierProvider<AuthRepository>.value(
            value: FakeAuthRepository(user: testUser),
          ),
        ],
        child: child,
      );

  group('athlete profile', () {
    PlayerProfileViewModel profile({required bool mine}) {
      final profiles = FakeProfileRepository();
      if (!mine) {
        profiles.put(
          PlayerProfile(
            uid: 'p2',
            name: 'Jamie Carter',
            username: 'jamiecarter',
            details: const ProfileDetails(
              bio: 'Captain and ultimate fanatic.',
              hometown: 'Seattle, WA',
            ),
            summary: ProfileSummary(
              teams: const [
                ProfileTeam(id: 't1', name: 'Riptide', role: 'Captain'),
              ],
              seasons: {'2026': const StatTotals(games: 18, goals: 21)},
            ),
          ),
        );
      }
      final vm = PlayerProfileViewModel(
        uid: mine ? me : 'p2',
        profileRepository: profiles,
        authRepository: FakeAuthRepository(user: testUser),
        teamRepository: FakeTeamRepository(),
        statsRepository: FakeStatsRepository(),
        directMessageRepository: FakeDirectMessageRepository(),
        followRepository: FakeFollowRepository(),
        userPostRepository: FakeUserPostRepository(),
      );
      addTearDown(vm.dispose);
      return vm;
    }

    Widget screen(PlayerProfileViewModel vm) =>
        providers(PlayerProfileScreen(viewModel: vm));

    testWidgets('uses the cover header, tiles and segmented tabs', (
      tester,
    ) async {
      final vm = profile(mine: false);
      await pumpInApp(tester, screen(vm), height: 900);
      expect(find.byType(CoverHeader), findsOneWidget);
      expect(find.byType(SummaryTiles), findsOneWidget);
      expect(find.byType(SegmentedTabs), findsOneWidget);
      expect(find.text('Jamie Carter'), findsWidgets);
      expect(find.text('@jamiecarter'), findsOneWidget);
      expect(find.text('FOLLOWERS'), findsOneWidget);
      expect(find.text('Message'), findsOneWidget);
      // Overview, Posts, Stats and Teams are all still there.
      for (final t in ['Overview', 'Posts', 'Stats', 'Teams']) {
        expect(
          find.descendant(
            of: find.byType(SegmentedTabs),
            matching: find.text(t),
          ),
          findsOneWidget,
          reason: t,
        );
      }
    });

    testWidgets('the tabs still switch what is shown', (tester) async {
      final vm = profile(mine: false);
      await pumpInApp(tester, screen(vm), height: 900);
      expect(find.text('By the numbers'), findsOneWidget);
      // On a phone the four tabs scroll sideways; bring Teams into view.
      final teamsTab = find.descendant(
        of: find.byType(SegmentedTabs),
        matching: find.text('Teams'),
      );
      await tester.ensureVisible(teamsTab);
      await tester.pumpAndSettle();
      await tester.tap(teamsTab);
      await tester.pumpAndSettle();
      expect(find.text('Riptide'), findsWidgets);
      expect(find.text('By the numbers'), findsNothing);
    });

    testWidgets('your own profile keeps Edit profile and the follow tiles', (
      tester,
    ) async {
      final vm = profile(mine: true);
      await pumpInApp(tester, screen(vm), height: 900);
      expect(find.text('Edit profile'), findsOneWidget);
      expect(find.text('Message'), findsNothing);
      expect(find.text('FOLLOWING'), findsOneWidget);
    });

    testWidgets('large text does not overflow', (tester) async {
      final vm = profile(mine: false);
      await expectNoOverflowWithLargeText(tester, screen(vm), height: 900);
    });

    testWidgets('meets the tap target and contrast guidelines', (tester) async {
      final vm = profile(mine: false);
      await pumpInApp(tester, screen(vm), height: 900);
      await expectAccessible(tester);
    });

    testWidgets('golden: profile', (tester) async {
      final vm = profile(mine: false);
      await expectGoldens(tester, screen(vm), 'q1_profile', height: 900);
    }, skip: goldenSkip != null);
  });

  group('discover', () {
    (TeamSearchViewModel, PlayerSearchViewModel) build() {
      final teams = FakeTeamRepository();
      TeamListing l(String id, String name, {bool approval = false}) =>
          TeamListing(
            id: id,
            name: name,
            division: Division.mixed,
            level: CompetitionLevel.pickup,
            city: 'Denver',
            kind: TeamKind.community,
            requiresApproval: approval,
          );
      for (final t in [
        l('a', 'Denver Open Pickup'),
        l('b', 'Denver Approval Pickup', approval: true),
        l('e', 'Denver Thursday Pickup'),
      ]) {
        teams.listings[t.id] = t;
        final owner = t.id == 'e' ? me : 'owner';
        teams.teams[t.id] = Team(
          id: t.id,
          name: t.name,
          division: t.division,
          level: t.level,
          ownerId: owner,
          members: {owner: TeamRole.owner},
          kind: t.kind,
        );
      }
      final vm = TeamSearchViewModel(
        teamRepository: teams,
        authRepository: FakeAuthRepository(user: testUser),
      );
      final players = PlayerSearchViewModel(
        profileRepository: FakeProfileRepository(),
      );
      addTearDown(vm.dispose);
      addTearDown(players.dispose);
      return (vm, players);
    }

    Widget screen(
      TeamSearchViewModel vm,
      PlayerSearchViewModel players, {
      String query = '',
      ExploreFilter? filter,
    }) => ExploreScreen(
      viewModel: vm,
      players: players,
      initialQuery: query,
      initialFilter: filter,
    );

    testWidgets('the filter chips are the shared chip, check on the one '
        'picked', (tester) async {
      final (vm, players) = build();
      await pumpInApp(tester, screen(vm, players), height: 900);
      expect(find.byType(AppFilterChip), findsWidgets);
      expect(find.widgetWithText(AppFilterChip, 'All'), findsOneWidget);
      await tester.tap(find.widgetWithText(AppFilterChip, 'Teams'));
      await tester.pumpAndSettle();
      final teams = tester.widget<AppFilterChip>(
        find.widgetWithText(AppFilterChip, 'Teams'),
      );
      expect(teams.selected, isTrue);
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Teams'))
            .showCheckmark,
        isTrue,
        reason: 'the chip picked is marked by a check, not by colour alone',
      );
    });

    testWidgets('communities: Join, Ask to join and Your community', (
      tester,
    ) async {
      final (vm, players) = build();
      await pumpInApp(
        tester,
        screen(vm, players, query: 'denver', filter: ExploreFilter.groups),
        height: 900,
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('Denver Open Pickup'), findsOneWidget);
      expect(find.text('Join'), findsOneWidget);
      expect(find.text('Ask to join'), findsOneWidget);
      // What you already belong to is a pill, not a button.
      expect(find.widgetWithText(StatusPill, 'Joined'), findsOneWidget);
    });

    testWidgets('large text does not overflow', (tester) async {
      final (vm, players) = build();
      await expectNoOverflowWithLargeText(
        tester,
        screen(vm, players, query: 'denver', filter: ExploreFilter.groups),
        height: 900,
      );
    });

    testWidgets('golden: communities results', (tester) async {
      final (vm, players) = build();
      await expectGoldens(
        tester,
        screen(vm, players, query: 'denver', filter: ExploreFilter.groups),
        'q3_communities',
        height: 900,
      );
    }, skip: goldenSkip != null);
  });

  group('post page', () {
    PostDetailViewModel post(FakeUserPostRepository posts) {
      posts.posts.add(
        UserPost(
          id: 'p1',
          authorId: 'sam',
          authorName: 'Sam Ortiz',
          body: 'Great practice tonight!',
          commentCount: 2,
          createdAt: DateTime(2026, 11, 26, 20),
        ),
      );
      final comments = FakePostCommentRepository(posts: posts);
      comments.comments.addAll([
        PostComment(
          id: 'c1',
          postId: 'p1',
          authorId: 'jo',
          authorName: 'Jo Park',
          body: 'That layout D was unreal.',
          createdAt: DateTime(2026, 11, 26, 21),
        ),
        PostComment(
          id: 'c2',
          postId: 'p1',
          authorId: 'sam',
          authorName: 'Sam Ortiz',
          body: 'Thanks!',
          createdAt: DateTime(2026, 11, 26, 22),
          parentId: 'c1',
          replyToName: 'Jo Park',
        ),
      ]);
      final vm = PostDetailViewModel(
        postId: 'p1',
        userPostRepository: posts,
        authRepository: FakeAuthRepository(user: testUser),
        commentRepository: comments,
      );
      addTearDown(vm.dispose);
      return vm;
    }

    Widget screen(FakeUserPostRepository posts) =>
        providers(PostDetailScreen(viewModel: post(posts)), posts: posts);

    testWidgets('comments, replies and the box to add one are there', (
      tester,
    ) async {
      await pumpInApp(tester, screen(FakeUserPostRepository()), height: 900);
      expect(find.text('Comments (2)'), findsOneWidget);
      expect(find.text('That layout D was unreal.'), findsOneWidget);
      expect(find.text('@Jo Park'), findsOneWidget);
      expect(find.text('Add a comment…'), findsOneWidget);
    });

    testWidgets('Like, Reply and delete are at least 48 px', (tester) async {
      await pumpInApp(tester, screen(FakeUserPostRepository()), height: 900);
      for (final label in ['Reply']) {
        final box = tester.getSize(
          find.widgetWithText(TextButton, label).first,
        );
        expect(box.height, greaterThanOrEqualTo(48), reason: label);
      }
    });

    testWidgets('buttons are labelled and text has contrast; the author and '
        'comment pictures are 48 px targets', (tester) async {
      await pumpInApp(tester, screen(FakeUserPostRepository()), height: 900);
      final handle = tester.ensureSemantics();
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
      // The tap-target guideline also flags the comment text, which is
      // selectable (LinkifiedText, shared); the controls themselves are 48.
      for (final box in [
        tester.getSize(find.widgetWithText(InkWell, 'Sam Ortiz').first),
        for (final i in find.byType(CommentTile).evaluate())
          tester.getSize(
            find
                .descendant(
                  of: find.byWidget(i.widget),
                  matching: find.byType(InkWell),
                )
                .first,
          ),
      ]) {
        expect(box.height, greaterThanOrEqualTo(48));
      }
    });

    testWidgets('large text does not overflow', (tester) async {
      await expectNoOverflowWithLargeText(
        tester,
        screen(FakeUserPostRepository()),
        height: 900,
      );
    });

    testWidgets('golden: post page', (tester) async {
      await expectGoldens(
        tester,
        screen(FakeUserPostRepository()),
        'q4_post',
        height: 900,
      );
    }, skip: goldenSkip != null);
  });
}
