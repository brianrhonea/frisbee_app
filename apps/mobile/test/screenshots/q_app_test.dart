// Sprint 5, lane Q-app: before/after pictures of the athlete profile,
// Discover, communities and pickups, and the post page and composer, on fake
// data. Skipped unless asked for:
//   flutter test test/screenshots/q_app_test.dart \
//     --dart-define=SCREENSHOTS=<review/app dir> \
//     --dart-define=SHOT_WIDTH=390|1024 [--dart-define=SHOT_THEME=dark] \
//     [--dart-define=SHOT_PHASE=before|after]
// Files are named <screen>_<width>_<theme>_<phase>[_variant].png under
// <dir>/Q<n>-<name>/.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/auth/auth_repository.dart';
import 'package:frisbee_app/data/repositories/follow/follow_repository.dart';
import 'package:frisbee_app/data/repositories/team/team_repository.dart';
import 'package:frisbee_app/data/repositories/user_post/user_post_repository.dart';
import 'package:frisbee_app/domain/models/hosted_tournament.dart';
import 'package:frisbee_app/domain/models/player_profile.dart';
import 'package:frisbee_app/domain/models/post_comment.dart';
import 'package:frisbee_app/domain/models/roster_player.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/user_post.dart';
import 'package:frisbee_app/routing/routes.dart';
import 'package:frisbee_app/ui/explore/view_models/explore_viewmodel.dart';
import 'package:frisbee_app/ui/explore/view_models/player_search_viewmodel.dart';
import 'package:frisbee_app/ui/explore/widgets/explore_screen.dart';
import 'package:frisbee_app/ui/posts/view_models/post_composer_viewmodel.dart';
import 'package:frisbee_app/ui/posts/view_models/post_detail_viewmodel.dart';
import 'package:frisbee_app/ui/posts/widgets/post_composer.dart';
import 'package:frisbee_app/ui/posts/widgets/post_detail_screen.dart';
import 'package:frisbee_app/ui/profile/view_models/player_profile_viewmodel.dart';
import 'package:frisbee_app/ui/profile/widgets/profile_screen.dart';
import 'package:frisbee_app/ui/teams/view_models/team_search_viewmodel.dart';
import 'package:provider/provider.dart';

import '../testing/fakes.dart';
import '../testing/hosted_tournament_fakes.dart';
import '../testing/social_fakes.dart';
import '../ui/explore_test.dart' show FakeRankingRepository, ranking;
import 's4_common.dart';
import 'shot_env.dart';

const _phase = String.fromEnvironment('SHOT_PHASE', defaultValue: 'after');

void main() {
  final skip = s4Out.isEmpty ? 'pass --dart-define=SCREENSHOTS=<dir>' : null;
  final me = testUser.uid;

  Future<void> snap(
    WidgetTester tester,
    String dir,
    String screen, [
    String variant = '',
  ]) async {
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump();
    final boundary =
        shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final name =
        '${screen}_${shotWidth}_${s4Dark ? 'dark' : 'light'}_$_phase'
        '${variant.isEmpty ? '' : '_$variant'}';
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory('$s4Out/$dir').createSync(recursive: true);
      File('$s4Out/$dir/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
  }

  Team flyers() => Team(
    id: 't1',
    name: 'Northside Flyers',
    division: Division.mixed,
    level: CompetitionLevel.club,
    city: 'Denver',
    ownerId: me,
    members: {me: TeamRole.owner, 'sam': TeamRole.player},
    memberNames: {me: 'Test User', 'sam': 'Sam Ortiz'},
  );

  group('Q1 athlete profile', () {
    Future<PlayerProfileViewModel> open(
      WidgetTester tester, {
      required bool mine,
    }) async {
      await shotSize(tester);
      final auth = FakeAuthRepository(user: testUser);
      final teams = FakeTeamRepository();
      teams.teams['t1'] = flyers();
      teams.roster['t1'] = [
        RosterPlayer(
          id: 'r1',
          name: 'Test User',
          number: 17,
          userId: mine ? me : null,
          position: PlayerPosition.handler,
        ),
        const RosterPlayer(id: 'r2', name: 'Sam Ortiz', number: 7),
      ];
      final profiles = FakeProfileRepository();
      final follows = FakeFollowRepository();
      final posts = FakeUserPostRepository()
        ..posts.addAll([
          UserPost(
            id: 'p1',
            authorId: mine ? me : 'p2',
            authorName: mine ? 'Test User' : 'Jamie Carter',
            body:
                'Great turnout at practice last night! Building momentum '
                'for the tournament.',
            likedBy: const ['sam'],
            commentCount: 2,
            createdAt: DateTime(2026, 11, 26, 9),
          ),
        ]);
      if (!mine) {
        profiles.put(
          PlayerProfile(
            uid: 'p2',
            name: 'Jamie Carter',
            username: 'jamiecarter',
            details: const ProfileDetails(
              bio:
                  'Captain and ultimate frisbee fanatic. Competing with '
                  'Riptide and always looking for pickup games.',
              pronouns: 'she/her',
              hometown: 'Seattle, WA',
              school: 'UW',
              playingSince: 2014,
            ),
            summary: ProfileSummary(
              teams: const [
                ProfileTeam(
                  id: 't1',
                  name: 'Riptide',
                  subtitle: 'Mixed · Club · Seattle',
                  role: 'Captain',
                  number: 24,
                  position: 'Handler',
                ),
              ],
              seasons: {
                '2026': const StatTotals(
                  games: 18,
                  goals: 21,
                  assists: 34,
                  completions: 410,
                ),
              },
              games: [
                ProfileGame(
                  teamName: 'Riptide',
                  opponent: 'Sub Zero',
                  date: DateTime(2026, 11, 8),
                  ourScore: 13,
                  theirScore: 9,
                  line: const StatTotals(games: 1, goals: 2, assists: 3),
                ),
              ],
            ),
          ),
        );
      }
      final vm = PlayerProfileViewModel(
        uid: mine ? me : 'p2',
        profileRepository: profiles,
        authRepository: auth,
        teamRepository: teams,
        statsRepository: FakeStatsRepository(),
        directMessageRepository: FakeDirectMessageRepository(),
        followRepository: follows,
        userPostRepository: posts,
      );
      addTearDown(vm.dispose);
      await shotPump(
        tester,
        PlayerProfileScreen(viewModel: vm),
        wrap: (app) => MultiProvider(
          providers: [
            Provider<UserPostRepository>.value(value: posts),
            Provider<FollowRepository>.value(value: follows),
            Provider<TeamRepository>.value(value: teams),
            ChangeNotifierProvider<AuthRepository>.value(value: auth),
          ],
          child: app,
        ),
      );
      return vm;
    }

    for (final (mine, variant) in [(true, 'own'), (false, 'other')]) {
      testWidgets('overview $variant', skip: skip != null, (tester) async {
        await open(tester, mine: mine);
        await snap(tester, 'Q1-athlete-profile', 'profile', variant);
      });
    }

    testWidgets('stats tab', skip: skip != null, (tester) async {
      await open(tester, mine: false);
      await tester.tap(find.text('Stats').last);
      await snap(tester, 'Q1-athlete-profile', 'profile', 'stats');
    });
  });

  group('Q2 and Q3 discover', () {
    late FakeTeamRepository teams;
    late FakeHostedTournamentRepository tournaments;

    (TeamSearchViewModel, PlayerSearchViewModel, ExploreViewModel) build() {
      teams = FakeTeamRepository();
      TeamListing l(
        String id,
        String name, {
        TeamKind kind = TeamKind.team,
        bool approval = false,
      }) => TeamListing(
        id: id,
        name: name,
        division: Division.mixed,
        level: kind == TeamKind.community
            ? CompetitionLevel.pickup
            : CompetitionLevel.club,
        city: 'Denver',
        kind: kind,
        requiresApproval: approval,
      );
      for (final t in [
        l('a', 'Denver Open Pickup', kind: TeamKind.community),
        l(
          'b',
          'Denver Approval Pickup',
          kind: TeamKind.community,
          approval: true,
        ),
        l('c', 'Denver Flyers'),
        l('d', 'Denver Code Team'),
        l('e', 'Denver Thursday Pickup', kind: TeamKind.community),
      ]) {
        teams.listings[t.id] = t;
        teams.teams[t.id] = Team(
          id: t.id,
          name: t.name,
          division: t.division,
          level: t.level,
          ownerId: t.id == 'e' ? me : 'owner',
          members: {t.id == 'e' ? me : 'owner': TeamRole.owner},
          kind: t.kind,
        );
      }
      tournaments = FakeHostedTournamentRepository()
        ..tournaments['a'] = HostedTournament(
          id: 'a',
          hostId: 'h',
          hostName: 'Austin Ultimate',
          name: 'Lone Star Classic',
          location: 'Austin, TX',
          startsOn: DateTime.now().add(const Duration(days: 10)),
          status: HostedStatus.registration,
        )
        ..tournaments['b'] = HostedTournament(
          id: 'b',
          hostId: 'h2',
          hostName: 'Seattle Ultimate',
          name: 'Emerald City Hat',
          location: 'Seattle, WA',
          startsOn: DateTime.now().add(const Duration(days: 24)),
          status: HostedStatus.registration,
        );
      final rankings = FakeRankingRepository()
        ..initialRankings = [
          ranking(CompetitionLevel.club, Division.open, [
            for (var i = 0; i < 5; i++) ('o$i', 'Open $i'),
          ]),
        ];
      final vm = TeamSearchViewModel(
        teamRepository: teams,
        authRepository: FakeAuthRepository(user: testUser),
      );
      final players = PlayerSearchViewModel(
        profileRepository: FakeProfileRepository(),
      );
      final explore = ExploreViewModel(
        tournamentRepository: tournaments,
        rankingRepository: rankings,
        teamRepository: teams,
        authRepository: FakeAuthRepository(user: testUser),
      );
      addTearDown(vm.dispose);
      addTearDown(players.dispose);
      addTearDown(explore.dispose);
      return (vm, players, explore);
    }

    testWidgets('Q2 discover', skip: skip != null, (tester) async {
      await shotSize(tester);
      final (vm, players, explore) = build();
      await shotPump(
        tester,
        ExploreScreen(viewModel: vm, players: players, explore: explore),
      );
      await snap(tester, 'Q2-discover', 'discover');
    });

    testWidgets('Q3 communities and pickups', skip: skip != null, (
      tester,
    ) async {
      await shotSize(tester);
      final (vm, players, explore) = build();
      await shotPump(
        tester,
        ExploreScreen(
          viewModel: vm,
          players: players,
          explore: explore,
          initialQuery: 'denver',
          initialFilter: ExploreFilter.groups,
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      await snap(tester, 'Q3-communities-pickups', 'communities');
    });
  });

  group('Q4 post page and composer', () {
    testWidgets('post page', skip: skip != null, (tester) async {
      await shotSize(tester);
      final posts = FakeUserPostRepository()
        ..posts.add(
          UserPost(
            id: 'p1',
            authorId: 'sam',
            authorName: 'Sam Ortiz',
            body:
                'Great practice tonight! Highlights from the scrimmage '
                'are up in the playbook.',
            likedBy: const ['a', 'b', 'c'],
            commentCount: 3,
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
          likedBy: const ['sam'],
        ),
        PostComment(
          id: 'c2',
          postId: 'p1',
          authorId: 'sam',
          authorName: 'Sam Ortiz',
          body: 'Thanks! See you Thursday.',
          createdAt: DateTime(2026, 11, 26, 22),
          parentId: 'c1',
          replyToName: 'Jo Park',
        ),
        PostComment(
          id: 'c3',
          postId: 'p1',
          authorId: me,
          authorName: 'Test User',
          body: 'Count me in.',
          createdAt: DateTime(2026, 11, 26, 23),
        ),
      ]);
      final auth = FakeAuthRepository(user: testUser);
      final vm = PostDetailViewModel(
        postId: 'p1',
        userPostRepository: posts,
        authRepository: auth,
        commentRepository: comments,
      );
      addTearDown(vm.dispose);
      await shotPump(
        tester,
        PostDetailScreen(viewModel: vm),
        wrap: (app) => MultiProvider(
          providers: [
            Provider<UserPostRepository>.value(value: posts),
            Provider<FollowRepository>.value(value: FakeFollowRepository()),
            Provider<TeamRepository>.value(value: FakeTeamRepository()),
            ChangeNotifierProvider<AuthRepository>.value(value: auth),
          ],
          child: app,
        ),
      );
      await snap(tester, 'Q4-post-detail', 'post');
    });

    testWidgets('composer', skip: skip != null, (tester) async {
      await shotSize(tester);
      final vm = PostComposerViewModel(
        postId: null,
        userPostRepository: FakeUserPostRepository(),
        followRepository: FakeFollowRepository(),
        authRepository: FakeAuthRepository(user: testUser),
        filePicker: FakeFilePickerService(),
      );
      addTearDown(vm.dispose);
      await shotPump(tester, PostComposer(viewModel: vm));
      await tester.enterText(
        find.byType(TextField).first,
        'Highlights from Sunday: the break throw at 12-11 was unreal.',
      );
      await snap(tester, 'Q4-post-detail', 'composer');
    });
  });
}
