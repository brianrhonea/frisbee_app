import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../data/repositories/hosted_tournament/hosted_tournament_repository.dart';
import '../data/repositories/calendar/calendar_repository.dart';
import '../data/repositories/chat/chat_repository.dart';
import '../data/repositories/direct_message/direct_message_repository.dart';
import '../data/repositories/notification/notification_repository.dart';
import '../data/repositories/auth/auth_repository.dart';
import '../data/repositories/meeting/meeting_repository.dart';
import '../data/repositories/schedule/schedule_settings_repository.dart';
import '../data/repositories/team/team_hints_repository.dart';
import '../data/repositories/learn/learn_progress_repository.dart';
import '../data/repositories/discover/discover_repository.dart';
import '../ui/auth/view_models/choose_username_viewmodel.dart';
import '../ui/auth/view_models/sign_in_viewmodel.dart';
import '../ui/auth/view_models/sign_up_viewmodel.dart';
import '../ui/auth/widgets/choose_username_screen.dart';
import '../ui/auth/widgets/sign_in_screen.dart';
import '../ui/auth/widgets/sign_up_screen.dart';
import '../ui/core/ui/view_model_host.dart';
import '../ui/home/view_models/home_viewmodel.dart';
import '../ui/home/widgets/home_screen.dart';
import '../ui/learn/view_models/learn_viewmodel.dart';
import '../ui/learn/widgets/learn_screen.dart';
import '../ui/posts/view_models/post_detail_viewmodel.dart';
import '../ui/posts/widgets/post_detail_screen.dart';
import '../domain/models/ranking.dart';
import '../ui/explore/view_models/explore_viewmodel.dart';
import '../ui/explore/view_models/player_search_viewmodel.dart';
import '../ui/explore/widgets/rankings_screen.dart';
import '../ui/explore/widgets/explore_screen.dart';
import '../ui/profile/view_models/player_profile_viewmodel.dart';
import '../ui/profile/widgets/profile_screen.dart';
import '../ui/schedule/view_models/schedule_viewmodel.dart';
import '../ui/schedule/widgets/schedule_screen.dart';
import '../ui/shell/widgets/app_shell.dart';
import '../ui/tournaments/view_models/hosted_tournaments_viewmodel.dart';
import '../ui/teams/view_models/team_home_viewmodel.dart';
import '../ui/teams/view_models/team_search_viewmodel.dart';
import '../ui/teams/widgets/team_home_screen.dart';
import '../ui/teams/widgets/team_section_screen.dart';
import 'routes.dart';
import '../ui/personal/view_models/personal_details_viewmodel.dart';
import '../ui/personal/view_models/personal_prompt_viewmodel.dart';
import '../ui/personal/widgets/personal_details_screen.dart';
import '../ui/personal/widgets/personal_prompt_card.dart';

// Pages the app's router (router.dart) shows, with their view models wired
// up once.

Widget signInPage() => ViewModelHost(
  create: (c) => SignInViewModel(authRepository: c.read()),
  builder: (_, vm) => SignInScreen(viewModel: vm),
);

Widget signUpPage() => ViewModelHost(
  create: (c) =>
      SignUpViewModel(authRepository: c.read(), personalRepository: c.read()),
  builder: (_, vm) => SignUpScreen(viewModel: vm),
);

/// Personal details: the last step of signing up, or from Settings.
Widget personalDetailsPage({bool finishing = false}) => ViewModelHost(
  key: ValueKey('personal-details-$finishing'),
  create: (c) => PersonalDetailsViewModel(
    personalRepository: c.read(),
    authRepository: c.read(),
    finishing: finishing,
  ),
  builder: (_, vm) => PersonalDetailsScreen(viewModel: vm),
);

Widget chooseUsernamePage() => ViewModelHost(
  create: (c) => ChooseUsernameViewModel(
    authRepository: c.read(),
    personalRepository: c.read(),
  ),
  builder: (_, vm) => ChooseUsernameScreen(viewModel: vm),
);

/// Learn to play, with its reading progress (kept on this device).
Widget learnPage() => ViewModelHost(
  create: (c) => LearnViewModel(
    // Tests that don't provide one keep progress in memory.
    repository:
        c.read<LearnProgressRepository?>() ?? LearnProgressRepositoryMemory(),
  ),
  builder: (_, vm) => LearnScreen(viewModel: vm),
);

/// Discover, with its search and filter from `?q=` and `?only=`: search,
/// what's live, tournaments and leagues coming up (what the Events tab's
/// "Find events" was), results and rankings.
Widget explorePage(GoRouterState state) => ViewModelHost(
  create: (c) =>
      TeamSearchViewModel(teamRepository: c.read(), authRepository: c.read()),
  builder: (_, vm) => ViewModelHost(
    create: (c) => PlayerSearchViewModel(profileRepository: c.read()),
    builder: (_, players) => ViewModelHost(
      create: (c) => exploreViewModel(c),
      builder: (_, explore) => ViewModelHost(
        create: (c) => HostedTournamentsViewModel(
          tournamentRepository: c.read(),
          authRepository: c.read(),
          discoverRepository: c.read<DiscoverRepository?>(),
        ),
        builder: (_, events) => ExploreScreen(
          viewModel: vm,
          players: players,
          explore: explore,
          events: events,
          initialQuery: state.uri.queryParameters['q'] ?? '',
          initialFilter: ExploreFilter.values
              .where((f) => f.name == state.uri.queryParameters['only'])
              .firstOrNull,
        ),
      ),
    ),
  ),
);

ExploreViewModel exploreViewModel(
  BuildContext c, {
  bool rankingsPage = false,
  RankingKind kind = RankingKind.teams,
  String? level,
  String? division,
}) => ExploreViewModel(
  tournamentRepository: c.read(),
  rankingRepository: c.read(),
  teamRepository: c.read(),
  authRepository: c.read(),
  discoverRepository: rankingsPage ? null : c.read<DiscoverRepository?>(),
  rankingsPage: rankingsPage,
  kind: kind,
  level: level,
  division: division,
);

/// Team rankings by Level and Division (`?level=club&division=mixed`, as
/// the website links them; the old `?d=club-mixed` and
/// `?division=club-mixed` still work), or players (`?kind=players`, or the
/// old `?d=players`).
Widget rankingsPage(GoRouterState state) {
  final q = state.uri.queryParameters;
  final players = q['kind'] == 'players' || q['d'] == 'players';
  final want = RankingChoice.wantFromQuery(
    level: q['level'],
    division: q['division'],
    d: players ? null : q['d'],
  );
  return ViewModelHost(
    create: (c) => exploreViewModel(
      c,
      rankingsPage: true,
      kind: players ? RankingKind.players : RankingKind.teams,
      level: want.level,
      division: want.division,
    ),
    builder: (_, vm) => RankingsScreen(viewModel: vm),
  );
}

PlayerProfileViewModel playerProfileViewModel(BuildContext c, String uid) =>
    PlayerProfileViewModel(
      uid: uid,
      profileRepository: c.read(),
      authRepository: c.read(),
      teamRepository: c.read(),
      statsRepository: c.read(),
      directMessageRepository: c.read(),
      followRepository: c.read(),
      userPostRepository: c.read(),
      notificationRepository: c.read(),
      filePicker: c.read(),
    );

/// Another player's profile.
Widget playerPage(String uid) => ViewModelHost(
  key: ValueKey(uid),
  create: (c) => playerProfileViewModel(c, uid),
  builder: (_, vm) => PlayerProfileScreen(viewModel: vm),
);

/// The signed-in user's own profile.
Widget myProfilePage() => ViewModelHost(
  create: (c) => playerProfileViewModel(
    c,
    c.read<AuthRepository>().currentUser?.uid ?? '',
  ),
  builder: (_, vm) => PlayerProfileScreen(viewModel: vm),
);

/// A team's home page, on the tab named by `?section=`.
Widget teamPage(GoRouterState state) {
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
      followRepository: c.read(),
      notificationRepository: c.read(),
      groupTournamentRepository: c.read(),
      tournamentRepository: c.read<HostedTournamentRepository?>(),
      hints: c.read<TeamHintsRepository?>(),
      chatRepository: c.read<ChatRepository?>(),
      directMessageRepository: c.read<DirectMessageRepository?>(),
    ),
    builder: (_, vm) => TeamHomeScreen(
      viewModel: vm,
      section: TeamSection.fromPath(state.uri.queryParameters['section']),
      more: state.uri.queryParameters['section'] == TeamTab.morePath,
      inTeamsTab: state.uri.path.startsWith('${Routes.teams}/'),
    ),
  );
}

/// The signed-in user's Home: posts from who they follow, their teams'
/// news and what's next on their schedule.
Widget homePage() => ViewModelHost(
  create: (c) => HomeViewModel(
    authRepository: c.read(),
    teamRepository: c.read(),
    eventRepository: c.read(),
    meetingRepository: c.read<MeetingRepository>(),
    teamPostRepository: c.read(),
    followRepository: c.read(),
    userPostRepository: c.read(),
    filePicker: c.read(),
    tournamentRepository: c.read<HostedTournamentRepository?>(),
  ),
  builder: (_, vm) => HomeScreen(
    viewModel: vm,
    prompt: ViewModelHost(
      create: (c) => PersonalPromptViewModel(
        personalRepository: c.read(),
        authRepository: c.read(),
      ),
      builder: (_, p) => PersonalPromptCard(viewModel: p),
    ),
  ),
);

/// A post's page with its comments; `?comment=1` goes to the comment box.
Widget postPage(GoRouterState state) {
  final id = state.pathParameters['postId']!;
  return ViewModelHost(
    key: ValueKey('post-$id'),
    create: (c) => PostDetailViewModel(
      postId: id,
      userPostRepository: c.read(),
      authRepository: c.read(),
      commentRepository: c.read(),
      notificationRepository: c.read<NotificationRepository?>(),
    ),
    builder: (_, vm) => PostDetailScreen(
      viewModel: vm,
      focusComment: state.uri.queryParameters['comment'] == '1',
    ),
  );
}

/// The Schedule tab: the user's own calendar, a week at a time.
Widget schedulePage() => ViewModelHost(
  key: const ValueKey('schedule'),
  create: (c) => ScheduleViewModel(
    authRepository: c.read(),
    teamRepository: c.read(),
    eventRepository: c.read(),
    meetingRepository: c.read<MeetingRepository>(),
    calendarRepository: c.read<CalendarRepository>(),
    settingsRepository: c.read<ScheduleSettingsRepository?>(),
  ),
  builder: (context, vm) =>
      ScheduleScreen(viewModel: vm, leading: ProfileButton.leading(context)),
);
