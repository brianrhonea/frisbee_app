import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/auth/auth_repository.dart';
import 'package:frisbee_app/data/repositories/browse/browse_repository.dart';
import 'package:frisbee_app/data/repositories/theme/theme_repository.dart';
import 'package:frisbee_app/domain/models/browse.dart';
import 'package:frisbee_app/domain/models/chat.dart';
import 'package:frisbee_app/domain/models/group_tournament.dart';
import 'package:frisbee_app/domain/models/player_profile.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/team_event.dart';
import 'package:frisbee_app/domain/models/user_post.dart';
import 'package:frisbee_app/routing/routes.dart';
import 'package:frisbee_app/routing/web_router.dart';
import 'package:frisbee_app/ui/auth/widgets/sign_up_screen.dart';
import 'package:frisbee_app/ui/browse/view_models/browse_search_viewmodel.dart';
import 'package:frisbee_app/ui/browse/view_models/community_feed_viewmodel.dart';
import 'package:frisbee_app/ui/browse/widgets/community_feed_screen.dart';
import 'package:frisbee_app/ui/browse/widgets/public_profile_screen.dart';
import 'package:frisbee_app/ui/browse/widgets/public_team_screen.dart';
import 'package:frisbee_app/ui/web/view_models/web_shell_viewmodel.dart';
import 'package:frisbee_app/ui/web/widgets/get_the_app_screen.dart';
import 'package:frisbee_app/ui/web/widgets/web_shell.dart';
import 'package:frisbee_app/utils/result.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../testing/fakes.dart';

/// Public data as the `browse` functions would send it.
class FakeBrowseRepository implements BrowseRepository {
  final posts = <UserPost>[];
  final profiles = <String, PlayerProfile>{};
  final teams = <String, PublicTeamPage>{};
  UpcomingEvents upcomingEvents = const UpcomingEvents();

  @override
  Future<Result<PostPage>> feed({DateTime? before}) async =>
      Result.ok(PostPage(posts: before == null ? posts : const []));

  @override
  Future<Result<UserPost>> post(String id) async =>
      Result.ok(posts.firstWhere((p) => p.id == id));

  @override
  Future<Result<PublicProfilePage>> profile(
    String uid, {
    DateTime? before,
  }) async {
    final p = profiles[uid];
    if (p == null) return Result.error(Exception('No such player.'));
    return Result.ok(
      PublicProfilePage(
        profile: p,
        posts: PostPage(
          posts: p.isPrivate
              ? const []
              : [
                  for (final post in posts)
                    if (post.authorId == uid) post,
                ],
        ),
      ),
    );
  }

  @override
  Future<Result<PublicTeamPage>> team(String id) async {
    final t = teams[id];
    return t == null ? Result.error(Exception('No such team.')) : Result.ok(t);
  }

  @override
  Future<Result<UpcomingEvents>> upcoming() async => Result.ok(upcomingEvents);

  @override
  Future<Result<List<PlayerProfile>>> searchPlayers(String query) async =>
      Result.ok([
        for (final p in profiles.values)
          if (p.matches(query)) p,
      ]);

  @override
  Future<Result<List<TeamListing>>> searchTeams(String query) async =>
      Result.ok([
        for (final t in teams.values)
          if (t.listing.matches(query)) t.listing,
      ]);

  @override
  Future<Result<Uint8List>> downloadImage(ChatAttachment image) async =>
      Result.ok(Uint8List(0));
}

UserPost post(String id, {String authorId = 'u2', int likes = 0}) => UserPost(
  id: id,
  authorId: authorId,
  authorName: 'Sam Rivera',
  body: 'Hucks all day $id',
  likedBy: List.filled(likes, ''),
  createdAt: DateTime(2026, 11, 1),
);

void main() {
  test('WebShellViewModel picks light or dark and signs out', () async {
    final auth = FakeAuthRepository(user: testUser);
    final theme = FakeThemeRepository();
    final vm = WebShellViewModel(authRepository: auth, themeRepository: theme);
    addTearDown(vm.dispose);
    expect(vm.userName, testUser.label);

    await vm.setDark.execute(true);
    expect(theme.themeMode, ThemeMode.dark);
    await vm.setDark.execute(false);
    expect(theme.themeMode, ThemeMode.light);

    await vm.signOut.execute();
    expect(vm.user, isNull);
  });

  test('visitors get the public sections; members Home and profile too', () {
    List<String> labels(bool signedIn) => [
      for (final l in webNavLinks(signedIn: signedIn)) l.label,
    ];
    expect(labels(false), ['Community', 'Explore', 'Events']);
    expect(labels(true), ['Home', 'Community', 'Explore', 'Events', 'Profile']);

    final explore = webNavLinks(signedIn: false)[1];
    expect(isWebNavLinkActive(explore, '/explore?q=x'), isTrue);
    expect(isWebNavLinkActive(explore, '/players/u2'), isTrue);
    expect(isWebNavLinkActive(explore, '/teams/t1'), isTrue);
    final events = webNavLinks(signedIn: false)[2];
    expect(isWebNavLinkActive(events, '/events'), isTrue);
    expect(isWebNavLinkActive(events, '/eventsx'), isFalse);
  });

  group('webRedirect', () {
    String? go(FakeAuthRepository auth, String location) =>
        webRedirect(auth, Uri.parse(location));

    test('waits for auth on the splash page', () {
      final auth = FakeAuthRepository(ready: false);
      expect(go(auth, '/teams/t1'), '/splash?from=%2Fteams%2Ft1');
    });

    test('visitors browse public pages; members-only ones ask to sign in', () {
      final auth = FakeAuthRepository();
      expect(go(auth, '/'), Routes.community);
      expect(go(auth, '/splash'), Routes.community);
      for (final open in [
        Routes.community,
        '/explore?q=a',
        '/events',
        '/players/u2',
        '/teams/t1',
        Routes.signUp,
      ]) {
        expect(go(auth, open), isNull, reason: open);
      }
      expect(go(auth, Routes.home), '/sign-in?from=%2Fhome');
      expect(go(auth, '/profile'), '/sign-in?from=%2Fprofile');
      expect(go(auth, '/posts/p1'), '/sign-in?from=%2Fposts%2Fp1');
    });

    test('members land on Home, and signing in returns where they were', () {
      final auth = FakeAuthRepository(user: testUser);
      expect(go(auth, '/'), Routes.home);
      expect(go(auth, Routes.signIn), Routes.home);
      expect(go(auth, '/sign-in?from=/teams/t1'), '/teams/t1');
      expect(go(auth, '/sign-up?from=/players/u2'), '/players/u2');
      expect(go(auth, '/splash?from=/events'), '/events');
      expect(go(auth, Routes.community), isNull);
    });

    test('new members pick a username first', () {
      final auth = FakeAuthRepository(user: testUser)..usernameMissing = true;
      expect(
        go(auth, '/sign-up?from=/teams/t1'),
        '${Routes.chooseUsername}?from=%2Fteams%2Ft1',
      );
      expect(go(auth, Routes.chooseUsername), isNull);
      auth.usernameMissing = false;
      expect(go(auth, '${Routes.chooseUsername}?from=/teams/t1'), '/teams/t1');
    });
  });

  test('the community feed loads public posts', () async {
    final browse = FakeBrowseRepository()..posts.add(post('p1'));
    final vm = CommunityFeedViewModel(
      browseRepository: browse,
      authRepository: FakeAuthRepository(),
    );
    addTearDown(vm.dispose);
    await pumpEventQueue();
    expect(vm.posts.map((p) => p.id), ['p1']);
    expect(vm.hasMore, isFalse);
    expect(vm.signedIn, isFalse);
  });

  test('visitor search finds players and teams', () async {
    final browse = FakeBrowseRepository()
      ..profiles['u2'] = const PlayerProfile(uid: 'u2', name: 'Sam Rivera')
      ..teams['t1'] = const PublicTeamPage(
        listing: TeamListing(
          id: 't1',
          name: 'Riverside Ultimate',
          division: Division.mixed,
          level: CompetitionLevel.club,
        ),
      );
    final vm = BrowseSearchViewModel(browseRepository: browse);
    addTearDown(vm.dispose);
    await vm.search.execute('river');
    expect(vm.players.map((p) => p.name), ['Sam Rivera']);
    expect(vm.teams.map((t) => t.name), ['Riverside Ultimate']);
    await vm.search.execute('zzz');
    expect(vm.noMatches, isTrue);
  });

  group('the website', () {
    late FakeAuthRepository auth;
    late FakeBrowseRepository browse;
    late GoRouter router;

    setUp(() {
      browse = FakeBrowseRepository()
        ..posts.addAll([post('p1', likes: 3), post('p2', authorId: 'u3')])
        ..profiles['u2'] = const PlayerProfile(uid: 'u2', name: 'Sam Rivera')
        ..profiles['u3'] = const PlayerProfile(
          uid: 'u3',
          name: 'Alex Chen',
          isPrivate: true,
        )
        ..teams['t1'] = PublicTeamPage(
          listing: const TeamListing(
            id: 't1',
            name: 'Riverside Ultimate',
            division: Division.mixed,
            level: CompetitionLevel.club,
            city: 'Denver',
          ),
          events: [
            TeamEvent(
              id: 'e1',
              title: 'Open tryouts',
              type: EventType.practice,
              startsAt: DateTime(2026, 12, 5, 18),
            ),
          ],
        )
        ..upcomingEvents = UpcomingEvents(
          tournaments: [
            TournamentListing(
              groupId: 'g1',
              tournamentId: 'x1',
              name: 'Winter Hat',
              startsAt: DateTime(2026, 12, 12),
            ),
          ],
        );
    });

    Future<void> pump(
      WidgetTester tester,
      String location, {
      Size size = const Size(1440, 900),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      router = webRouter(auth, initialLocation: location);
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthRepository>.value(value: auth),
            ChangeNotifierProvider<ThemeRepository>.value(
              value: FakeThemeRepository(),
            ),
            Provider<BrowseRepository>.value(value: browse),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
    }

    String location() =>
        router.routerDelegate.currentConfiguration.uri.toString();

    testWidgets('visitors land on the community feed, with a way to join', (
      tester,
    ) async {
      auth = FakeAuthRepository();
      await pump(tester, '/');
      expect(location(), Routes.community);
      expect(find.byType(CommunityFeedScreen), findsOneWidget);
      expect(find.text('Hucks all day p1'), findsOneWidget);
      expect(find.text("Don't miss a point"), findsOneWidget);
      expect(find.text('New to Stall 10?'), findsOneWidget);
      // x.com-style footer links.
      expect(find.text('Privacy Policy'), findsOneWidget);
      expect(find.text('Terms of Service'), findsOneWidget);
    });

    testWidgets('liking asks a visitor to join, and comes back after', (
      tester,
    ) async {
      auth = FakeAuthRepository();
      await pump(tester, Routes.community);
      await tester.tap(find.bySemanticsLabel('3 likes'));
      await tester.pumpAndSettle();
      expect(find.text('Like a post to share the love.'), findsOneWidget);

      await tester.tap(find.text('Create account').last);
      await tester.pumpAndSettle();
      expect(find.byType(SignUpScreen), findsOneWidget);
      expect(location(), '/sign-up?from=%2Fcommunity');
    });

    testWidgets('visitors see public profiles; private ones stay private', (
      tester,
    ) async {
      auth = FakeAuthRepository();
      await pump(tester, '/players/u2');
      expect(find.byType(PublicProfileScreen), findsOneWidget);
      expect(find.text('Hucks all day p1'), findsOneWidget);

      router.go('/players/u3');
      await tester.pumpAndSettle();
      expect(find.text('This profile is private'), findsOneWidget);
      expect(find.text('Hucks all day p2'), findsNothing);
      expect(find.text('Request to follow'), findsOneWidget);
    });

    testWidgets('visitors see team pages and what is coming up', (
      tester,
    ) async {
      auth = FakeAuthRepository();
      await pump(tester, '/teams/t1');
      expect(find.byType(PublicTeamScreen), findsOneWidget);
      expect(find.text('Open tryouts'), findsOneWidget);
      await tester.tap(find.text('Join'));
      await tester.pumpAndSettle();
      expect(
        find.text('Join a team to get its schedule, chats and playbook.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Events'));
      await tester.pumpAndSettle();
      expect(location(), Routes.upcomingEvents);
      expect(find.text('Winter Hat'), findsOneWidget);
    });

    testWidgets('members-only pages send visitors to sign in', (tester) async {
      auth = FakeAuthRepository();
      await pump(tester, Routes.home);
      expect(location(), '/sign-in?from=%2Fhome');
    });

    testWidgets('app-only pages offer the app', (tester) async {
      auth = FakeAuthRepository(user: testUser);
      await pump(tester, '/teams/t1/meetings');
      expect(find.byType(GetTheAppScreen), findsOneWidget);
      expect(find.byType(WebShell), findsOneWidget);
      // Members get the app card instead of the sign-up one.
      expect(find.text('Take Stall 10 with you'), findsOneWidget);
      expect(find.text("Don't miss a point"), findsNothing);
    });

    testWidgets('on a phone the sections are along the bottom', (
      tester,
    ) async {
      auth = FakeAuthRepository();
      await pump(tester, Routes.community, size: const Size(390, 800));
      expect(find.byType(NavigationBar), findsOneWidget);
      await tester.tap(find.text('Events'));
      await tester.pumpAndSettle();
      expect(location(), Routes.upcomingEvents);
    });
  });
}
