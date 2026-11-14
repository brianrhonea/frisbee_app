import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../data/repositories/auth/auth_repository.dart';
import '../data/repositories/personal/personal_repository.dart';
import '../ui/browse/view_models/browse_search_viewmodel.dart';
import '../ui/browse/view_models/community_feed_viewmodel.dart';
import '../ui/browse/view_models/public_profile_viewmodel.dart';
import '../ui/browse/view_models/public_team_viewmodel.dart';
import '../ui/browse/view_models/upcoming_events_viewmodel.dart';
import '../ui/browse/widgets/browse_search_screen.dart';
import '../ui/browse/widgets/community_feed_screen.dart';
import '../ui/browse/widgets/public_profile_screen.dart';
import '../ui/browse/widgets/public_team_screen.dart';
import '../ui/browse/widgets/upcoming_events_screen.dart';
import '../ui/core/ui/status_views.dart';
import '../ui/core/ui/view_model_host.dart';
import '../ui/web/view_models/web_shell_viewmodel.dart';
import '../ui/web/widgets/get_the_app_screen.dart';
import '../ui/web/widgets/web_shell.dart';
import 'route_builders.dart';
import 'router.dart' show splashPath;
import 'routes.dart';
import 'tournament_routes.dart';

/// Paths only members open; visitors are sent to sign in first.
/// Tournaments have no public `browse` pages yet.
const _membersOnly = [
  Routes.home,
  Routes.profile,
  Routes.postsPath,
  Routes.tournaments,
];

bool _isMembersOnly(String path) =>
    _membersOnly.any((p) => path == p || path.startsWith('$p/'));

const _authPages = {Routes.signIn, Routes.signUp};

/// The website's redirects. Visitors browse everything public; members-only
/// pages ask them to sign in and come back. Signing in returns to where
/// they were (`?from=`), else Home.
String? webRedirect(
  AuthRepository auth,
  Uri uri, {
  PersonalDetailsRepository? personal,
}) {
  final path = uri.path;
  final from = uri.queryParameters['from'];
  if (!auth.isReady) {
    if (path == splashPath) return null;
    return Uri(
      path: splashPath,
      queryParameters: {'from': uri.toString()},
    ).toString();
  }
  final landing = auth.isAuthenticated ? Routes.home : Routes.community;
  if (path == splashPath) return from ?? landing;
  if (path == '/') return landing;
  if (!auth.isAuthenticated) {
    if (!_isMembersOnly(path)) return null;
    return Uri(
      path: Routes.signIn,
      queryParameters: {'from': uri.toString()},
    ).toString();
  }
  // No username yet: pick one first, then carry on.
  if (auth.needsUsername) {
    if (path == Routes.chooseUsername) return null;
    final target = _authPages.contains(path) ? from : uri.toString();
    return Uri(
      path: Routes.chooseUsername,
      queryParameters: target == null ? null : {'from': target},
    ).toString();
  }
  // A new account without personal details (as the app's authRedirect).
  if (personal?.mustComplete ?? false) {
    if (path == Routes.finishSignUp) return null;
    final target = _authPages.contains(path) || path == Routes.chooseUsername
        ? from
        : uri.toString();
    return Uri(
      path: Routes.finishSignUp,
      queryParameters: target == null ? null : {'from': target},
    ).toString();
  }
  if (path == Routes.chooseUsername ||
      path == Routes.finishSignUp ||
      _authPages.contains(path)) {
    return from ?? Routes.home;
  }
  return null;
}

/// The website's router (lib/main_web.dart), laid out by [WebShell].
///
/// Everyone sees the community feed, Explore, Events, and player and team
/// pages. Members see the app's own screens for those (with liking,
/// following, joining…) plus their Home feed and profile; visitors see
/// read-only pages from the `browse` functions that ask them to join for
/// anything more. Other app paths show [GetTheAppScreen].
///
/// Paths match the app's (Routes), so links work in both.
GoRouter webRouter(
  AuthRepository auth, {
  PersonalDetailsRepository? personal,
  String? initialLocation,
}) {
  /// [member] for signed-in users, else [visitor].
  Widget either(Widget Function() member, Widget Function() visitor) =>
      auth.isAuthenticated ? member() : visitor();

  return GoRouter(
    initialLocation: initialLocation ?? '/',
    refreshListenable: Listenable.merge([auth, ?personal]),
    redirect: (_, state) => webRedirect(auth, state.uri, personal: personal),
    errorBuilder: (_, state) => _framed(state, const GetTheAppScreen()),
    routes: [
      GoRoute(
        path: splashPath,
        builder: (_, _) => const Scaffold(body: LoadingView()),
      ),
      GoRoute(path: '/', builder: (_, _) => const SizedBox.shrink()),
      GoRoute(path: Routes.signIn, builder: (_, _) => signInPage()),
      GoRoute(path: Routes.signUp, builder: (_, _) => signUpPage()),
      GoRoute(
        path: Routes.chooseUsername,
        builder: (_, _) => chooseUsernamePage(),
      ),
      GoRoute(
        path: Routes.finishSignUp,
        builder: (_, _) => personalDetailsPage(finishing: true),
      ),
      // Group links (InviteLinks): the group's page.
      GoRoute(
        path: '/g/:groupId',
        redirect: (_, state) => Routes.team(state.pathParameters['groupId']!),
      ),
      ShellRoute(
        builder: (_, state, child) => _framed(state, child),
        routes: [
          GoRoute(path: Routes.home, builder: (_, _) => homePage()),
          GoRoute(
            path: Routes.community,
            builder: (_, _) => ViewModelHost(
              create: (c) => CommunityFeedViewModel(
                browseRepository: c.read(),
                authRepository: c.read(),
              ),
              builder: (_, vm) => CommunityFeedScreen(viewModel: vm),
            ),
          ),
          GoRoute(
            path: Routes.explorePath,
            builder: (_, state) => either(
              () => explorePage(state),
              () => ViewModelHost(
                create: (c) =>
                    BrowseSearchViewModel(browseRepository: c.read()),
                builder: (_, vm) => BrowseSearchScreen(
                  viewModel: vm,
                  initialQuery: state.uri.queryParameters['q'] ?? '',
                ),
              ),
            ),
          ),
          GoRoute(
            path: Routes.upcomingEvents,
            builder: (_, _) => ViewModelHost(
              create: (c) =>
                  UpcomingEventsViewModel(browseRepository: c.read()),
              builder: (_, vm) => UpcomingEventsScreen(viewModel: vm),
            ),
          ),
          GoRoute(
            path: '/players/:uid',
            // Your own profile is /profile, as in the app.
            redirect: (_, state) =>
                state.pathParameters['uid'] == auth.currentUser?.uid
                ? Routes.profile
                : null,
            builder: (_, state) {
              final uid = state.pathParameters['uid']!;
              return either(
                () => playerPage(uid),
                () => ViewModelHost(
                  key: ValueKey('public-player-$uid'),
                  create: (c) => PublicProfileViewModel(
                    uid: uid,
                    browseRepository: c.read(),
                  ),
                  builder: (_, vm) => PublicProfileScreen(viewModel: vm),
                ),
              );
            },
          ),
          GoRoute(path: Routes.profile, builder: (_, _) => myProfilePage()),
          GoRoute(
            path: '${Routes.teams}/:teamId',
            builder: (_, state) {
              final id = state.pathParameters['teamId']!;
              return either(
                () => teamPage(state),
                () => ViewModelHost(
                  key: ValueKey('public-team-$id'),
                  create: (c) => PublicTeamViewModel(
                    teamId: id,
                    browseRepository: c.read(),
                  ),
                  builder: (_, vm) => PublicTeamScreen(viewModel: vm),
                ),
              );
            },
          ),
          GoRoute(
            path: '${Routes.postsPath}/:postId',
            builder: (_, state) => postPage(state),
          ),
          ...hostedTournamentRoutes(),
          // The app pushes teams over tournaments; on the web they're
          // ordinary pages.
          GoRoute(
            path: '${Routes.teamsOverPath}/:teamId',
            redirect: (_, state) => Uri(
              path: Routes.team(state.pathParameters['teamId']!),
              queryParameters: state.uri.queryParameters.isEmpty
                  ? null
                  : state.uri.queryParameters,
            ).toString(),
          ),
          GoRoute(
            path: getTheAppPath,
            builder: (_, _) => const GetTheAppScreen(appOnly: false),
          ),
        ],
      ),
    ],
  );
}

/// [child] in the website's frame.
Widget _framed(GoRouterState state, Widget child) => ViewModelHost(
  create: (c) =>
      WebShellViewModel(authRepository: c.read(), themeRepository: c.read()),
  builder: (_, vm) =>
      WebShell(viewModel: vm, location: state.uri.toString(), child: child),
);
