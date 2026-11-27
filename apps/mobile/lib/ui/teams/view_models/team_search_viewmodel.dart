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
  }) : _teams = teamRepository,
       _auth = authRepository {
    search = Command1<List<TeamListing>, String>(_search);
    join = Command1<void, TeamListing>(_join);
    final uid = authRepository.currentUser?.uid ?? '';
    _mineSub = _teams.watchMyTeams(uid).listen((teams) {
      _mine = {for (final t in teams) t.id};
      notifyListeners();
    }, onError: (Object _) {});
  }

  static const minQueryLength = 2;

  final TeamRepository _teams;
  final AuthRepository _auth;
  late final StreamSubscription<List<Team>> _mineSub;
  Set<String> _mine = const {};

  late final Command1<List<TeamListing>, String> search;

  String _query = '';
  String get query => _query;

  /// Teams and groups, or only one kind; null shows both. Groups include
  /// school and club communities.
  TeamKind? _kind;
  TeamKind? get kind => _kind;

  void setKind(TeamKind? kind) {
    _kind = kind;
    notifyListeners();
  }

  List<TeamListing> get results => switch (search.result) {
    Ok(:final value) => [
      for (final t in value)
        if (_kind == null ||
            t.kind == _kind ||
            (_kind == TeamKind.community && t.kind.isGroupLike))
          t,
    ],
    _ => const [],
  };

  /// True once a search for the current query finished with no matches.
  bool get noMatches =>
      search.completed && results.isEmpty && _query.length >= minQueryLength;

  /// Whether the user is on [teamId], to mark it in the results.
  bool isMine(String teamId) => _mine.contains(teamId);

  /// Joins an open group, or asks to join one that approves members or a
  /// team that takes join requests: what the team page's join card does.
  /// The server still decides (a club team's age rule, for one), and its
  /// error is the command's result.
  late final Command1<void, TeamListing> join;

  final Set<String> _requested = {};

  /// Whether the results show a Join button for [t]: signed in, not on it
  /// already, and it has a join path that needs no invite code. A plain
  /// team that joins only with a code (and has join requests off) has none.
  bool canJoin(TeamListing t) =>
      _auth.currentUser != null &&
      !isMine(t.id) &&
      !_requested.contains(t.id) &&
      (t.isCommunity || t.takesRequests);

  /// The user asked to join [t] and is waiting for approval.
  bool requested(String teamId) => _requested.contains(teamId);

  /// "Ask to join" where an admin approves, "Join" where it's open.
  String joinLabel(TeamListing t) => t.takesRequests ? 'Ask to join' : 'Join';

  Future<Result<void>> _join(TeamListing t) async {
    final me = _auth.currentUser;
    if (me == null) return Result.error(Exception('Not signed in'));
    if (!canJoin(t)) {
      return Result.error(Exception('Join a team with an invite code.'));
    }
    if (t.takesRequests) {
      final result = await _teams.requestToJoin(t.id, me);
      if (result is Ok) {
        _requested.add(t.id);
        notifyListeners();
      }
      return result;
    }
    // Joined: the team stream marks it as the user's.
    return _teams.joinGroup(t.id, me);
  }

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
    join.dispose();
    _mineSub.cancel();
    super.dispose();
  }
}
