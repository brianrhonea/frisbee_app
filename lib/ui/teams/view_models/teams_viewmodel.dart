import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../domain/models/team.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

class TeamsViewModel extends ChangeNotifier {
  TeamsViewModel({
    required TeamRepository teamRepository,
    required AuthRepository authRepository,
  }) : _teams = teamRepository,
       _auth = authRepository {
    joinTeam = Command1<String, String>(_joinTeam);
    _subscribe();
  }

  final TeamRepository _teams;
  final AuthRepository _auth;
  StreamSubscription<List<Team>>? _sub;

  List<Team> _items = const [];
  List<Team> get teams => _items;

  bool _loading = true;
  bool get loading => _loading;

  Object? _error;
  Object? get error => _error;

  /// Joins by invite code; result value is the team id.
  late final Command1<String, String> joinTeam;

  String get uid => _auth.currentUser?.uid ?? '';

  TeamRole? roleIn(Team team) => team.roleOf(uid);

  void _subscribe() {
    final user = _auth.currentUser;
    if (user == null) return;
    _sub?.cancel();
    _loading = true;
    _error = null;
    _sub = _teams
        .watchMyTeams(user.uid)
        .listen(
          (teams) {
            _items = teams;
            _loading = false;
            _error = null;
            notifyListeners();
          },
          onError: (Object e) {
            _error = e;
            _loading = false;
            notifyListeners();
          },
        );
  }

  void retry() {
    _subscribe();
    notifyListeners();
  }

  Future<Result<String>> _joinTeam(String code) async {
    final user = _auth.currentUser;
    if (user == null) return Result.error(Exception('Not signed in'));
    return _teams.joinTeam(code, user);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
