import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/providers/auth_provider.dart';
import '../features/auth/screens/login_screen.dart';
import '../features/rankings/screens/league_list_screen.dart';
import '../features/rankings/screens/league_detail_screen.dart';
import '../features/rankings/screens/team_detail_screen.dart';
import '../features/schedule/screens/schedule_screen.dart';
import '../features/schedule/screens/game_detail_screen.dart';
import '../features/pickups/screens/pickup_map_screen.dart';
import '../features/pickups/screens/pickup_detail_screen.dart';
import '../features/pickups/screens/create_pickup_screen.dart';
import '../features/teams/screens/my_teams_screen.dart';
import '../features/teams/screens/create_team_screen.dart';
import '../features/fitness/screens/fitness_home_screen.dart';
import '../features/fitness/screens/workout_log_screen.dart';
import '../features/fitness/screens/scheduler_screen.dart';
import '../features/fitness/screens/drill_library_screen.dart';
import '../features/profile/screens/profile_screen.dart';
import '../features/profile/screens/edit_profile_screen.dart';
import '../shared/widgets/shell_scaffold.dart';

// ── Route names (use constants to avoid typos) ────────────────
abstract final class Routes {
  static const login         = '/login';

  // Rankings
  static const rankings      = '/rankings';
  static const leagueDetail  = '/rankings/:leagueId';
  static const teamDetail    = '/rankings/:leagueId/teams/:teamId';

  // Schedule
  static const schedule      = '/schedule';
  static const gameDetail    = '/schedule/:gameId';

  // Pickups
  static const pickups       = '/pickups';
  static const pickupDetail  = '/pickups/:pickupId';
  static const createPickup  = '/pickups/create';

  // Teams
  static const myTeams       = '/teams';
  static const createTeam    = '/teams/create';

  // Fitness
  static const fitness       = '/fitness';
  static const workoutLog    = '/fitness/log';
  static const fitnessScheduler = '/fitness/scheduler';
  static const drillLibrary  = '/fitness/drills';

  // Profile
  static const profile       = '/profile';
  static const editProfile   = '/profile/edit';
}

// ── Provider ──────────────────────────────────────────────────
final routerProvider = Provider<GoRouter>((ref) {
  // Reactive redirect — listens to auth state
  final authNotifier = ValueNotifier<bool>(false);

  ref.listen<AsyncValue<bool>>(isAuthenticatedProvider, (_, next) {
    authNotifier.value = next.valueOrNull ?? false;
  });

  return GoRouter(
    initialLocation: Routes.rankings,
    refreshListenable: authNotifier,
    debugLogDiagnostics: true,
    redirect: (context, state) {
      final isAuth = authNotifier.value;
      final isOnLogin = state.matchedLocation == Routes.login;

      // Protected routes — redirect to login if not authenticated
      final protectedPrefixes = [
        Routes.myTeams,
        Routes.fitness,
        Routes.profile,
        Routes.createPickup,
      ];
      final needsAuth = protectedPrefixes.any(
        (p) => state.matchedLocation.startsWith(p),
      );

      if (needsAuth && !isAuth) return Routes.login;
      if (isOnLogin && isAuth) return Routes.rankings;

      return null; // no redirect
    },
    routes: [
      // ── Auth ──────────────────────────────────────────────
      GoRoute(
        path: Routes.login,
        name: 'login',
        builder: (_, __) => const LoginScreen(),
      ),

      // ── Shell (bottom nav) ────────────────────────────────
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => ShellScaffold(
          navigationShell: navigationShell,
        ),
        branches: [
          // Rankings branch
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.rankings,
              name: 'rankings',
              builder: (_, __) => const LeagueListScreen(),
              routes: [
                GoRoute(
                  path: ':leagueId',
                  name: 'leagueDetail',
                  builder: (_, state) => LeagueDetailScreen(
                    leagueId: state.pathParameters['leagueId']!,
                  ),
                  routes: [
                    GoRoute(
                      path: 'teams/:teamId',
                      name: 'teamDetail',
                      builder: (_, state) => TeamDetailScreen(
                        leagueId: state.pathParameters['leagueId']!,
                        teamId: state.pathParameters['teamId']!,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ]),

          // Schedule branch
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.schedule,
              name: 'schedule',
              builder: (_, __) => const ScheduleScreen(),
              routes: [
                GoRoute(
                  path: ':gameId',
                  name: 'gameDetail',
                  builder: (_, state) => GameDetailScreen(
                    gameId: state.pathParameters['gameId']!,
                  ),
                ),
              ],
            ),
          ]),

          // Pickups branch
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.pickups,
              name: 'pickups',
              builder: (_, __) => const PickupMapScreen(),
              routes: [
                GoRoute(
                  path: 'create',
                  name: 'createPickup',
                  builder: (_, __) => const CreatePickupScreen(),
                ),
                GoRoute(
                  path: ':pickupId',
                  name: 'pickupDetail',
                  builder: (_, state) => PickupDetailScreen(
                    pickupId: state.pathParameters['pickupId']!,
                  ),
                ),
              ],
            ),
          ]),

          // Teams branch
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.myTeams,
              name: 'myTeams',
              builder: (_, __) => const MyTeamsScreen(),
              routes: [
                GoRoute(
                  path: 'create',
                  name: 'createTeam',
                  builder: (_, __) => const CreateTeamScreen(),
                ),
              ],
            ),
          ]),

          // Fitness branch
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.fitness,
              name: 'fitness',
              builder: (_, __) => const FitnessHomeScreen(),
              routes: [
                GoRoute(
                  path: 'log',
                  name: 'workoutLog',
                  builder: (_, __) => const WorkoutLogScreen(),
                ),
                GoRoute(
                  path: 'scheduler',
                  name: 'fitnessScheduler',
                  builder: (_, __) => const SchedulerScreen(),
                ),
                GoRoute(
                  path: 'drills',
                  name: 'drillLibrary',
                  builder: (_, __) => const DrillLibraryScreen(),
                ),
              ],
            ),
          ]),

          // Profile branch
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.profile,
              name: 'profile',
              builder: (_, __) => const ProfileScreen(),
              routes: [
                GoRoute(
                  path: 'edit',
                  name: 'editProfile',
                  builder: (_, __) => const EditProfileScreen(),
                ),
              ],
            ),
          ]),
        ],
      ),
    ],

    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.disc_full_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'Page not found',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            TextButton(
              onPressed: () => context.go(Routes.rankings),
              child: const Text('Go home'),
            ),
          ],
        ),
      ),
    ),
  );
});