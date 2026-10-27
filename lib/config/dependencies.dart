import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../data/repositories/auth/auth_repository.dart';
import '../data/repositories/auth/auth_repository_firebase.dart';
import '../data/repositories/playbook/play_repository.dart';
import '../data/repositories/playbook/play_repository_firebase.dart';
import '../data/repositories/ranking/ranking_repository.dart';
import '../data/repositories/ranking/ranking_repository_firebase.dart';
import '../data/repositories/team/team_repository.dart';
import '../data/repositories/team/team_repository_firebase.dart';
import '../data/repositories/tournament/tournament_repository.dart';
import '../data/repositories/tournament/tournament_repository_firebase.dart';
import '../data/services/auth_service.dart';

/// Services and repositories backed by Firebase.
List<SingleChildWidget> get firebaseProviders => [
  Provider(create: (_) => AuthService()),
  ChangeNotifierProvider<AuthRepository>(
    create: (context) =>
        AuthRepositoryFirebase(authService: context.read<AuthService>()),
  ),
  Provider<TeamRepository>(create: (_) => TeamRepositoryFirebase()),
  Provider<PlayRepository>(create: (_) => PlayRepositoryFirebase()),
  Provider<TournamentRepository>(create: (_) => TournamentRepositoryFirebase()),
  Provider<RankingRepository>(create: (_) => RankingRepositoryFirebase()),
];
