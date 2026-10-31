import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../data/repositories/auth/auth_repository.dart';
import '../data/repositories/auth/auth_repository_firebase.dart';
import '../data/repositories/event/event_repository.dart';
import '../data/repositories/event/event_repository_firebase.dart';
import '../data/repositories/playbook/play_repository.dart';
import '../data/repositories/playbook/play_repository_firebase.dart';
import '../data/repositories/ranking/ranking_repository.dart';
import '../data/repositories/stats/stats_repository.dart';
import '../data/repositories/stats/stats_repository_firebase.dart';
import '../data/repositories/ranking/ranking_repository_usau.dart';
import '../data/repositories/team/team_repository.dart';
import '../data/repositories/team/team_repository_firebase.dart';
import '../data/repositories/tournament/tournament_repository.dart';
import '../data/repositories/tournament/tournament_repository_usau.dart';
import '../data/repositories/usau_schedule/usau_schedule_repository.dart';
import '../data/repositories/usau_schedule/usau_schedule_repository_usau.dart';
import '../data/repositories/usau_team/usau_team_repository.dart';
import '../data/repositories/usau_team/usau_team_repository_usau.dart';
import '../data/services/auth_service.dart';
import '../data/services/usau/usau_client.dart';

/// Services and repositories backed by Firebase.
List<SingleChildWidget> get firebaseProviders => [
  Provider(create: (_) => AuthService()),
  ChangeNotifierProvider<AuthRepository>(
    create: (context) =>
        AuthRepositoryFirebase(authService: context.read<AuthService>()),
  ),
  Provider<TeamRepository>(create: (_) => TeamRepositoryFirebase()),
  Provider<PlayRepository>(create: (_) => PlayRepositoryFirebase()),
  Provider<EventRepository>(create: (_) => EventRepositoryFirebase()),
  Provider<StatsRepository>(
    create: (context) =>
        StatsRepositoryFirebase(teamRepository: context.read<TeamRepository>()),
  ),
  // USA Ultimate data is scraped by the app and held in memory until the
  // Cloud Functions in functions/src/usau are deployed. To switch back, use
  // TournamentRepositoryFirebase and RankingRepositoryFirebase here.
  Provider(create: (_) => UsauClient()),
  Provider<TournamentRepository>(
    create: (context) =>
        TournamentRepositoryUsau(client: context.read<UsauClient>()),
  ),
  Provider<RankingRepository>(
    create: (context) =>
        RankingRepositoryUsau(client: context.read<UsauClient>()),
  ),
  Provider<UsauTeamRepository>(
    create: (context) =>
        UsauTeamRepositoryUsau(client: context.read<UsauClient>()),
  ),
  Provider<UsauScheduleRepository>(
    create: (context) =>
        UsauScheduleRepositoryUsau(client: context.read<UsauClient>()),
  ),
];
