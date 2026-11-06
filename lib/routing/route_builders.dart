import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../data/repositories/auth/auth_repository.dart';
import '../data/repositories/meeting/meeting_repository.dart';
import '../ui/auth/view_models/choose_username_viewmodel.dart';
import '../ui/auth/view_models/sign_in_viewmodel.dart';
import '../ui/auth/view_models/sign_up_viewmodel.dart';
import '../ui/auth/widgets/choose_username_screen.dart';
import '../ui/auth/widgets/sign_in_screen.dart';
import '../ui/auth/widgets/sign_up_screen.dart';
import '../ui/core/ui/view_model_host.dart';
import '../ui/events/widgets/events_screen.dart';
import '../ui/home/view_models/home_viewmodel.dart';
import '../ui/home/widgets/home_screen.dart';
import '../ui/posts/view_models/post_detail_viewmodel.dart';
import '../ui/posts/widgets/post_detail_screen.dart';
import '../ui/explore/view_models/player_search_viewmodel.dart';
import '../ui/explore/widgets/explore_screen.dart';
import '../ui/profile/view_models/player_profile_viewmodel.dart';
import '../ui/profile/widgets/profile_screen.dart';
import '../ui/rankings/view_models/rankings_viewmodel.dart';
import '../ui/rankings/view_models/usau_team_viewmodel.dart';
import '../ui/rankings/widgets/rankings_screen.dart';
import '../ui/rankings/widgets/usau_team_screen.dart';
import '../ui/teams/view_models/team_home_viewmodel.dart';
import '../ui/teams/view_models/team_search_viewmodel.dart';
import '../ui/teams/widgets/team_home_screen.dart';
import '../ui/teams/widgets/team_section_screen.dart';
import '../ui/tournaments/view_models/tournament_detail_viewmodel.dart';
import '../ui/tournaments/view_models/tournaments_viewmodel.dart';
import '../ui/tournaments/widgets/tournament_detail_screen.dart';
import 'routes.dart';

// Pages that both the app's router (router.dart) and the website's
// (web_router.dart) show, with their view models wired up once.

Widget signInPage() => ViewModelHost(
  create: (c) => SignInViewModel(authRepository: c.read()),
  builder: (_, vm) => SignInScreen(viewModel: vm),
);

Widget signUpPage() => ViewModelHost(
  create: (c) => SignUpViewModel(authRepository: c.read()),
  builder: (_, vm) => SignUpScreen(viewModel: vm),
);

Widget chooseUsernamePage() => ViewModelHost(
  create: (c) => ChooseUsernameViewModel(authRepository: c.read()),
  builder: (_, vm) => ChooseUsernameScreen(viewModel: vm),
);

/// Explore, with its search and filter from `?q=` and `?only=`.
Widget explorePage(GoRouterState state) => ViewModelHost(
  create: (c) =>
      TeamSearchViewModel(teamRepository: c.read(), authRepository: c.read()),
  builder: (_, vm) => ViewModelHost(
    create: (c) => PlayerSearchViewModel(profileRepository: c.read()),
    builder: (_, players) => ViewModelHost(
      create: (c) => TournamentsViewModel(tournamentRepository: c.read()),
      builder: (_, events) => ExploreScreen(
        viewModel: vm,
        players: players,
        events: events,
        initialQuery: state.uri.queryParameters['q'] ?? '',
        initialFilter: ExploreFilter.values
            .where((f) => f.name == state.uri.queryParameters['only'])
            .firstOrNull,
      ),
    ),
  ),
);

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

Widget eventsPage() => ViewModelHost(
  create: (c) => TournamentsViewModel(tournamentRepository: c.read()),
  builder: (_, vm) => EventsScreen(viewModel: vm),
);

Widget tournamentPage(String id) => ViewModelHost(
  key: ValueKey('tournament-$id'),
  create: (c) => TournamentDetailViewModel(
    tournamentId: id,
    tournamentRepository: c.read(),
    usauScheduleRepository: c.read(),
    followRepository: c.read(),
    notificationRepository: c.read(),
    authRepository: c.read(),
  ),
  builder: (_, vm) => TournamentDetailScreen(viewModel: vm),
);

Widget rankingsPage() => ViewModelHost(
  create: (c) => RankingsViewModel(rankingRepository: c.read()),
  builder: (_, vm) => RankingsScreen(viewModel: vm),
);

/// A USA Ultimate team page, from Rankings or Teams search.
Widget usauTeamPage(GoRouterState state) {
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
      usauTeamRepository: c.read(),
      rankingRepository: c.read(),
    ),
    builder: (_, vm) => TeamHomeScreen(
      viewModel: vm,
      section: TeamSection.fromPath(state.uri.queryParameters['section']),
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
    tournamentRepository: c.read(),
    followRepository: c.read(),
    userPostRepository: c.read(),
    filePicker: c.read(),
  ),
  builder: (_, vm) => HomeScreen(viewModel: vm),
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
    ),
    builder: (_, vm) => PostDetailScreen(
      viewModel: vm,
      focusComment: state.uri.queryParameters['comment'] == '1',
    ),
  );
}
