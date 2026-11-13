import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../domain/models/team.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

class CreateTeamViewModel extends ChangeNotifier {
  CreateTeamViewModel({
    required TeamRepository teamRepository,
    required AuthRepository authRepository,
  }) : _teams = teamRepository,
       _auth = authRepository {
    create = Command1<String, NewTeam>(_create);
  }

  final TeamRepository _teams;
  final AuthRepository _auth;

  /// Result value is the new team id.
  late final Command1<String, NewTeam> create;

  Future<Result<String>> _create(NewTeam team) async {
    final user = _auth.currentUser;
    if (user == null) return Result.error(Exception('Not signed in'));
    return _teams.createTeam(team, user);
  }
}
