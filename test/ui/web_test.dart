import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/auth/auth_repository.dart';
import 'package:frisbee_app/data/repositories/profile/profile_repository.dart';
import 'package:frisbee_app/data/repositories/ranking/ranking_repository.dart';
import 'package:frisbee_app/data/repositories/team/team_repository.dart';
import 'package:frisbee_app/data/repositories/theme/theme_repository.dart';
import 'package:frisbee_app/data/repositories/tournament/tournament_repository.dart';
import 'package:frisbee_app/routing/routes.dart';
import 'package:frisbee_app/routing/web_router.dart';
import 'package:frisbee_app/ui/auth/widgets/sign_in_screen.dart';
import 'package:frisbee_app/ui/explore/widgets/explore_screen.dart';
import 'package:frisbee_app/ui/web/view_models/web_shell_viewmodel.dart';
import 'package:frisbee_app/ui/web/widgets/get_the_app_screen.dart';
import 'package:frisbee_app/ui/web/widgets/store_badges.dart';
import 'package:frisbee_app/ui/web/widgets/web_shell.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../testing/fakes.dart';

void main() {
  group('WebShellViewModel', () {
    test('picks light or dark and signs out', () async {
      final auth = FakeAuthRepository(user: testUser);
      final theme = FakeThemeRepository();
      final vm = WebShellViewModel(
        authRepository: auth,
        themeRepository: theme,
      );
      addTearDown(vm.dispose);
      expect(vm.userName, testUser.label);

      await vm.setDark.execute(true);
      expect(theme.themeMode, ThemeMode.dark);
      await vm.setDark.execute(false);
      expect(theme.themeMode, ThemeMode.light);

      await vm.signOut.execute();
      expect(auth.isAuthenticated, isFalse);
      expect(vm.user, isNull);
    });
  });

  test('top-bar links light up for their section', () {
    final explore = webNavLinks.first;
    final events = webNavLinks[1];
    expect(isWebNavLinkActive(explore, '/explore?q=cascades'), isTrue);
    expect(isWebNavLinkActive(explore, '/players/u2'), isTrue);
    expect(isWebNavLinkActive(explore, '/tournaments'), isFalse);
    expect(isWebNavLinkActive(events, '/tournaments/x1'), isTrue);
    expect(isWebNavLinkActive(events, '/tournamentsx'), isFalse);
  });

  group('web router', () {
    late FakeAuthRepository auth;
    late GoRouter router;

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
            Provider<TeamRepository>.value(value: FakeTeamRepository()),
            Provider<ProfileRepository>.value(value: FakeProfileRepository()),
            Provider<RankingRepository>.value(
              value: FakeRankingRepository(const []),
            ),
            Provider<TournamentRepository>.value(
              value: FakeTournamentRepository(const []),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
    }

    String location() =>
        router.routerDelegate.currentConfiguration.uri.toString();

    testWidgets('signed out, it asks to sign in', (tester) async {
      auth = FakeAuthRepository();
      await pump(tester, Routes.explorePath);
      expect(find.byType(SignInScreen), findsOneWidget);
      expect(find.byType(WebShell), findsNothing);
    });

    testWidgets('signed in, it opens Explore in the web frame', (tester) async {
      auth = FakeAuthRepository(user: testUser);
      await pump(tester, '/');
      expect(location(), Routes.explorePath);
      expect(find.byType(WebShell), findsOneWidget);
      expect(find.byType(ExploreScreen), findsOneWidget);
    });

    testWidgets('app-only pages offer the app instead', (tester) async {
      auth = FakeAuthRepository(user: testUser);
      await pump(tester, '/teams/t1/meetings');
      expect(find.byType(GetTheAppScreen), findsOneWidget);
      expect(find.text("That's in the Stall 10 app"), findsOneWidget);
      expect(find.byType(StoreBadges), findsOneWidget);
      // Still framed, so the way back is one click.
      expect(find.byType(WebShell), findsOneWidget);
    });

    testWidgets('the top bar searches and links to the downloads', (
      tester,
    ) async {
      auth = FakeAuthRepository(user: testUser);
      await pump(tester, '/messages');

      await tester.tap(find.text('Get the app'));
      await tester.pumpAndSettle();
      expect(location(), getTheAppPath);
      expect(find.text('Get Stall 10'), findsOneWidget);

      await tester.enterText(
        find.descendant(
          of: find.byType(WebShell),
          matching: find.byType(TextField),
        ),
        'cascades',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(location(), Routes.explore(query: 'cascades'));
      expect(find.byType(ExploreScreen), findsOneWidget);
    });

    testWidgets('on a phone the sections move into a menu', (tester) async {
      auth = FakeAuthRepository(user: testUser);
      await pump(tester, '/messages', size: const Size(390, 800));
      expect(find.text('Rankings'), findsNothing);

      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rankings'));
      await tester.pumpAndSettle();
      expect(location(), Routes.rankings);
    });
  });
}
