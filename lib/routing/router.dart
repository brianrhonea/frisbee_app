import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../data/repositories/auth/auth_repository.dart';
import '../ui/auth/view_models/sign_in_viewmodel.dart';
import '../ui/auth/view_models/sign_up_viewmodel.dart';
import '../ui/auth/widgets/sign_in_screen.dart';
import '../ui/auth/widgets/sign_up_screen.dart';
import '../ui/core/ui/adaptive_shell.dart';
import '../ui/core/ui/status_views.dart';
import '../ui/core/ui/view_model_host.dart';
import '../ui/home/view_models/home_viewmodel.dart';
import '../ui/home/widgets/home_screen.dart';
import '../ui/playbook/view_models/play_editor_viewmodel.dart';
import '../ui/playbook/widgets/play_editor_screen.dart';
import '../ui/profile/view_models/profile_viewmodel.dart';
import '../ui/profile/widgets/profile_screen.dart';
import '../ui/rankings/view_models/rankings_viewmodel.dart';
import '../ui/rankings/view_models/usau_team_viewmodel.dart';
import '../ui/rankings/widgets/rankings_screen.dart';
import '../ui/rankings/widgets/usau_team_screen.dart';
import '../ui/teams/view_models/create_team_viewmodel.dart';
import '../ui/teams/view_models/team_detail_viewmodel.dart';
import '../ui/teams/view_models/teams_viewmodel.dart';
import '../ui/teams/widgets/create_team_screen.dart';
import '../ui/teams/widgets/team_detail_screen.dart';
import '../ui/teams/widgets/teams_screen.dart';
import '../ui/tournaments/view_models/tournaments_viewmodel.dart';
import '../ui/tournaments/widgets/tournament_detail_screen.dart';
import '../ui/tournaments/widgets/tournaments_screen.dart';
import 'routes.dart';

const _splash = '/splash';
const _publicRoutes = {Routes.signIn, Routes.signUp};

final _rootKey = GlobalKey<NavigatorState>();

GoRouter router(AuthRepository auth) => GoRouter(
  navigatorKey: _rootKey,
  initialLocation: Routes.home,
  refreshListenable: auth,
  redirect: (context, state) => authRedirect(auth, state.uri),
  routes: [
    GoRoute(
      path: _splash,
      builder: (_, _) => const Scaffold(body: LoadingView()),
    ),
    GoRoute(
      path: Routes.signIn,
      builder: (context, _) => ViewModelHost(
        create: (c) => SignInViewModel(authRepository: c.read()),
        builder: (_, vm) => SignInScreen(viewModel: vm),
      ),
    ),
    GoRoute(
      path: Routes.signUp,
      builder: (context, _) => ViewModelHost(
        create: (c) => SignUpViewModel(authRepository: c.read()),
        builder: (_, vm) => SignUpScreen(viewModel: vm),
      ),
    ),
    StatefulShellRoute.indexedStack(
      builder: (_, _, shell) => AdaptiveShell(navigationShell: shell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Routes.home,
              builder: (_, _) => ViewModelHost(
                create: (c) => HomeViewModel(
                  authRepository: c.read(),
                  teamRepository: c.read(),
                  tournamentRepository: c.read(),
                ),
                builder: (_, vm) => HomeScreen(viewModel: vm),
              ),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Routes.teams,
              builder: (_, _) => ViewModelHost(
                create: (c) => TeamsViewModel(
                  teamRepository: c.read(),
                  authRepository: c.read(),
                ),
                builder: (_, vm) => TeamsScreen(viewModel: vm),
              ),
              routes: [
                GoRoute(
                  path: 'new',
                  builder: (_, _) => ViewModelHost(
                    create: (c) => CreateTeamViewModel(
                      teamRepository: c.read(),
                      authRepository: c.read(),
                    ),
                    builder: (_, vm) => CreateTeamScreen(viewModel: vm),
                  ),
                ),
                GoRoute(
                  path: ':teamId',
                  builder: (_, state) {
                    final teamId = state.pathParameters['teamId']!;
                    return ViewModelHost(
                      key: ValueKey('team-$teamId'),
                      create: (c) => TeamDetailViewModel(
                        teamId: teamId,
                        teamRepository: c.read(),
                        playRepository: c.read(),
                        authRepository: c.read(),
                      ),
                      builder: (_, vm) => TeamDetailScreen(viewModel: vm),
                    );
                  },
                  routes: [
                    GoRoute(
                      path: 'plays/:playId',
                      parentNavigatorKey: _rootKey,
                      builder: (_, state) {
                        final teamId = state.pathParameters['teamId']!;
                        final playId = state.pathParameters['playId']!;
                        return ViewModelHost(
                          key: ValueKey('play-$teamId-$playId'),
                          create: (c) => PlayEditorViewModel(
                            teamId: teamId,
                            playId: playId == 'new' ? null : playId,
                            playRepository: c.read(),
                            teamRepository: c.read(),
                            authRepository: c.read(),
                          ),
                          builder: (_, vm) => PlayEditorScreen(viewModel: vm),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Routes.tournaments,
              builder: (_, _) => ViewModelHost(
                create: (c) =>
                    TournamentsViewModel(tournamentRepository: c.read()),
                builder: (_, vm) => TournamentsScreen(viewModel: vm),
              ),
              routes: [
                GoRoute(
                  path: ':id',
                  builder: (_, state) {
                    final id = state.pathParameters['id']!;
                    return ViewModelHost(
                      key: ValueKey('tournament-$id'),
                      create: (c) =>
                          TournamentsViewModel(tournamentRepository: c.read()),
                      builder: (_, vm) => TournamentDetailScreen(
                        viewModel: vm,
                        tournamentId: id,
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Routes.rankings,
              builder: (_, _) => ViewModelHost(
                create: (c) => RankingsViewModel(
                  rankingRepository: c.read(),
                  teamEloRepository: c.read(),
                ),
                builder: (_, vm) => RankingsScreen(viewModel: vm),
              ),
              routes: [
                GoRoute(
                  path: 'team',
                  builder: (_, state) {
                    final url = state.uri.queryParameters['url'] ?? '';
                    return ViewModelHost(
                      key: ValueKey('usau-team-$url'),
                      create: (c) => UsauTeamViewModel(
                        url: url,
                        name: state.uri.queryParameters['name'] ?? '',
                        usauTeamRepository: c.read(),
                      ),
                      builder: (_, vm) => UsauTeamScreen(viewModel: vm),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Routes.profile,
              builder: (_, _) => ViewModelHost(
                create: (c) => ProfileViewModel(authRepository: c.read()),
                builder: (_, vm) => ProfileScreen(viewModel: vm),
              ),
            ),
          ],
        ),
      ],
    ),
  ],
);

/// Sends signed-out users to sign-in (remembering where they were headed)
/// and signed-in users away from the auth screens.
String? authRedirect(AuthRepository auth, Uri uri) {
  final path = uri.path;
  final from = uri.queryParameters['from'];
  if (!auth.isReady) {
    if (path == _splash) return null;
    return Uri(
      path: _splash,
      queryParameters: {'from': uri.toString()},
    ).toString();
  }
  final public = _publicRoutes.contains(path);
  if (!auth.isAuthenticated) {
    if (public) return null;
    final target = path == _splash ? from : uri.toString();
    return Uri(
      path: Routes.signIn,
      queryParameters: target == null || target == Routes.home
          ? null
          : {'from': target},
    ).toString();
  }
  if (public || path == _splash) return from ?? Routes.home;
  return null;
}
