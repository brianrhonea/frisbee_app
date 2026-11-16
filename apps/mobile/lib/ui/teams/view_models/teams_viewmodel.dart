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
    acceptInvite = Command1<String, TeamInvite>(_acceptInvite);
    declineInvite = Command1<void, TeamInvite>(_declineInvite);
    _subscribe();
  }

  final TeamRepository _teams;
  final AuthRepository _auth;
  StreamSubscription<List<Team>>? _sub;
  StreamSubscription<List<TeamInvite>>? _invitesSub;

  List<TeamInvite> _invites = const [];

  /// Invitations from owners and organizers, newest first.
  List<TeamInvite> get invites => _invites;

  /// Listings of invited teams, to tell club teams (16 and over) apart.
  final _inviteListings = <String, StreamSubscription<TeamListing?>>{};
  final _clubInvites = <String>{};

  /// Whether [invite] is to a club team, which is for players 16 and over
  /// (shown on the invite; the API checks their age when they accept).
  bool isClubInvite(TeamInvite invite) => _clubInvites.contains(invite.teamId);

  void _watchInviteListings() {
    final ids = {
      for (final i in _invites)
        if (!i.isCommunity) i.teamId,
    };
    for (final id in _inviteListings.keys.toList()) {
      if (ids.contains(id)) continue;
      _inviteListings.remove(id)?.cancel();
      _clubInvites.remove(id);
    }
    for (final id in ids) {
      _inviteListings[id] ??= _teams.watchListing(id).listen((l) {
        final club = l?.isClubTeam ?? false;
        if (club == _clubInvites.contains(id)) return;
        club ? _clubInvites.add(id) : _clubInvites.remove(id);
        notifyListeners();
      }, onError: (Object _) {});
    }
  }

  /// Joins the invite's team; result value is the team id.
  late final Command1<String, TeamInvite> acceptInvite;

  late final Command1<void, TeamInvite> declineInvite;

  List<Team> _items = const [];

  /// Everything the user is on, teams and groups.
  List<Team> get all => _items;

  List<Team> get teams => _items.where((t) => !t.isCommunity).toList();

  List<Team> get groups => _items.where((t) => t.isCommunity).toList();

  /// The user's other teams, by name. A team that one of their
  /// communities lists ([viaCommunity]) is shown under that community
  /// instead, so a community's admins don't get one card per team.
  List<Team> get yourTeams =>
      teams.where((t) => !viaCommunity(t)).toList()..sort(_byName);

  /// The user's communities (groups, schools and clubs), by name; each
  /// lists its teams ([Team.sortedLinkedTeams]).
  List<Team> get communities => groups..sort(_byName);

  /// [team] is linked to one of the user's communities, which lists it.
  bool viaCommunity(Team team) =>
      team.inCommunity &&
      _items.any(
        (c) => c.id == team.orgId && c.linkedTeams.containsKey(team.id),
      );

  /// Whether the user is on the community's team [teamId].
  bool isOn(String teamId) => _items.any((t) => t.id == teamId);

  static int _byName(Team a, Team b) =>
      a.name.toLowerCase().compareTo(b.name.toLowerCase());

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
    _invitesSub?.cancel();
    _invitesSub = _teams.watchMyInvites(user.uid).listen((invites) {
      _invites = invites;
      _watchInviteListings();
      notifyListeners();
    }, onError: (Object _) {});
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

  Future<Result<String>> _acceptInvite(TeamInvite invite) async {
    final user = _auth.currentUser;
    if (user == null) return Result.error(Exception('Not signed in'));
    final result = await _teams.acceptInvite(invite, user);
    return switch (result) {
      Ok() => Result.ok(invite.teamId),
      Error(:final error) => Result.error(error),
    };
  }

  Future<Result<void>> _declineInvite(TeamInvite invite) =>
      _teams.declineInvite(uid, invite.teamId);

  @override
  void dispose() {
    _sub?.cancel();
    _invitesSub?.cancel();
    for (final s in _inviteListings.values) {
      s.cancel();
    }
    super.dispose();
  }
}
