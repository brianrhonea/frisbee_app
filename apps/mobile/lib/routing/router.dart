import '../data/repositories/notification/notification_repository.dart';
import '../data/repositories/draft/message_draft_repository.dart';
import '../data/repositories/people/people_repository.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../data/repositories/auth/auth_repository.dart';
import '../data/repositories/personal/personal_repository.dart';
import '../domain/models/model_utils.dart';
import '../domain/models/team.dart';
import '../ui/calendar/view_models/calendars_viewmodel.dart';
import '../ui/calendar/widgets/calendars_screen.dart';
import '../ui/chat/view_models/chat_room_settings_viewmodel.dart';
import '../ui/chat/view_models/chat_room_viewmodel.dart';
import '../ui/chat/widgets/chat_layout.dart';
import '../ui/chat/widgets/chat_room_screen.dart';
import '../ui/chat/widgets/chat_room_settings_screen.dart';
import '../ui/meetings/view_models/meeting_detail_viewmodel.dart';
import '../ui/meetings/view_models/meeting_editor_viewmodel.dart';
import '../ui/meetings/view_models/meeting_room_viewmodel.dart';
import '../ui/meetings/widgets/meeting_detail_screen.dart';
import '../ui/meetings/widgets/meeting_editor_screen.dart';
import '../ui/meetings/widgets/meeting_room_screen.dart';
import '../ui/messages/view_models/direct_chat_viewmodel.dart';
import '../ui/messages/view_models/group_members_viewmodel.dart';
import '../ui/messages/view_models/inbox_viewmodel.dart';
import '../ui/messages/widgets/direct_chat_screen.dart';
import '../ui/messages/widgets/group_members_screen.dart';
import '../ui/messages/widgets/inbox_screen.dart';
import '../ui/core/ui/status_views.dart';
import '../ui/core/ui/view_model_host.dart';
import '../ui/core/ui/slide_over_page.dart';
import '../ui/settings/widgets/follow_requests_screen.dart';
import '../ui/settings/widgets/settings_screen.dart';
import '../ui/learn/widgets/learn_screen.dart';
import '../ui/shell/view_models/shell_viewmodel.dart';
import '../ui/shell/widgets/app_shell.dart';
import '../ui/playbook/view_models/play_editor_viewmodel.dart';
import '../ui/playbook/widgets/play_editor_screen.dart';
import '../ui/notifications/view_models/notification_settings_viewmodel.dart';
import '../ui/notifications/view_models/notifications_viewmodel.dart';
import '../ui/notifications/widgets/notification_settings_screen.dart';
import '../ui/notifications/widgets/notifications_screen.dart';
import '../ui/people/view_models/following_viewmodel.dart';
import '../ui/people/widgets/following_screen.dart';
import '../ui/profile/view_models/profile_viewmodel.dart';
import '../ui/teams/view_models/join_link_viewmodel.dart';
import '../ui/teams/widgets/join_link_screen.dart';
import '../ui/schedule/view_models/event_detail_viewmodel.dart';
import '../ui/schedule/view_models/event_editor_viewmodel.dart';
import '../ui/schedule/view_models/my_event_detail_viewmodel.dart';
import '../ui/schedule/widgets/event_detail_screen.dart';
import '../ui/schedule/widgets/event_editor_screen.dart';
import '../ui/schedule/widgets/my_event_detail_screen.dart';
import '../ui/stats/view_models/game_tracker_viewmodel.dart';
import '../ui/stats/view_models/stats_viewmodel.dart';
import '../ui/stats/view_models/tournament_viewmodel.dart';
import '../ui/stats/widgets/game_screen.dart';
import '../ui/stats/widgets/stats_tab.dart';
import '../ui/stats/widgets/tournament_screen.dart';
import '../ui/teams/view_models/create_team_viewmodel.dart';
import '../ui/teams/view_models/teams_viewmodel.dart';
import '../ui/teams/widgets/create_team_screen.dart';
import '../ui/teams/widgets/team_section_screen.dart';
import '../ui/teams/widgets/teams_screen.dart';
import '../ui/teams/view_models/roles_viewmodel.dart';
import '../ui/teams/widgets/roles_screen.dart';
import '../ui/teams/view_models/discord_import_viewmodel.dart';
import '../ui/teams/widgets/discord_import_screen.dart';
import '../ui/group_tournaments/view_models/tournament_editor_viewmodel.dart';
import '../ui/group_tournaments/view_models/group_tournament_viewmodel.dart';
import '../ui/group_tournaments/widgets/tournament_editor_screen.dart';
import '../ui/group_tournaments/widgets/group_tournament_screen.dart';
import 'tournament_routes.dart';
import '../ui/videos/view_models/video_editor_viewmodel.dart';
import '../ui/videos/view_models/video_viewmodel.dart';
import '../ui/videos/widgets/video_editor_screen.dart';
import '../ui/videos/widgets/video_screen.dart';
import '../ui/workouts/view_models/record_workout_viewmodel.dart';
import '../ui/workouts/widgets/record_workout_screen.dart';
import '../ui/workouts/widgets/route_widgets.dart';
import 'route_builders.dart';
import 'routes.dart';

const splashPath = '/splash';
const _publicRoutes = {Routes.signIn, Routes.signUp};

final _rootKey = GlobalKey<NavigatorState>();

GoRouter router(
  AuthRepository auth,
  PersonalDetailsRepository personal,
) => GoRouter(
  navigatorKey: _rootKey,
  initialLocation: Routes.home,
  refreshListenable: Listenable.merge([auth, personal]),
  redirect: (context, state) =>
      authRedirect(auth, state.uri, personal: personal),
  routes: [
    GoRoute(
      path: splashPath,
      builder: (_, _) => const Scaffold(body: LoadingView()),
    ),
    GoRoute(path: Routes.signIn, builder: (_, _) => signInPage()),
    GoRoute(
      path: Routes.chooseUsername,
      builder: (_, _) => chooseUsernamePage(),
    ),
    GoRoute(
      path: Routes.finishSignUp,
      builder: (_, _) => personalDetailsPage(finishing: true),
    ),
    GoRoute(path: Routes.signUp, builder: (_, _) => signUpPage()),
    // Invite links (InviteLinks), opened from other apps: join a team by
    // its code, or open a group's page, where people join or ask to.
    GoRoute(
      path: '/join/:code',
      builder: (_, state) {
        final code = state.pathParameters['code']!;
        return ViewModelHost(
          key: ValueKey('join-$code'),
          create: (c) => JoinLinkViewModel(
            code: code,
            teamRepository: c.read(),
            authRepository: c.read(),
          ),
          builder: (_, vm) => JoinLinkScreen(viewModel: vm),
        );
      },
    ),
    GoRoute(
      path: '/g/:groupId',
      redirect: (_, state) => Routes.team(state.pathParameters['groupId']!),
    ),
    // Post links (InviteLinks.post), sent in messages or shared to other
    // apps.
    GoRoute(
      path: '/p/:postId',
      redirect: (_, state) => Routes.post(state.pathParameters['postId']!),
    ),
    // A profile opened from a conversation or chat room, over it, so back
    // returns there (the Explore tab's /players/:uid would switch tabs).
    GoRoute(
      path: '/people/:uid',
      redirect: (_, state) =>
          state.pathParameters['uid'] == auth.currentUser?.uid
          ? Routes.profile
          : null,
      builder: (_, state) => playerPage(state.pathParameters['uid']!),
    ),
    // A team or group opened from a tournament, over it, so back returns
    // there (see Routes.teamOver).
    GoRoute(
      path: '${Routes.teamsOverPath}/:teamId',
      parentNavigatorKey: _rootKey,
      builder: (_, state) => teamPage(state),
    ),
    // People's posts, over the shell. `/posts` alone goes Home, where the
    // feed is. The composer is an overlay, not a route.
    GoRoute(
      path: Routes.postsPath,
      redirect: (_, state) =>
          state.uri.path == Routes.postsPath ? Routes.home : null,
      routes: [
        GoRoute(path: ':postId', builder: (_, state) => postPage(state)),
      ],
    ),
    GoRoute(
      path: Routes.recordWorkout,
      builder: (context, _) => ViewModelHost(
        create: (c) => RecordWorkoutViewModel(
          recorder: c.read(),
          location: c.read(),
          unit: distanceUnitOf(c),
        ),
        builder: (_, vm) => RecordWorkoutScreen(viewModel: vm),
      ),
    ),
    GoRoute(path: Routes.learn, builder: (_, _) => const LearnScreen()),
    // Settings, from the gear on the user's profile: slides over the page
    // (a panel on wide screens), and its sections slide over it.
    GoRoute(
      path: Routes.settings,
      pageBuilder: (context, state) => slideOverPage(
        context,
        state.pageKey,
        _settings((vm) => SettingsScreen(viewModel: vm)),
        panelOnWide: true,
      ),
      routes: [
        for (final (path, screen)
            in <(String, Widget Function(ProfileViewModel))>[
              ('general', (vm) => GeneralSettingsScreen(viewModel: vm)),
              ('privacy', (vm) => PrivacySettingsScreen(viewModel: vm)),
              ('account', (vm) => AccountSettingsScreen(viewModel: vm)),
              ('follow-requests', (vm) => FollowRequestsScreen(viewModel: vm)),
            ])
          GoRoute(
            path: path,
            pageBuilder: (context, state) => slideOverPage(
              context,
              state.pageKey,
              _settings(screen),
              panelOnWide: true,
              dim: false,
            ),
          ),
        GoRoute(
          path: 'personal',
          pageBuilder: (context, state) => slideOverPage(
            context,
            state.pageKey,
            personalDetailsPage(),
            panelOnWide: true,
            dim: false,
          ),
        ),
        GoRoute(
          path: 'calendar',
          pageBuilder: (context, state) => slideOverPage(
            context,
            state.pageKey,
            ViewModelHost(
              create: (c) => CalendarsViewModel(
                calendarRepository: c.read(),
                profileRepository: c.read(),
                uid: c.read<AuthRepository>().currentUser?.uid,
              ),
              builder: (_, vm) => CalendarsScreen(viewModel: vm),
            ),
            panelOnWide: true,
            dim: false,
          ),
        ),
        GoRoute(
          path: 'following',
          pageBuilder: (context, state) => slideOverPage(
            context,
            state.pageKey,
            ViewModelHost(
              create: (c) => FollowingViewModel(
                followRepository: c.read(),
                notificationRepository: c.read(),
                authRepository: c.read(),
              ),
              builder: (_, vm) => FollowingScreen(viewModel: vm),
            ),
            panelOnWide: true,
            dim: false,
          ),
        ),
      ],
    ),
    // Opened from the bell on Home, over the shell.
    GoRoute(
      path: Routes.notifications,
      builder: (_, _) => ViewModelHost(
        create: (c) => NotificationsViewModel(
          notificationRepository: c.read(),
          authRepository: c.read(),
          followRepository: c.read(),
        ),
        builder: (_, vm) => NotificationsScreen(viewModel: vm),
      ),
      routes: [
        GoRoute(
          path: 'settings',
          // Usually opened from Settings, so it slides over it the same way.
          pageBuilder: (context, state) => slideOverPage(
            context,
            state.pageKey,
            ViewModelHost(
              create: (c) => NotificationSettingsViewModel(
                notificationRepository: c.read(),
                teamRepository: c.read(),
                authRepository: c.read(),
              ),
              builder: (_, vm) => NotificationSettingsScreen(viewModel: vm),
            ),
            panelOnWide: true,
            dim: false,
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
                postRepository: c.read(),
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
                tournamentRepository: c.read(),
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
    // Team videos, full screen over the shell (see Routes.teamVideosPath).
    GoRoute(
      path: '${Routes.teamVideosPath}/:teamId',
      redirect: (_, state) {
        final teamId = state.pathParameters['teamId']!;
        final base = '${Routes.teamVideosPath}/$teamId';
        return state.uri.path == base ? Routes.teamVideos(teamId) : null;
      },
      routes: [
        GoRoute(path: 'new', builder: (_, state) => _videoEditor(state, null)),
        GoRoute(
          path: ':videoId',
          builder: (_, state) {
            final teamId = state.pathParameters['teamId']!;
            final videoId = state.pathParameters['videoId']!;
            return ViewModelHost(
              key: ValueKey('video-$teamId-$videoId'),
              create: (c) => VideoViewModel(
                teamId: teamId,
                videoId: videoId,
                videoRepository: c.read(),
                teamRepository: c.read(),
                authRepository: c.read(),
              ),
              builder: (_, vm) => VideoScreen(viewModel: vm),
            );
          },
          routes: [
            GoRoute(
              path: 'edit',
              builder: (_, state) =>
                  _videoEditor(state, state.pathParameters['videoId']),
            ),
          ],
        ),
      ],
    ),
    // Hosted tournaments, full screen over the shell (see
    // Routes.tournaments).
    ...hostedTournamentRoutes(),
    // Community group tournaments, full screen over the shell (see
    // Routes.groupTournamentsPath).
    GoRoute(
      path: '${Routes.groupTournamentsPath}/:groupId',
      redirect: (_, state) {
        final groupId = state.pathParameters['groupId']!;
        final base = '${Routes.groupTournamentsPath}/$groupId';
        return state.uri.path == base ? Routes.teamTournaments(groupId) : null;
      },
      routes: [
        GoRoute(
          path: 'new',
          builder: (_, state) => _tournamentEditor(state, null),
        ),
        GoRoute(
          path: ':tournamentId',
          builder: (_, state) {
            final groupId = state.pathParameters['groupId']!;
            final tournamentId = state.pathParameters['tournamentId']!;
            return ViewModelHost(
              key: ValueKey('group-tournament-$groupId-$tournamentId'),
              create: (c) => GroupTournamentViewModel(
                groupId: groupId,
                tournamentId: tournamentId,
                teamRepository: c.read(),
                tournamentRepository: c.read(),
                authRepository: c.read(),
                followRepository: c.read(),
                notificationRepository: c.read(),
              ),
              builder: (_, vm) => GroupTournamentScreen(viewModel: vm),
            );
          },
          routes: [
            GoRoute(
              path: 'edit',
              builder: (_, state) => _tournamentEditor(
                state,
                state.pathParameters['tournamentId'],
              ),
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
                    videoRepository: c.read(),
                  ),
                  builder: (_, vm) => MeetingRoomScreen(viewModel: vm),
                );
              },
            ),
          ],
        ),
      ],
    ),
    // Editing an event on a calendar other than My calendar (through the
    // API); those have no page of their own.
    GoRoute(
      path: '${Routes.calendarsPath}/:calendarId/events/:eventId/edit',
      builder: (_, state) {
        final calendarId = state.pathParameters['calendarId']!;
        final eventId = state.pathParameters['eventId']!;
        return ViewModelHost(
          key: ValueKey('edit-calendar-event-$calendarId-$eventId'),
          create: (c) => EventEditorViewModel(
            teamId: null,
            calendarId: calendarId,
            eventId: eventId,
            eventRepository: c.read(),
            teamRepository: c.read(),
            authRepository: c.read(),
            calendarRepository: c.read(),
          ),
          builder: (_, vm) => EventEditorScreen(viewModel: vm),
        );
      },
    ),
    // Personal schedule, full screen over the shell.
    GoRoute(
      path: Routes.myEventsPath,
      redirect: (_, state) =>
          state.uri.path == Routes.myEventsPath ? Routes.schedule : null,
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
                postRepository: c.read(),
                calendarRepository: c.read(),
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
    // The app frame; branch order matches ShellSection.
    StatefulShellRoute.indexedStack(
      builder: (_, state, shell) => ViewModelHost(
        create: (c) => ShellViewModel(
          authRepository: c.read(),
          teamRepository: c.read(),
          directMessageRepository: c.read(),
          notificationRepository: c.read(),
        ),
        builder: (_, vm) => AppShell(
          viewModel: vm,
          navigationShell: shell,
          location: state.uri.toString(),
        ),
      ),
      branches: [
        // Home: the feed.
        StatefulShellBranch(
          routes: [GoRoute(path: Routes.home, builder: (_, _) => homePage())],
        ),
        // Explore: search and player profiles.
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Routes.explorePath,
              builder: (_, state) => explorePage(state),
            ),
            GoRoute(
              path: Routes.rankingsPath,
              builder: (_, state) => rankingsPage(state),
            ),
            GoRoute(
              path: '/players/:uid',
              // Your own profile lives on the Profile tab.
              redirect: (_, state) =>
                  state.pathParameters['uid'] == auth.currentUser?.uid
                  ? Routes.profile
                  : null,
              builder: (_, state) => playerPage(state.pathParameters['uid']!),
            ),
          ],
        ),
        // Events: the user's schedule, and tournaments and leagues to find.
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Routes.schedule,
              builder: (_, state) => eventsPage(state),
            ),
          ],
        ),
        // Teams: the user's teams and communities, and every team page.
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
                  builder: (_, state) => ViewModelHost(
                    create: (c) => CreateTeamViewModel(
                      teamRepository: c.read(),
                      authRepository: c.read(),
                    ),
                    builder: (_, vm) => CreateTeamScreen(
                      viewModel: vm,
                      kind: enumByName(
                        TeamKind.values,
                        state.uri.queryParameters['kind'],
                        TeamKind.team,
                      ),
                    ),
                  ),
                ),
                GoRoute(
                  path: 'search',
                  // Finding teams and groups is Explore's job now; old links
                  // land there.
                  redirect: (_, _) => Routes.explore(only: ExploreFilter.teams),
                  builder: (_, _) => const SizedBox.shrink(),
                ),
                GoRoute(
                  path: ':teamId',
                  // Old links (e.g. in the notification feed) name a tab
                  // with ?tab=.
                  redirect: (_, state) {
                    if (state.uri.pathSegments.length != 2) return null;
                    final tab = state.uri.queryParameters['tab'];
                    if (tab == null) return null;
                    final teamId = state.pathParameters['teamId']!;
                    return TeamSection.fromLegacyTab(tab)?.route(teamId) ??
                        Routes.team(teamId);
                  },
                  builder: (_, state) => teamPage(state),
                  routes: [
                    // Sections are tabs of the team page; old links (e.g.
                    // in the notification feed) name them by path.
                    for (final section in TeamSection.values)
                      GoRoute(
                        path: section.path,
                        redirect: (_, state) =>
                            section.route(state.pathParameters['teamId']!),
                      ),
                    GoRoute(
                      path: 'discord',
                      parentNavigatorKey: _rootKey,
                      builder: (_, state) {
                        final teamId = state.pathParameters['teamId']!;
                        return ViewModelHost(
                          key: ValueKey('discord-$teamId'),
                          create: (c) => DiscordImportViewModel(
                            teamId: teamId,
                            teamRepository: c.read(),
                            chatRepository: c.read(),
                            discordImportRepository: c.read(),
                            authRepository: c.read(),
                          ),
                          builder: (_, vm) =>
                              DiscordImportScreen(viewModel: vm),
                        );
                      },
                    ),
                    GoRoute(
                      path: 'roles',
                      parentNavigatorKey: _rootKey,
                      builder: (_, state) {
                        final teamId = state.pathParameters['teamId']!;
                        return ViewModelHost(
                          key: ValueKey('roles-$teamId'),
                          create: (c) => RolesViewModel(
                            teamId: teamId,
                            teamRepository: c.read(),
                            authRepository: c.read(),
                          ),
                          builder: (_, vm) => RolesScreen(viewModel: vm),
                        );
                      },
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
                              peopleRepository: c.read<PeopleRepository?>(),
                              draftRepository: c
                                  .read<MessageDraftRepository?>(),
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
        // Messages: private conversations. Team chats are on team pages.
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Routes.messages,
              builder: (_, _) => ViewModelHost(
                create: (c) => InboxViewModel(
                  directMessageRepository: c.read(),
                  authRepository: c.read(),
                  notificationRepository: c.read<NotificationRepository?>(),
                ),
                builder: (_, vm) => InboxScreen(viewModel: vm),
              ),
              routes: [
                GoRoute(
                  path: 'new',
                  parentNavigatorKey: _rootKey,
                  // One person picked: a direct message; several: a group.
                  builder: (_, _) => ViewModelHost(
                    create: (c) => GroupMembersViewModel(
                      directMessageRepository: c.read(),
                      authRepository: c.read(),
                    ),
                    builder: (_, vm) => GroupMembersScreen(viewModel: vm),
                  ),
                ),
                GoRoute(
                  path: 'new-group',
                  parentNavigatorKey: _rootKey,
                  builder: (_, state) {
                    final to = state.uri.queryParameters['to'];
                    return ViewModelHost(
                      key: ValueKey('group-members-$to'),
                      create: (c) => GroupMembersViewModel(
                        directMessageRepository: c.read(),
                        authRepository: c.read(),
                        groupId: to,
                      ),
                      builder: (_, vm) => GroupMembersScreen(viewModel: vm),
                    );
                  },
                ),
                GoRoute(
                  path: ':conversationId',
                  parentNavigatorKey: _rootKey,
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
                          peopleRepository: c.read<PeopleRepository?>(),
                          draftRepository: c.read<MessageDraftRepository?>(),
                          notificationRepository: c
                              .read<NotificationRepository?>(),
                        ),
                        builder: (_, vm) => DirectChatScreen(viewModel: vm),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
        // My profile.
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Routes.profile,
              builder: (_, _) => myProfilePage(),
              routes: [
                // Everything the user follows, over the shell.
                GoRoute(
                  path: 'following',
                  parentNavigatorKey: _rootKey,
                  builder: (_, _) => ViewModelHost(
                    create: (c) => FollowingViewModel(
                      followRepository: c.read(),
                      notificationRepository: c.read(),
                      authRepository: c.read(),
                    ),
                    builder: (_, vm) => FollowingScreen(viewModel: vm),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
);

/// A settings page with its own [ProfileViewModel].
Widget _settings(Widget Function(ProfileViewModel vm) screen) => ViewModelHost(
  create: (c) => ProfileViewModel(
    authRepository: c.read(),
    themeRepository: c.read(),
    notificationRepository: c.read(),
    directMessageRepository: c.read(),
    profileRepository: c.read(),
    followRepository: c.read(),
  ),
  builder: (_, vm) => screen(vm),
);

/// Sends signed-out users to sign-in (remembering where they were headed),
/// signed-in users without a username to pick one, new accounts without
/// personal details ([personal]) to give them, and everyone else away
/// from the auth screens: to Community, or back to
/// the invite link they opened so they can finish joining.
String? authRedirect(
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
  final public = _publicRoutes.contains(path);
  if (!auth.isAuthenticated) {
    if (public) return null;
    final target = path == splashPath ? from : uri.toString();
    return Uri(
      path: Routes.signIn,
      queryParameters: target == null || target == Routes.home
          ? null
          : {'from': target},
    ).toString();
  }
  // No username yet: pick one first, then carry on.
  final choosing = path == Routes.chooseUsername;
  if (auth.needsUsername) {
    if (choosing) return null;
    final target = public || path == splashPath ? from : uri.toString();
    return Uri(
      path: Routes.chooseUsername,
      queryParameters: target == null || target == Routes.home
          ? null
          : {'from': target},
    ).toString();
  }
  if (choosing) return from ?? Routes.home;
  // A new account without personal details: those next. Only on a definite
  // "required and missing"; while it's unknown nobody is held up.
  final finishing = path == Routes.finishSignUp;
  if (personal?.mustComplete ?? false) {
    if (finishing) return null;
    final target = public || path == splashPath ? from : uri.toString();
    return Uri(
      path: Routes.finishSignUp,
      queryParameters: target == null || target == Routes.home
          ? null
          : {'from': target},
    ).toString();
  }
  if (finishing) return from ?? Routes.home;
  if (public) return _isInviteLink(from) ? from : Routes.home;
  // Already signed in when the app opened: carry on where it was headed.
  if (path == splashPath) return from ?? Routes.home;
  return null;
}

/// Team invite links (`/join/CODE`), group links (`/g/ID`) and post links
/// (`/p/ID`), which signing in returns to.
bool _isInviteLink(String? location) {
  final path = location == null ? null : Uri.tryParse(location)?.path;
  return path != null &&
      (path.startsWith('/join/') ||
          path.startsWith('/g/') ||
          path.startsWith('/p/'));
}

/// Sets up a new group tournament, or edits [tournamentId].
Widget _tournamentEditor(GoRouterState state, String? tournamentId) {
  final groupId = state.pathParameters['groupId']!;
  final eventId = state.uri.queryParameters['event'];
  return ViewModelHost(
    key: ValueKey('tournament-editor-$groupId-$tournamentId-$eventId'),
    create: (c) => TournamentEditorViewModel(
      groupId: groupId,
      tournamentId: tournamentId,
      teamRepository: c.read(),
      eventRepository: c.read(),
      tournamentRepository: c.read(),
      authRepository: c.read(),
      postRepository: c.read(),
      filePicker: c.read(),
      eventId: eventId,
    ),
    builder: (_, vm) => TournamentEditorScreen(viewModel: vm),
  );
}

/// Adds a video to a team, or edits [videoId].
Widget _videoEditor(GoRouterState state, String? videoId) {
  final teamId = state.pathParameters['teamId']!;
  return ViewModelHost(
    key: ValueKey('video-editor-$teamId-$videoId'),
    create: (c) => VideoEditorViewModel(
      teamId: teamId,
      videoId: videoId,
      videoRepository: c.read(),
      teamRepository: c.read(),
      authRepository: c.read(),
      youTubeInfo: c.read(),
      filePicker: c.read(),
      initialFolderId: videoId == null
          ? state.uri.queryParameters['folder']
          : null,
    ),
    builder: (_, vm) => VideoEditorScreen(viewModel: vm),
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
      folderId: roomId == null ? state.uri.queryParameters['folder'] : null,
      teamRepository: c.read(),
      chatRepository: c.read(),
      authRepository: c.read(),
    ),
    builder: (_, vm) => ChatRoomSettingsScreen(viewModel: vm),
  );
}
