import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../data/repositories/auth/auth_repository.dart';
import '../ui/core/ui/status_views.dart';
import '../ui/core/ui/view_model_host.dart';
import '../ui/web/view_models/web_shell_viewmodel.dart';
import '../ui/web/widgets/get_the_app_screen.dart';
import '../ui/web/widgets/web_shell.dart';
import 'route_builders.dart';
import 'router.dart' show authRedirect, splashPath;
import 'routes.dart';

/// The website's router (lib/main_web.dart): sign-in, then Explore, player
/// and team pages, events, rankings and the user's profile, framed by
/// [WebShell]. Paths the app has but the website doesn't (team sections,
/// messages, meetings…) show [GetTheAppScreen].
///
/// Paths match the app's (Routes), so links work in both.
GoRouter webRouter(AuthRepository auth, {String? initialLocation}) => GoRouter(
  initialLocation: initialLocation ?? Routes.explorePath,
  refreshListenable: auth,
  redirect: (_, state) =>
      authRedirect(auth, state.uri, home: Routes.explorePath),
  errorBuilder: (_, state) => _framed(state, const GetTheAppScreen()),
  routes: [
    GoRoute(
      path: splashPath,
      builder: (_, _) => const Scaffold(body: LoadingView()),
    ),
    GoRoute(path: '/', redirect: (_, _) => Routes.explorePath),
    GoRoute(path: Routes.home, redirect: (_, _) => Routes.explorePath),
    GoRoute(path: Routes.signIn, builder: (_, _) => signInPage()),
    GoRoute(path: Routes.signUp, builder: (_, _) => signUpPage()),
    GoRoute(
      path: Routes.chooseUsername,
      builder: (_, _) => chooseUsernamePage(),
    ),
    // Group links (InviteLinks): the group's page.
    GoRoute(
      path: '/g/:groupId',
      redirect: (_, state) => Routes.team(state.pathParameters['groupId']!),
    ),
    ShellRoute(
      builder: (_, state, child) => _framed(state, child),
      routes: [
        GoRoute(
          path: Routes.explorePath,
          builder: (_, state) => explorePage(state),
        ),
        GoRoute(
          path: '/players/:uid',
          // Your own profile is /profile, as in the app.
          redirect: (_, state) =>
              state.pathParameters['uid'] == auth.currentUser?.uid
              ? Routes.profile
              : null,
          builder: (_, state) => playerPage(state.pathParameters['uid']!),
        ),
        GoRoute(path: Routes.profile, builder: (_, _) => myProfilePage()),
        GoRoute(
          path: '${Routes.teams}/:teamId',
          builder: (_, state) => teamPage(state),
        ),
        GoRoute(
          path: Routes.tournaments,
          builder: (_, _) => eventsPage(),
          routes: [
            GoRoute(
              path: ':id',
              builder: (_, state) =>
                  tournamentPage(state.pathParameters['id']!),
            ),
          ],
        ),
        GoRoute(
          path: Routes.rankings,
          builder: (_, _) => rankingsPage(),
          routes: [
            GoRoute(path: 'team', builder: (_, state) => usauTeamPage(state)),
          ],
        ),
        GoRoute(
          path: getTheAppPath,
          builder: (_, _) => const GetTheAppScreen(appOnly: false),
        ),
      ],
    ),
  ],
);

/// [child] in the website's frame.
Widget _framed(GoRouterState state, Widget child) => ViewModelHost(
  create: (c) =>
      WebShellViewModel(authRepository: c.read(), themeRepository: c.read()),
  builder: (_, vm) =>
      WebShell(viewModel: vm, location: state.uri.toString(), child: child),
);
