import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../domain/models/team.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// A team's place in a school or club community, for its admins: find a
/// community and ask to join it, see whether it answered, or leave.
class TeamCommunityViewModel extends ChangeNotifier {
  TeamCommunityViewModel({
    required this.teamId,
    required TeamRepository teamRepository,
    required AuthRepository authRepository,
  }) : _teams = teamRepository,
       _auth = authRepository {
    search = Command1<List<TeamListing>, String>(_search);
    request = Command1<void, TeamListing>(_request);
    leave = Command0<void>(() async {
      final team = _team;
      if (team == null) return Result.error(Exception('Team not loaded'));
      return _teams.leaveCommunity(team);
    });
    _teamSub = _teams.watchTeam(teamId).listen((t) {
      _team = t;
      _watchRequest();
      notifyListeners();
    }, onError: (Object _) {});
  }

  static const minQueryLength = 2;

  final String teamId;
  final TeamRepository _teams;
  final AuthRepository _auth;
  late final StreamSubscription<Team?> _teamSub;
  StreamSubscription<bool>? _requestSub;
  String? _requestOrg;
  bool? _requested;

  late final Command1<List<TeamListing>, String> search;
  late final Command1<void, TeamListing> request;
  late final Command0<void> leave;

  Team? _team;
  Team? get team => _team;

  String get orgName => _team?.orgName ?? '';
  String? get orgId => _team?.orgId;
  bool get inCommunity => _team?.inCommunity ?? false;

  /// Asked, and the request is still waiting.
  bool get pending => (_team?.communityPending ?? false) && _requested != false;

  /// Asked, but the community turned it down (the request is gone and the
  /// team wasn't added).
  bool get declined =>
      (_team?.communityPending ?? false) && _requested == false;

  List<TeamListing> get results => switch (search.result) {
    Ok(:final value) => [
      for (final t in value)
        if (t.isOrganization) t,
    ],
    _ => const [],
  };

  void _watchRequest() {
    final org = _team?.communityPending ?? false ? _team?.orgId : null;
    if (org == _requestOrg) return;
    _requestOrg = org;
    _requestSub?.cancel();
    _requestSub = null;
    _requested = null;
    if (org == null) return;
    _requestSub = _teams.watchLinkRequested(org, teamId).listen((r) {
      _requested = r;
      notifyListeners();
    }, onError: (Object _) {});
  }

  Future<Result<List<TeamListing>>> _search(String query) async {
    final q = query.trim();
    if (q.length < minQueryLength) return const Result.ok([]);
    return _teams.searchTeams(q);
  }

  Future<Result<void>> _request(TeamListing org) async {
    final team = _team;
    final user = _auth.currentUser;
    if (team == null || user == null) {
      return Result.error(Exception('Team not loaded'));
    }
    return _teams.requestCommunityLink(team, org, user);
  }

  @override
  void dispose() {
    _teamSub.cancel();
    _requestSub?.cancel();
    super.dispose();
  }
}
