import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../data/repositories/auth/auth_repository.dart';
import '../data/repositories/meeting/meeting_repository.dart';
import '../ui/auth/view_models/sign_in_viewmodel.dart';
import '../ui/auth/view_models/sign_up_viewmodel.dart';
import '../ui/auth/widgets/sign_in_screen.dart';
import '../ui/auth/widgets/sign_up_screen.dart';
import '../ui/chat/view_models/chat_room_settings_viewmodel.dart';
import '../ui/chat/view_models/chat_room_viewmodel.dart';
import '../ui/chat/widgets/chat_layout.dart';
import '../ui/chat/widgets/chat_room_screen.dart';
import '../ui/chat/widgets/chat_room_settings_screen.dart';
import '../ui/core/ui/adaptive_shell.dart';
import '../ui/meetings/view_models/meeting_detail_viewmodel.dart';
import '../ui/meetings/view_models/meeting_editor_viewmodel.dart';
import '../ui/meetings/view_models/meeting_room_viewmodel.dart';
import '../ui/meetings/widgets/meeting_detail_screen.dart';
import '../ui/meetings/widgets/meeting_editor_screen.dart';
import '../ui/meetings/widgets/meeting_room_screen.dart';
import '../ui/messages/view_models/direct_chat_viewmodel.dart';
import '../ui/messages/view_models/inbox_viewmodel.dart';
import '../ui/messages/view_models/people_search_viewmodel.dart';
import '../ui/messages/widgets/direct_chat_screen.dart';
import '../ui/messages/widgets/inbox_screen.dart';
import '../ui/messages/widgets/people_search_screen.dart';
import '../ui/core/ui/status_views.dart';
import '../ui/core/ui/view_model_host.dart';
import '../ui/events/widgets/events_screen.dart';
import '../ui/home/view_models/home_viewmodel.dart';
import '../ui/home/widgets/home_screen.dart';
import '../ui/playbook/view_models/play_editor_viewmodel.dart';
import '../ui/playbook/widgets/play_editor_screen.dart';
import '../ui/notifications/view_models/notification_settings_viewmodel.dart';
import '../ui/notifications/view_models/notifications_viewmodel.dart';
import '../ui/notifications/widgets/notification_settings_screen.dart';
import '../ui/notifications/widgets/notifications_screen.dart';
import '../ui/profile/view_models/profile_viewmodel.dart';
import '../ui/profile/widgets/profile_screen.dart';
import '../ui/rankings/view_models/rankings_viewmodel.dart';
import '../ui/rankings/view_models/usau_team_viewmodel.dart';
import '../ui/rankings/widgets/rankings_screen.dart';
import '../ui/rankings/widgets/usau_team_screen.dart';
import '../ui/schedule/view_models/event_detail_viewmodel.dart';
import '../ui/schedule/view_models/event_editor_viewmodel.dart';
import '../ui/schedule/view_models/schedule_viewmodel.dart';
import '../ui/schedule/view_models/my_event_detail_viewmodel.dart';
import '../ui/schedule/widgets/event_detail_screen.dart';
import '../ui/schedule/widgets/event_editor_screen.dart';
import '../ui/schedule/widgets/schedule_screen.dart';
import '../ui/schedule/widgets/my_event_detail_screen.dart';
import '../ui/stats/view_models/game_tracker_viewmodel.dart';
import '../ui/stats/view_models/stats_viewmodel.dart';
import '../ui/stats/view_models/tournament_viewmodel.dart';
import '../ui/stats/widgets/game_screen.dart';
import '../ui/stats/widgets/stats_tab.dart';
import '../ui/stats/widgets/tournament_screen.dart';
import '../ui/teams/view_models/create_team_viewmodel.dart';
import '../ui/teams/view_models/team_detail_viewmodel.dart';
import '../ui/teams/view_models/team_home_viewmodel.dart';
import '../ui/teams/view_models/team_search_viewmodel.dart';
import '../ui/teams/view_models/teams_viewmodel.dart';
import '../ui/teams/view_models/usau_team_search_viewmodel.dart';
import '../ui/teams/widgets/create_team_screen.dart';
import '../ui/teams/view_models/usau_roster_viewmodel.dart';
import '../ui/teams/widgets/team_home_screen.dart';
import '../ui/teams/widgets/team_search_screen.dart';
import '../ui/teams/widgets/team_section_screen.dart';
import '../ui/teams/widgets/usau_roster_screen.dart';
import '../ui/teams/widgets/teams_screen.dart';
import '../ui/teams/widgets/usau_team_search_screen.dart';
import '../ui/tournaments/view_models/tournament_detail_viewmodel.dart';
import '../ui/tournaments/view_models/tournaments_viewmodel.dart';
import '../ui/tournaments/widgets/tournament_detail_screen.dart';
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
    // Opened from the avatar on Home, over the shell.
    GoRoute(
      path: Routes.profile,
      builder: (_, _) => ViewModelHost(
        create: (c) => ProfileViewModel(
          authRepository: c.read(),
          themeRepository: c.read(),
          notificationRepository: c.read(),
        ),
        builder: (_, vm) => ProfileScreen(viewModel: vm),
      ),
    ),
    // Opened from the bell on Home, over the shell.
    GoRoute(
      path: Routes.notifications,
      builder: (_, _) => ViewModelHost(
        create: (c) => NotificationsViewModel(
          notificationRepository: c.read(),
          authRepository: c.read(),
        ),
        builder: (_, vm) => NotificationsScreen(viewModel: vm),
      ),
      routes: [
        GoRoute(
          path: 'settings',
          builder: (_, _) => ViewModelHost(
            create: (c) => NotificationSettingsViewModel(
              notificationRepository: c.read(),
              teamRepository: c.read(),
              authRepository: c.read(),
            ),
            builder: (_, vm) => NotificationSettingsScreen(viewModel: vm),
          ),
        ),
      ],
    ),
    // Team events, full screen over the shell (see Routes.teamEventsPath).
    GoRoute(
      path: '${Routes.teamEventsPath}/:teamId',
      redirect: (_, state) {
        final teamId = state.pathParameters['teamId']!;
        final base = '${Routes.teamEventsPath}/$teamId';
        return state.uri.path == base ? Routes.team(teamId) : null;
      },
      routes: [
        GoRoute(
          path: 'new',
          builder: (_, state) {
            final teamId = state.pathParameters['teamId']!;
            final date = state.uri.queryParameters['date'];
            return ViewModelHost(
              key: ValueKey('new-event-$teamId-$date'),
              create: (c) => EventEditorViewModel(
                teamId: teamId,
                eventId: null,
                initialDay: date == null ? null : DateTime.tryParse(date),
                eventRepository: c.read(),
                teamRepository: c.read(),
                authRepository: c.read(),
              ),
              builder: (_, vm) => EventEditorScreen(viewModel: vm),
            );
          },
        ),
        GoRoute(
          path: ':eventId',
          builder: (_, state) {
            final teamId = state.pathParameters['teamId']!;
            final eventId = state.pathParameters['eventId']!;
            return ViewModelHost(
              key: ValueKey('event-$teamId-$eventId'),
              create: (c) => EventDetailViewModel(
                teamId: teamId,
                eventId: eventId,
                eventRepository: c.read(),
                teamRepository: c.read(),
                authRepository: c.read(),
              ),
              builder: (_, vm) => EventDetailScreen(viewModel: vm),
            );
          },
          routes: [
            GoRoute(
              path: 'edit',
              builder: (_, state) {
                final teamId = state.pathParameters['teamId']!;
                final eventId = state.pathParameters['eventId']!;
                return ViewModelHost(
                  key: ValueKey('edit-event-$teamId-$eventId'),
                  create: (c) => EventEditorViewModel(
                    teamId: teamId,
                    eventId: eventId,
                    eventRepository: c.read(),
                    teamRepository: c.read(),
                    authRepository: c.read(),
                  ),
                  builder: (_, vm) => EventEditorScreen(viewModel: vm),
                );
              },
            ),
          ],
        ),
      ],
    ),
    // Team meetings, full screen over the shell (see
    // Routes.teamMeetingsPath).
    GoRoute(
      path: '${Routes.teamMeetingsPath}/:teamId',
      redirect: (_, state) {
        final teamId = state.pathParameters['teamId']!;
        final base = '${Routes.teamMeetingsPath}/$teamId';
        return state.uri.path == base ? Routes.teamEvents(teamId) : null;
      },
      routes: [
        GoRoute(
          path: 'new',
          builder: (_, state) {
            final teamId = state.pathParameters['teamId']!;
            final date = state.uri.queryParameters['date'];
            return ViewModelHost(
              key: ValueKey('new-meeting-$teamId-$date'),
              create: (c) => MeetingEditorViewModel(
                teamId: teamId,
                meetingId: null,
                initialDay: date == null ? null : DateTime.tryParse(date),
                meetingRepository: c.read(),
                teamRepository: c.read(),
                authRepository: c.read(),
              ),
              builder: (_, vm) => MeetingEditorScreen(viewModel: vm),
            );
          },
        ),
        GoRoute(
          path: ':meetingId',
          builder: (_, state) {
            final teamId = state.pathParameters['teamId']!;
            final meetingId = state.pathParameters['meetingId']!;
            return ViewModelHost(
              key: ValueKey('meeting-$teamId-$meetingId'),
              create: (c) => MeetingDetailViewModel(
                teamId: teamId,
                meetingId: meetingId,
                meetingRepository: c.read(),
                teamRepository: c.read(),
                authRepository: c.read(),
              ),
              builder: (_, vm) => MeetingDetailScreen(viewModel: vm),
            );
          },
          routes: [
            GoRoute(
              path: 'edit',
              builder: (_, state) {
                final teamId = state.pathParameters['teamId']!;
                final meetingId = state.pathParameters['meetingId']!;
                return ViewModelHost(
                  key: ValueKey('edit-meeting-$teamId-$meetingId'),
                  create: (c) => MeetingEditorViewModel(
                    teamId: teamId,
                    meetingId: meetingId,
                    meetingRepository: c.read(),
                    teamRepository: c.read(),
                    authRepository: c.read(),
                  ),
                  builder: (_, vm) => MeetingEditorScreen(viewModel: vm),
                );
              },
            ),
            GoRoute(
              path: 'room',
              builder: (_, state) {
                final teamId = state.pathParameters['teamId']!;
                final meetingId = state.pathParameters['meetingId']!;
                return ViewModelHost(
                  key: ValueKey('meeting-room-$teamId-$meetingId'),
                  create: (c) => MeetingRoomViewModel(
                    teamId: teamId,
                    meetingId: meetingId,
                    meetingRepository: c.read(),
                    teamRepository: c.read(),
                    authRepository: c.read(),
                    media: c.read(),
                    settingsRepository: c.read(),
                    filePicker: c.read(),
                    presence: c.read(),
                  ),
                  builder: (_, vm) => MeetingRoomScreen(viewModel: vm),
                );
              },
            ),
          ],
        ),
      ],
    ),
    // Direct messages, full screen over the shell (opened with push).
    GoRoute(
      path: Routes.messages,
      builder: (_, _) => ViewModelHost(
        create: (c) => InboxViewModel(
          directMessageRepository: c.read(),
          authRepository: c.read(),
        ),
        builder: (_, vm) => InboxScreen(viewModel: vm),
      ),
      routes: [
        GoRoute(
          path: 'new',
          builder: (_, _) => ViewModelHost(
            create: (c) => PeopleSearchViewModel(
              directMessageRepository: c.read(),
              authRepository: c.read(),
            ),
            builder: (_, vm) => PeopleSearchScreen(viewModel: vm),
          ),
        ),
        GoRoute(
          path: ':conversationId',
          pageBuilder: (_, state) {
            final id = state.pathParameters['conversationId']!;
            return chatPage(
              state.pageKey,
              ViewModelHost(
                key: ValueKey('dm-$id'),
                create: (c) => DirectChatViewModel(
                  conversationId: id,
                  directMessageRepository: c.read(),
                  authRepository: c.read(),
                  filePicker: c.read(),
                ),
                builder: (_, vm) => DirectChatScreen(viewModel: vm),
              ),
            );
          },
        ),
      ],
    ),
    // Personal schedule, full screen over the shell.
    GoRoute(
      path: Routes.myEventsPath,
      redirect: (_, state) =>
          state.uri.path == Routes.myEventsPath ? Routes.tournaments : null,
      routes: [
        GoRoute(
          path: 'new',
          builder: (_, state) {
            final date = state.uri.queryParameters['date'];
            return ViewModelHost(
              key: ValueKey('new-my-event-$date'),
              create: (c) => EventEditorViewModel(
                teamId: null,
                eventId: null,
                initialDay: date == null ? null : DateTime.tryParse(date),
                eventRepository: c.read(),
                teamRepository: c.read(),
                authRepository: c.read(),
              ),
              builder: (_, vm) => EventEditorScreen(viewModel: vm),
            );
          },
        ),
        GoRoute(
          path: ':eventId',
          builder: (_, state) {
            final eventId = state.pathParameters['eventId']!;
            return ViewModelHost(
              key: ValueKey('my-event-$eventId'),
              create: (c) => MyEventDetailViewModel(
                eventId: eventId,
                eventRepository: c.read(),
                authRepository: c.read(),
              ),
              builder: (_, vm) => MyEventDetailScreen(viewModel: vm),
            );
          },
          routes: [
            GoRoute(
              path: 'edit',
              builder: (_, state) {
                final eventId = state.pathParameters['eventId']!;
                return ViewModelHost(
                  key: ValueKey('edit-my-event-$eventId'),
                  create: (c) => EventEditorViewModel(
                    teamId: null,
                    eventId: eventId,
                    eventRepository: c.read(),
                    teamRepository: c.read(),
                    authRepository: c.read(),
                  ),
                  builder: (_, vm) => EventEditorScreen(viewModel: vm),
                );
              },
            ),
          ],
        ),
      ],
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
                  directMessageRepository: c.read(),
                  notificationRepository: c.read(),
                  teamRepository: c.read(),
                  playRepository: c.read(),
                  eventRepository: c.read(),
                  meetingRepository: c.read<MeetingRepository>(),
                  tournamentRepository: c.read(),
                  rankingRepository: c.read(),
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
                  path: 'search',
                  builder: (_, _) => ViewModelHost(
                    create: (c) => TeamSearchViewModel(
                      teamRepository: c.read(),
                      authRepository: c.read(),
                    ),
                    builder: (_, vm) => TeamSearchScreen(viewModel: vm),
                  ),
                  routes: [
                    GoRoute(
                      path: 'usau',
                      builder: (_, _) => ViewModelHost(
                        create: (c) => UsauTeamSearchViewModel(
                          rankingRepository: c.read(),
                        ),
                        builder: (_, vm) => UsauTeamSearchScreen(viewModel: vm),
                      ),
                      routes: [
                        GoRoute(
                          path: 'team',
                          builder: (_, state) => _usauTeam(state),
                        ),
                      ],
                    ),
                  ],
                ),
                GoRoute(
                  path: ':teamId',
                  // Teams had tabs before they had a home page; old links
                  // (e.g. in the notification feed) name one with ?tab=.
                  redirect: (_, state) {
                    if (state.uri.pathSegments.length != 2) return null;
                    final tab = state.uri.queryParameters['tab'];
                    if (tab == null) return null;
                    final teamId = state.pathParameters['teamId']!;
                    return TeamSection.fromLegacyTab(tab)?.route(teamId) ??
                        Routes.team(teamId);
                  },
                  builder: (_, state) {
                    final teamId = state.pathParameters['teamId']!;
                    return ViewModelHost(
                      key: ValueKey('team-$teamId'),
                      create: (c) => TeamHomeViewModel(
                        teamId: teamId,
                        teamRepository: c.read(),
                        eventRepository: c.read(),
                        teamPostRepository: c.read(),
                        authRepository: c.read(),
                        filePicker: c.read(),
                      ),
                      builder: (_, vm) => TeamHomeScreen(viewModel: vm),
                    );
                  },
                  routes: [
                    for (final section in TeamSection.values)
                      GoRoute(
                        path: section.path,
                        builder: (_, state) => _teamSection(state, section),
                      ),
                    GoRoute(
                      path: 'chats/new',
                      parentNavigatorKey: _rootKey,
                      builder: (_, state) => _chatRoomSettings(state, null),
                    ),
                    GoRoute(
                      path: 'chats/:roomId',
                      parentNavigatorKey: _rootKey,
                      pageBuilder: (_, state) {
                        final teamId = state.pathParameters['teamId']!;
                        final roomId = state.pathParameters['roomId']!;
                        return chatPage(
                          state.pageKey,
                          ViewModelHost(
                            key: ValueKey('chat-$teamId-$roomId'),
                            create: (c) => ChatRoomViewModel(
                              teamId: teamId,
                              roomId: roomId,
                              teamRepository: c.read(),
                              chatRepository: c.read(),
                              notificationRepository: c.read(),
                              authRepository: c.read(),
                              filePicker: c.read(),
                            ),
                            builder: (_, vm) => ChatRoomScreen(viewModel: vm),
                          ),
                        );
                      },
                      routes: [
                        GoRoute(
                          path: 'settings',
                          parentNavigatorKey: _rootKey,
                          builder: (_, state) => _chatRoomSettings(
                            state,
                            state.pathParameters['roomId'],
                          ),
                        ),
                      ],
                    ),
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
                    GoRoute(
                      path: 'usau-roster',
                      parentNavigatorKey: _rootKey,
                      builder: (_, state) {
                        final teamId = state.pathParameters['teamId']!;
                        return ViewModelHost(
                          key: ValueKey('usau-roster-$teamId'),
                          create: (c) => UsauRosterViewModel(
                            teamId: teamId,
                            teamRepository: c.read(),
                            usauTeamRepository: c.read(),
                            rankingRepository: c.read(),
                            authRepository: c.read(),
                          ),
                          builder: (_, vm) => UsauRosterScreen(viewModel: vm),
                        );
                      },
                    ),
                    GoRoute(
                      path: 'stats/season',
                      parentNavigatorKey: _rootKey,
                      builder: (_, state) {
                        final teamId = state.pathParameters['teamId']!;
                        return ViewModelHost(
                          key: ValueKey('season-stats-$teamId'),
                          create: (c) => StatsViewModel(
                            teamId: teamId,
                            statsRepository: c.read(),
                            eventRepository: c.read(),
                            teamRepository: c.read(),
                            authRepository: c.read(),
                          ),
                          builder: (_, vm) => SeasonStatsScreen(viewModel: vm),
                        );
                      },
                    ),
                    GoRoute(
                      path: 'stats/tournaments/:tournamentId',
                      parentNavigatorKey: _rootKey,
                      builder: (_, state) {
                        final teamId = state.pathParameters['teamId']!;
                        final id = state.pathParameters['tournamentId']!;
                        return ViewModelHost(
                          key: ValueKey('stats-tournament-$teamId-$id'),
                          create: (c) => TournamentViewModel(
                            teamId: teamId,
                            tournamentId: id,
                            statsRepository: c.read(),
                            teamRepository: c.read(),
                            authRepository: c.read(),
                          ),
                          builder: (_, vm) => TournamentScreen(viewModel: vm),
                        );
                      },
                    ),
                    GoRoute(
                      path: 'stats/games/:gameId',
                      parentNavigatorKey: _rootKey,
                      builder: (_, state) {
                        final teamId = state.pathParameters['teamId']!;
                        final id = state.pathParameters['gameId']!;
                        return ViewModelHost(
                          key: ValueKey('stats-game-$teamId-$id'),
                          create: (c) => GameTrackerViewModel(
                            teamId: teamId,
                            gameId: id,
                            statsRepository: c.read(),
                            teamRepository: c.read(),
                            authRepository: c.read(),
                          ),
                          builder: (_, vm) => GameScreen(viewModel: vm),
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
              path: Routes.schedule,
              builder: (_, _) => ViewModelHost(
                create: (c) => ScheduleViewModel(
                  authRepository: c.read(),
                  teamRepository: c.read(),
                  eventRepository: c.read(),
                  meetingRepository: c.read<MeetingRepository>(),
                ),
                builder: (_, vm) => ScheduleScreen(viewModel: vm),
              ),
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
                builder: (_, vm) => EventsScreen(viewModel: vm),
              ),
              routes: [
                GoRoute(
                  path: ':id',
                  builder: (_, state) {
                    final id = state.pathParameters['id']!;
                    return ViewModelHost(
                      key: ValueKey('tournament-$id'),
                      create: (c) => TournamentDetailViewModel(
                        tournamentId: id,
                        tournamentRepository: c.read(),
                        usauScheduleRepository: c.read(),
                      ),
                      builder: (_, vm) => TournamentDetailScreen(viewModel: vm),
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
                create: (c) => RankingsViewModel(rankingRepository: c.read()),
                builder: (_, vm) => RankingsScreen(viewModel: vm),
              ),
              routes: [
                GoRoute(path: 'team', builder: (_, state) => _usauTeam(state)),
              ],
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

/// A USA Ultimate team page, from Rankings or Teams search.
Widget _teamSection(GoRouterState state, TeamSection section) {
  final teamId = state.pathParameters['teamId']!;
  return ViewModelHost(
    key: ValueKey('team-$teamId-${section.name}'),
    create: (c) => TeamDetailViewModel(
      teamId: teamId,
      teamRepository: c.read(),
      playRepository: c.read(),
      eventRepository: c.read(),
      meetingRepository: c.read<MeetingRepository>(),
      authRepository: c.read(),
    ),
    builder: (_, vm) => TeamSectionScreen(viewModel: vm, section: section),
  );
}

Widget _usauTeam(GoRouterState state) {
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
}

/// Creates a chat room ([roomId] null) or edits one.
Widget _chatRoomSettings(GoRouterState state, String? roomId) {
  final teamId = state.pathParameters['teamId']!;
  return ViewModelHost(
    key: ValueKey('chat-settings-$teamId-$roomId'),
    create: (c) => ChatRoomSettingsViewModel(
      teamId: teamId,
      roomId: roomId,
      teamRepository: c.read(),
      chatRepository: c.read(),
      authRepository: c.read(),
    ),
    builder: (_, vm) => ChatRoomSettingsScreen(viewModel: vm),
  );
}
