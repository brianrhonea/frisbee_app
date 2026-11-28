// Sprint 5 Q6 (app): the "..." menu over the profile cover (Report, Block,
// Share), Discover's Events chip and Athletes rename, and the profile's
// Media tab. The website mirrors these (apps/web, tests/e2e/q6-world).
// Goldens compare on Windows only; the other checks run everywhere.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:frisbee_app/data/repositories/auth/auth_repository.dart';
import 'package:frisbee_app/data/repositories/follow/follow_repository.dart';
import 'package:frisbee_app/data/repositories/moderation/moderation_repository.dart';
import 'package:frisbee_app/data/repositories/team/team_repository.dart';
import 'package:frisbee_app/data/repositories/user_post/user_post_repository.dart';
import 'package:frisbee_app/domain/models/chat.dart';
import 'package:frisbee_app/domain/models/player_profile.dart';
import 'package:frisbee_app/domain/models/user_post.dart';
import 'package:frisbee_app/routing/routes.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/core/ui/cover_menu_button.dart';
import 'package:frisbee_app/ui/profile/view_models/player_profile_viewmodel.dart';
import 'package:frisbee_app/ui/profile/widgets/profile_screen.dart';
import 'package:frisbee_app/utils/invite_links.dart';
import 'package:provider/provider.dart';

import '../testing/fakes.dart';
import '../testing/moderation_fakes.dart';
import '../testing/social_fakes.dart';
import '../ui_harness/harness.dart';

void main() {
  final me = testUser.uid;
  final thumbs = find.byWidgetPredicate(
    (w) => w.runtimeType.toString() == '_MediaTile',
  );

  const photo = ChatAttachment(
    path: 'posts/p1/a.jpg',
    name: 'a.jpg',
    contentType: 'image/jpeg',
    size: 10,
  );

  const photo2 = ChatAttachment(
    path: 'posts/p1/b.jpg',
    name: 'b.jpg',
    contentType: 'image/jpeg',
    size: 10,
  );

  Widget providers(
    Widget child, {
    required FakeUserPostRepository posts,
    FakeModerationRepository? moderation,
  }) => MultiProvider(
    providers: [
      Provider<UserPostRepository>.value(value: posts),
      Provider<FollowRepository>.value(value: FakeFollowRepository()),
      Provider<TeamRepository>.value(value: FakeTeamRepository()),
      ChangeNotifierProvider<AuthRepository>.value(
        value: FakeAuthRepository(user: testUser),
      ),
      ChangeNotifierProvider<ModerationRepository>.value(
        value: moderation ?? FakeModerationRepository(),
      ),
    ],
    child: child,
  );

  PlayerProfileViewModel profile({
    required bool mine,
    required FakeUserPostRepository posts,
  }) {
    final profiles = FakeProfileRepository();
    if (!mine) {
      profiles.put(
        PlayerProfile(
          uid: 'p2',
          name: 'Jamie Carter',
          username: 'jamiecarter',
          details: const ProfileDetails(bio: 'Captain.'),
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
      userPostRepository: posts,
    );
    addTearDown(vm.dispose);
    return vm;
  }

  UserPost post(String id, String author, {List<ChatAttachment>? images}) =>
      UserPost(
        id: id,
        authorId: author,
        authorName: 'Jamie Carter',
        body: 'Post $id',
        images: images ?? const [],
        createdAt: DateTime(2026, 11, 20),
      );

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
  }

  group('profile cover menu', () {
    testWidgets("someone else's profile: Report, Block, Share in order", (
      tester,
    ) async {
      final posts = FakeUserPostRepository();
      final vm = profile(mine: false, posts: posts);
      await pumpInApp(
        tester,
        providers(PlayerProfileScreen(viewModel: vm), posts: posts),
        height: 900,
      );
      expect(find.byType(CoverMenuButton), findsOneWidget);
      // Not in the top bar any more.
      expect(find.byTooltip('More'), findsNothing);
      await openMenu(tester);
      final labels = [
        for (final t in tester.widgetList<Text>(
          find.descendant(
            of: find.byType(PopupMenuItem<int>),
            matching: find.byType(Text),
          ),
        ))
          t.data,
      ];
      expect(labels, ['Report', 'Block', 'Share']);
    });

    testWidgets('your own profile: Share only, Edit profile stays', (
      tester,
    ) async {
      final posts = FakeUserPostRepository();
      final vm = profile(mine: true, posts: posts);
      await pumpInApp(
        tester,
        providers(PlayerProfileScreen(viewModel: vm), posts: posts),
        height: 900,
      );
      expect(find.text('Edit profile'), findsOneWidget);
      await openMenu(tester);
      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Report'), findsNothing);
      expect(find.text('Block'), findsNothing);
    });

    testWidgets('Share hands the profile link to the share sheet', (
      tester,
    ) async {
      final posts = FakeUserPostRepository();
      final vm = profile(mine: false, posts: posts);
      Uri? shared;
      await pumpInApp(
        tester,
        providers(
          PlayerProfileScreen(
            viewModel: vm,
            share: (_, _, l) async => shared = l,
          ),
          posts: posts,
        ),
        height: 900,
      );
      await openMenu(tester);
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();
      expect(shared, InviteLinks.player('p2'));
      expect(shared.toString(), endsWith('/players/p2'));
    });

    for (final (item, shows) in [
      ('Report', 'Report this profile'),
      ('Block', 'Block Jamie Carter?'),
    ]) {
      testWidgets('$item opens its sheet or asks first', (tester) async {
        final posts = FakeUserPostRepository();
        final vm = profile(mine: false, posts: posts);
        await pumpInApp(
          tester,
          providers(PlayerProfileScreen(viewModel: vm), posts: posts),
          height: 900,
        );
        await openMenu(tester);
        await tester.tap(find.text(item));
        await tester.pumpAndSettle();
        expect(find.text(shows), findsOneWidget);
      });
    }

    testWidgets('meets accessibility guidelines and 200% text', (tester) async {
      final posts = FakeUserPostRepository();
      final vm = profile(mine: false, posts: posts);
      final screen = providers(
        PlayerProfileScreen(viewModel: vm),
        posts: posts,
      );
      await pumpInApp(tester, screen, height: 900);
      await expectAccessible(tester);
      await expectNoOverflowWithLargeText(tester, screen, height: 900);
    });

    testWidgets('golden: menu open', (tester) async {
      final posts = FakeUserPostRepository();
      final vm = profile(mine: false, posts: posts);
      await loadAppFonts(tester);
      for (final theme in GoldenTheme.values) {
        final key = UniqueKey();
        await pumpInApp(
          tester,
          providers(PlayerProfileScreen(viewModel: vm), posts: posts),
          theme: theme,
          height: 900,
          boundaryKey: key,
        );
        await tester.tap(find.byTooltip('More options'));
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/q6_profile_menu.${theme.name}.360.png'),
        );
        // Close the popup before the next theme.
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();
      }
    }, skip: goldenSkip != null);
  });

  group('profile Media tab', () {
    Future<PlayerProfileViewModel> open(
      WidgetTester tester,
      FakeUserPostRepository posts, {
      bool mine = false,
      GoldenTheme theme = GoldenTheme.light,
      double textScale = 1,
      Key? boundaryKey,
      GoRouter? router,
    }) async {
      final vm = profile(mine: mine, posts: posts);
      await pumpInApp(
        tester,
        providers(PlayerProfileScreen(viewModel: vm), posts: posts),
        height: 900,
        theme: theme,
        textScale: textScale,
        boundaryKey: boundaryKey,
      );
      final tab = find.descendant(
        of: find.byType(Scrollable).first,
        matching: find.text('Media'),
      );
      await tester.ensureVisible(tab.first);
      await tester.tap(tab.first);
      await tester.pumpAndSettle();
      return vm;
    }

    testWidgets('lists only posts with photos, as thumbnails', (tester) async {
      final posts = FakeUserPostRepository()
        ..posts.addAll([
          post('a', 'p2', images: [photo]),
          post('b', 'p2'),
          post('c', 'p2', images: [photo, photo2]),
        ]);
      await open(tester, posts);
      expect(thumbs, findsNWidgets(3));
      expect(find.text('No photos or videos yet.'), findsNothing);
      expect(find.text('Post b'), findsNothing);
    });

    testWidgets('empty state', (tester) async {
      final posts = FakeUserPostRepository()..posts.add(post('b', 'p2'));
      await open(tester, posts);
      expect(find.text('No photos or videos yet.'), findsOneWidget);
    });

    testWidgets("a private post stays out of someone else's Media", (
      tester,
    ) async {
      final posts = FakeUserPostRepository()
        ..posts.add(
          UserPost(
            id: 'x',
            authorId: 'p2',
            authorName: 'Jamie Carter',
            body: 'private',
            images: const [photo],
            isPrivate: true,
            createdAt: DateTime(2026, 11, 20),
          ),
        );
      await open(tester, posts);
      // Same query as the Posts tab: a private post isn't fetched for a
      // stranger, so there is nothing to show.
      expect(find.text('No photos or videos yet.'), findsOneWidget);
    });

    testWidgets('a thumbnail opens its post', (tester) async {
      final posts = FakeUserPostRepository()
        ..posts.add(post('a', 'p2', images: [photo]));
      final vm = profile(mine: false, posts: posts);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) =>
                providers(PlayerProfileScreen(viewModel: vm), posts: posts),
          ),
        ],
        errorBuilder: (_, state) => Text('Went to ${state.uri.path}'),
      );
      // Real fonts, as on a phone: with the wide test font the Media tab
      // sits past the 360 px edge (and it only passed on Windows when an
      // earlier golden had loaded the fonts).
      await loadAppFonts(tester);
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Media'));
      await tester.pumpAndSettle();
      await tester.tap(thumbs);
      await tester.pumpAndSettle();
      expect(find.text('Went to ${Routes.post('a')}'), findsOneWidget);
    });

    testWidgets('meets accessibility guidelines and 200% text', (tester) async {
      final posts = FakeUserPostRepository()
        ..posts.add(post('a', 'p2', images: [photo]));
      await open(tester, posts);
      await expectAccessible(tester);
      await open(tester, posts, textScale: 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('golden: media tab', (tester) async {
      final posts = FakeUserPostRepository()
        ..posts.addAll([
          for (var i = 0; i < 5; i++) post('p$i', 'p2', images: [photo]),
        ]);
      await loadAppFonts(tester);
      for (final theme in GoldenTheme.values) {
        final key = UniqueKey();
        await open(tester, posts, theme: theme, boundaryKey: key);
        await expectLater(
          find.byKey(key),
          matchesGoldenFile('goldens/q6_profile_media.${theme.name}.360.png'),
        );
      }
    }, skip: goldenSkip != null);
  });
}
