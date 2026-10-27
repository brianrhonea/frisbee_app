import 'dart:async';

import 'package:frisbee_app/data/repositories/auth/auth_repository.dart';
import 'package:frisbee_app/data/repositories/playbook/play_repository.dart';
import 'package:frisbee_app/data/repositories/team/team_repository.dart';
import 'package:frisbee_app/data/repositories/tournament/tournament_repository.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/play.dart';
import 'package:frisbee_app/domain/models/roster_player.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/tournament.dart';
import 'package:frisbee_app/utils/result.dart';

const testUser = AppUser(uid: 'u1', email: 'a@b.com', displayName: 'Alex');

class FakeAuthRepository extends AuthRepository {
  FakeAuthRepository({AppUser? user, bool ready = true})
    : _user = user,
      _ready = ready;

  AppUser? _user;
  bool _ready;
  Exception? nextError;

  @override
  AppUser? get currentUser => _user;

  @override
  bool get isReady => _ready;

  void setUser(AppUser? user, {bool ready = true}) {
    _user = user;
    _ready = ready;
    notifyListeners();
  }

  Future<Result<void>> _run(void Function() action) async {
    final e = nextError;
    if (e != null) {
      nextError = null;
      return Result.error(e);
    }
    action();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> signInWithEmail(String email, String password) =>
      _run(() => setUser(AppUser(uid: 'u1', email: email)));

  @override
  Future<Result<void>> signUpWithEmail({
    required String email,
    required String password,
    required String displayName,
  }) => _run(
    () => setUser(AppUser(uid: 'u1', email: email, displayName: displayName)),
  );

  @override
  Future<Result<void>> signInWithGoogle() => _run(() => setUser(testUser));

  @override
  Future<Result<void>> signInWithApple() => _run(() => setUser(testUser));

  @override
  Future<Result<void>> sendPasswordReset(String email) => _run(() {});

  @override
  Future<Result<void>> updateDisplayName(String name) => _run(
    () => setUser(
      AppUser(uid: _user!.uid, email: _user!.email, displayName: name),
    ),
  );

  @override
  Future<Result<void>> signOut() => _run(() => setUser(null));

  @override
  Future<Result<void>> deleteAccount() => _run(() => setUser(null));
}

class FakeTeamRepository implements TeamRepository {
  final teams = <String, Team>{};
  final roster = <String, List<RosterPlayer>>{};
  final _teamsController = StreamController<void>.broadcast();
  String? joinedCode;

  void _emit() => _teamsController.add(null);

  @override
  Stream<List<Team>> watchMyTeams(String uid) async* {
    List<Team> mine() =>
        teams.values.where((t) => t.members.containsKey(uid)).toList();
    yield mine();
    yield* _teamsController.stream.map((_) => mine());
  }

  @override
  Stream<Team?> watchTeam(String teamId) async* {
    yield teams[teamId];
    yield* _teamsController.stream.map((_) => teams[teamId]);
  }

  @override
  Future<Result<String>> createTeam(NewTeam team, AppUser owner) async {
    final id = 't${teams.length + 1}';
    teams[id] = Team(
      id: id,
      name: team.name,
      division: team.division,
      level: team.level,
      city: team.city,
      ownerId: owner.uid,
      members: {owner.uid: TeamRole.owner},
      inviteCode: 'CODE$id',
    );
    _emit();
    return Result.ok(id);
  }

  @override
  Future<Result<String>> joinTeam(String inviteCode, AppUser user) async {
    joinedCode = inviteCode;
    final team = teams.values
        .where((t) => t.inviteCode == inviteCode)
        .firstOrNull;
    if (team == null) return Result.error(Exception('No team'));
    teams[team.id] = Team(
      id: team.id,
      name: team.name,
      division: team.division,
      level: team.level,
      ownerId: team.ownerId,
      inviteCode: team.inviteCode,
      members: {...team.members, user.uid: TeamRole.player},
    );
    _emit();
    return Result.ok(team.id);
  }

  @override
  Future<Result<void>> updateTeam(Team team) async {
    teams[team.id] = team;
    _emit();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> regenerateInviteCode(Team team) async =>
      const Result.ok(null);

  @override
  Future<Result<void>> setMemberRole(
    String teamId,
    String uid,
    TeamRole role,
  ) async => const Result.ok(null);

  @override
  Future<Result<void>> removeMember(String teamId, String uid) async =>
      const Result.ok(null);

  @override
  Future<Result<void>> deleteTeam(Team team) async {
    teams.remove(team.id);
    _emit();
    return const Result.ok(null);
  }

  @override
  Stream<List<RosterPlayer>> watchRoster(String teamId) =>
      Stream.value(roster[teamId] ?? const []);

  @override
  Future<Result<void>> savePlayer(String teamId, RosterPlayer player) async =>
      const Result.ok(null);

  @override
  Future<Result<void>> deletePlayer(String teamId, String playerId) async =>
      const Result.ok(null);
}

class FakePlayRepository implements PlayRepository {
  final plays = <String, Play>{};
  int saves = 0;

  @override
  Stream<List<Play>> watchPlays(String teamId) =>
      Stream.value(plays.values.toList());

  @override
  Future<Result<Play>> getPlay(String teamId, String playId) async {
    final p = plays[playId];
    return p == null ? Result.error(Exception('missing')) : Result.ok(p);
  }

  @override
  Future<Result<String>> savePlay(String teamId, Play play, String uid) async {
    saves++;
    final id = play.isNew ? 'p${plays.length + 1}' : play.id;
    plays[id] = play.copyWith(id: id);
    return Result.ok(id);
  }

  @override
  Future<Result<void>> deletePlay(String teamId, String playId) async {
    plays.remove(playId);
    return const Result.ok(null);
  }
}

class FakeTournamentRepository implements TournamentRepository {
  FakeTournamentRepository(this.tournaments);

  final List<Tournament> tournaments;

  @override
  Stream<List<Tournament>> watchTournaments() => Stream.value(tournaments);
}

Team teamWith(Map<String, TeamRole> members, {String id = 't1'}) => Team(
  id: id,
  name: 'Team',
  division: Division.mixed,
  level: CompetitionLevel.club,
  ownerId: members.entries.firstWhere((e) => e.value == TeamRole.owner).key,
  members: members,
  inviteCode: 'CODE$id',
);
