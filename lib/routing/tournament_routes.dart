import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../ui/core/ui/view_model_host.dart';
import '../ui/tournaments/view_models/hosted_tournament_form_viewmodel.dart';
import '../ui/tournaments/view_models/hosted_tournament_viewmodel.dart';
import '../ui/tournaments/view_models/hosted_tournaments_viewmodel.dart';
import '../ui/tournaments/view_models/player_signups_viewmodel.dart';
import '../ui/tournaments/view_models/live_draft_viewmodel.dart';
import '../ui/tournaments/view_models/team_draft_viewmodel.dart';
import '../ui/tournaments/widgets/hosted_tournament_form_screen.dart';
import '../ui/tournaments/widgets/hosted_tournament_screen.dart';
import '../ui/tournaments/widgets/hosted_tournaments_list.dart';
import '../ui/tournaments/widgets/live_draft_screen.dart';
import '../ui/tournaments/widgets/team_draft_screen.dart';
import 'routes.dart';

/// Hosted tournaments: finding them, hosting one, its page and editing
/// it. Shared by the app and the website's signed-in routes.
List<GoRoute> hostedTournamentRoutes() => [
  GoRoute(
    path: Routes.tournaments,
    builder: (_, _) => ViewModelHost(
      key: const ValueKey('find-tournaments'),
      create: (c) => HostedTournamentsViewModel(
        tournamentRepository: c.read(),
        authRepository: c.read(),
      ),
      builder: (_, vm) => FindTournamentsScreen(viewModel: vm),
    ),
    routes: [
      GoRoute(
        path: 'new',
        builder: (_, state) {
          final host = state.uri.queryParameters['host'] ?? '';
          return ViewModelHost(
            key: ValueKey('host-tournament-$host'),
            create: (c) => HostedTournamentFormViewModel(
              hostId: host,
              tournamentRepository: c.read(),
              teamRepository: c.read(),
              authRepository: c.read(),
            ),
            builder: (_, vm) => HostedTournamentFormScreen(viewModel: vm),
          );
        },
      ),
      GoRoute(
        path: ':tournamentId',
        builder: (_, state) {
          final id = state.pathParameters['tournamentId']!;
          return ViewModelHost(
            key: ValueKey('tournament-$id'),
            create: (c) => HostedTournamentViewModel(
              tournamentId: id,
              tournamentRepository: c.read(),
              teamRepository: c.read(),
              authRepository: c.read(),
              postRepository: c.read(),
              followRepository: c.read(),
              notificationRepository: c.read(),
            ),
            builder: (_, vm) => ViewModelHost(
              key: ValueKey('tournament-signups-$id'),
              create: (c) => PlayerSignupsViewModel(
                tournamentId: id,
                tournamentRepository: c.read(),
                authRepository: c.read(),
              ),
              builder: (_, signups) => HostedTournamentScreen(
                viewModel: vm,
                signups: signups,
                fallbackHostId: state.uri.queryParameters['host'],
              ),
            ),
          );
        },
        routes: [
          GoRoute(
            path: 'draft/:divisionId',
            builder: (_, state) {
              final id = state.pathParameters['tournamentId']!;
              final division = state.pathParameters['divisionId']!;
              return ViewModelHost(
                key: ValueKey('draft-$id-$division'),
                create: (c) => TeamDraftViewModel(
                  tournamentId: id,
                  divisionId: division,
                  tournamentRepository: c.read(),
                ),
                builder: (_, vm) => TeamDraftScreen(viewModel: vm),
              );
            },
          ),
          GoRoute(
            path: 'live-draft/:divisionId',
            builder: (_, state) {
              final id = state.pathParameters['tournamentId']!;
              final division = state.pathParameters['divisionId']!;
              return ViewModelHost(
                key: ValueKey('live-draft-$id-$division'),
                create: (c) => LiveDraftViewModel(
                  tournamentId: id,
                  divisionId: division,
                  tournamentRepository: c.read(),
                  teamRepository: c.read(),
                  authRepository: c.read(),
                ),
                builder: (_, vm) => LiveDraftScreen(viewModel: vm),
              );
            },
          ),
          GoRoute(
            path: 'edit',
            builder: (_, state) {
              final id = state.pathParameters['tournamentId']!;
              return ViewModelHost(
                key: ValueKey('edit-tournament-$id'),
                create: (c) => HostedTournamentFormViewModel(
                  tournamentId: id,
                  tournamentRepository: c.read(),
                  teamRepository: c.read(),
                  authRepository: c.read(),
                ),
                builder: (_, vm) => HostedTournamentFormScreen(viewModel: vm),
              );
            },
          ),
        ],
      ),
    ],
  ),
];
