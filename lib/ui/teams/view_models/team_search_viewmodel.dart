import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../domain/models/team.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// Finds teams in the app's public team directory by name or city.
class TeamSearchViewModel extends ChangeNotifier {
  TeamSearchViewModel({
    required TeamRepository teamRepository,
    required AuthRepository authRepository,
  }) : _teams = teamRepository {
    search = Command1<List<TeamListing>, String>(_search);
    final uid = authRepository.currentUser?.uid ?? '';
    _mineSub = _teams.watchMyTeams(uid).listen((teams) {
      _mine = {for (final t in teams) t.id};
      notifyListeners();
    }, onError: (Object _) {});
  }

  static const minQueryLength = 2;

  final TeamRepository _teams;
  late final StreamSubscription<List<Team>> _mineSub;
  Set<String> _mine = const {};

  late final Command1<List<TeamListing>, String> search;

  String _query = '';
  String get query => _query;

  List<TeamListing> get results => switch (search.result) {
    Ok(:final value) => value,
    _ => const [],
  };

  /// True once a search for the current query finished with no matches.
  bool get noMatches =>
      search.completed && results.isEmpty && _query.length >= minQueryLength;

  /// Whether the user is on [teamId], to mark it in the results.
  bool isMine(String teamId) => _mine.contains(teamId);

  Future<Result<List<TeamListing>>> _search(String query) async {
    _query = query.trim();
    if (_query.length < minQueryLength) return const Result.ok([]);
    final result = await _teams.searchTeams(_query);
    // A newer query may have been typed while this one ran.
    if (query.trim() != _query) return const Result.ok([]);
    return result;
  }

  @override
  void dispose() {
    _mineSub.cancel();
    super.dispose();
  }
}
