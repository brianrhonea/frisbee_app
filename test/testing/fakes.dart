import 'dart:async';

import 'package:frisbee_app/data/repositories/auth/auth_repository.dart';
import 'package:frisbee_app/data/repositories/event/event_repository.dart';
import 'package:frisbee_app/data/repositories/playbook/play_repository.dart';
import 'package:frisbee_app/data/repositories/team/team_repository.dart';
import 'package:frisbee_app/data/repositories/tournament/tournament_repository.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/play.dart';
import 'package:frisbee_app/domain/models/roster_player.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/team_event.dart';
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
  Future<Result<void>> setStatKeeper(
    String teamId,
    String uid, {
    required bool on,
  }) async {
    final t = teams[teamId];
    if (t == null) return Result.error(Exception('No team'));
    teams[teamId] = Team(
      id: t.id,
      name: t.name,
      division: t.division,
      level: t.level,
      city: t.city,
      ownerId: t.ownerId,
      inviteCode: t.inviteCode,
      members: t.members,
      memberNames: t.memberNames,
      statKeepers: on
          ? {...t.statKeepers, uid}
          : ({...t.statKeepers}..remove(uid)),
    );
    _emit();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> transferOwnership(
    String teamId, {
    required String ownerUid,
    required String newOwnerUid,
  }) async {
    final t = teams[teamId];
    if (t == null) return Result.error(Exception('No team'));
    teams[teamId] = Team(
      id: t.id,
      name: t.name,
      division: t.division,
      level: t.level,
      city: t.city,
      ownerId: newOwnerUid,
      inviteCode: t.inviteCode,
      members: {
        ...t.members,
        newOwnerUid: TeamRole.owner,
        ownerUid: TeamRole.player,
      },
      memberNames: t.memberNames,
      statKeepers: t.statKeepers,
    );
    _emit();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> removeMember(String teamId, String uid) async =>
      const Result.ok(null);

  @override
  Future<Result<void>> deleteTeam(Team team) async {
    teams.remove(team.id);
    _emit();
    return const Result.ok(null);
  }

  final syncs = <List<RosterPlayer>>[];

  @override
  Future<Result<void>> linkUsauTeam(
    String teamId, {
    String? url,
    String? name,
  }) async {
    final t = teams[teamId];
    if (t == null) return Result.error(Exception('No team'));
    teams[teamId] = Team(
      id: t.id,
      name: t.name,
      division: t.division,
      level: t.level,
      city: t.city,
      ownerId: t.ownerId,
      inviteCode: t.inviteCode,
      members: t.members,
      memberNames: t.memberNames,
      statKeepers: t.statKeepers,
      usauUrl: url,
      usauName: url == null ? null : name,
    );
    _emit();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> applyRosterSync(
    String teamId,
    List<RosterPlayer> players,
  ) async {
    syncs.add(players);
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

Team teamWith(
  Map<String, TeamRole> members, {
  String id = 't1',
  Set<String> statKeepers = const {},
}) => Team(
  id: id,
  statKeepers: statKeepers,
  name: 'Team',
  division: Division.mixed,
  level: CompetitionLevel.club,
  ownerId: members.entries.firstWhere((e) => e.value == TeamRole.owner).key,
  members: members,
  inviteCode: 'CODE$id',
);

class FakeEventRepository implements EventRepository {
  final events = <String, TeamEvent>{};
  final _changes = StreamController<void>.broadcast();
  bool? lastClearVotes;

  void _emit() => _changes.add(null);

  List<TeamEvent> _sorted() =>
      events.values.toList()..sort((a, b) => a.startsAt.compareTo(b.startsAt));

  @override
  Stream<List<TeamEvent>> watchEvents(String teamId) async* {
    yield _sorted();
    yield* _changes.stream.map((_) => _sorted());
  }

  @override
  Stream<TeamEvent?> watchEvent(String teamId, String eventId) async* {
    yield events[eventId];
    yield* _changes.stream.map((_) => events[eventId]);
  }

  @override
  Future<Result<String>> saveEvent(
    String teamId,
    TeamEvent event,
    String uid, {
    bool clearVotes = false,
  }) async {
    lastClearVotes = clearVotes;
    final id = event.isNew ? 'e${events.length + 1}' : event.id;
    events[id] = event.copyWith(id: id);
    _emit();
    return Result.ok(id);
  }

  @override
  Future<Result<void>> deleteEvent(String teamId, String eventId) async {
    events.remove(eventId);
    _emit();
    return const Result.ok(null);
  }

  TeamEvent _with(
    String eventId, {
    Map<String, RsvpStatus>? rsvps,
    Map<String, Set<Reaction>>? reactions,
    Map<String, List<String>>? votes,
  }) {
    final e = events[eventId]!;
    return TeamEvent(
      id: e.id,
      title: e.title,
      type: e.type,
      startsAt: e.startsAt,
      endsAt: e.endsAt,
      location: e.location,
      notes: e.notes,
      poll: e.poll,
      rsvps: rsvps ?? e.rsvps,
      reactions: reactions ?? e.reactions,
      votes: votes ?? e.votes,
      createdBy: e.createdBy,
    );
  }

  @override
  Future<Result<void>> setRsvp(
    String teamId,
    String eventId,
    String uid,
    RsvpStatus? status,
  ) async {
    final e = events[eventId]!;
    final rsvps = {...e.rsvps};
    status == null ? rsvps.remove(uid) : rsvps[uid] = status;
    final going = status == RsvpStatus.going;
    events[eventId] = _with(
      eventId,
      rsvps: rsvps,
      reactions: going ? null : ({...e.reactions}..remove(uid)),
      votes: going ? null : ({...e.votes}..remove(uid)),
    );
    _emit();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> setReaction(
    String teamId,
    String eventId,
    String uid,
    Reaction reaction, {
    required bool on,
  }) async {
    final reactions = {...events[eventId]!.reactions};
    final mine = {...?reactions[uid]};
    on ? mine.add(reaction) : mine.remove(reaction);
    reactions[uid] = mine;
    events[eventId] = _with(eventId, reactions: reactions);
    _emit();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> setVotes(
    String teamId,
    String eventId,
    String uid,
    List<String> optionIds,
  ) async {
    final votes = {...events[eventId]!.votes};
    optionIds.isEmpty ? votes.remove(uid) : votes[uid] = optionIds;
    events[eventId] = _with(eventId, votes: votes);
    _emit();
    return const Result.ok(null);
  }
}
