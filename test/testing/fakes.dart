import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:frisbee_app/data/repositories/auth/auth_repository.dart';
import 'package:frisbee_app/data/repositories/chat/chat_repository.dart';
import 'package:frisbee_app/data/repositories/direct_message/direct_message_repository.dart';
import 'package:frisbee_app/data/repositories/event/event_repository.dart';
import 'package:frisbee_app/data/repositories/notification/notification_repository.dart';
import 'package:frisbee_app/data/repositories/playbook/play_repository.dart';
import 'package:frisbee_app/data/repositories/ranking/ranking_repository.dart';
import 'package:frisbee_app/data/repositories/team/team_repository.dart';
import 'package:frisbee_app/data/repositories/team_post/team_post_repository.dart';
import 'package:frisbee_app/data/repositories/theme/theme_repository.dart';
import 'package:frisbee_app/data/repositories/tournament/tournament_repository.dart';
import 'package:frisbee_app/data/repositories/usau_schedule/usau_schedule_repository.dart';
import 'package:frisbee_app/data/services/file_picker_service.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/chat.dart';
import 'package:frisbee_app/domain/models/direct_message.dart';
import 'package:frisbee_app/domain/models/notification.dart';
import 'package:frisbee_app/domain/models/play.dart';
import 'package:frisbee_app/domain/models/ranking.dart';
import 'package:frisbee_app/domain/models/roster_player.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/team_event.dart';
import 'package:frisbee_app/domain/models/team_post.dart';
import 'package:frisbee_app/domain/models/tournament.dart';
import 'package:frisbee_app/domain/models/usau_schedule.dart';
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

  /// teamId → invite code; unlisted teams use `CODE` plus the team id.
  final codes = <String, String>{};

  /// Teams whose invite code was watched, to check who may read it.
  final inviteWatches = <String>[];

  String _codeOf(String teamId) => codes[teamId] ?? 'CODE$teamId';

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
      kind: team.kind,
      description: team.description,
      requiresApproval: team.requiresApproval,
      location: team.location,
    );
    if (team.kind == TeamKind.community) {
      listings[id] = team.listing(id);
    }
    _emit();
    return Result.ok(id);
  }

  /// teamId → pending join requests.
  final joinRequests = <String, List<GroupJoinRequest>>{};

  void _addMember(String teamId, String uid, String name) {
    final t = teams[teamId]!;
    teams[teamId] = t.copyWith(
      members: {...t.members, uid: TeamRole.player},
      memberNames: {...t.memberNames, uid: name},
    );
  }

  @override
  Future<Result<void>> joinGroup(String teamId, AppUser user) async {
    final t = teams[teamId];
    if (t == null || !t.isCommunity || t.requiresApproval) {
      return Result.error(Exception('permission-denied'));
    }
    _addMember(teamId, user.uid, user.label);
    _emit();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> requestToJoin(String teamId, AppUser user) async {
    (joinRequests[teamId] ??= []).add(
      GroupJoinRequest(uid: user.uid, name: user.label),
    );
    _emit();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> cancelJoinRequest(String teamId, String uid) =>
      declineJoinRequest(teamId, uid);

  @override
  Stream<bool> watchMyJoinRequest(String teamId, String uid) async* {
    bool mine() => (joinRequests[teamId] ?? []).any((r) => r.uid == uid);
    yield mine();
    yield* _teamsController.stream.map((_) => mine());
  }

  @override
  Stream<List<GroupJoinRequest>> watchJoinRequests(String teamId) async* {
    yield [...?joinRequests[teamId]];
    yield* _teamsController.stream.map((_) => [...?joinRequests[teamId]]);
  }

  @override
  Future<Result<void>> approveJoinRequest(
    String teamId,
    GroupJoinRequest request,
  ) async {
    _addMember(teamId, request.uid, request.name);
    joinRequests[teamId]?.removeWhere((r) => r.uid == request.uid);
    _emit();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> declineJoinRequest(String teamId, String uid) async {
    joinRequests[teamId]?.removeWhere((r) => r.uid == uid);
    _emit();
    return const Result.ok(null);
  }

  @override
  Future<Result<String>> joinTeam(String inviteCode, AppUser user) async {
    joinedCode = inviteCode;
    final team = teams.values
        .where((t) => _codeOf(t.id) == inviteCode)
        .firstOrNull;
    if (team == null) return Result.error(Exception('No team'));
    teams[team.id] = Team(
      id: team.id,
      name: team.name,
      division: team.division,
      level: team.level,
      ownerId: team.ownerId,
      members: {...team.members, user.uid: TeamRole.player},
    );
    _emit();
    return Result.ok(team.id);
  }

  @override
  Future<Result<void>> updateTeam(Team team) async {
    teams[team.id] = team;
    listings[team.id] = TeamListing.of(team);
    _emit();
    return const Result.ok(null);
  }

  /// The public team directory; teams appear here only once listed.
  final listings = <String, TeamListing>{};

  /// Teams whose listing was (re)published.
  final published = <String>[];

  @override
  Future<Result<List<TeamListing>>> searchTeams(String query) async =>
      Result.ok([
        for (final l in listings.values)
          if (l.matches(query)) l,
      ]);

  @override
  Stream<TeamListing?> watchListing(String teamId) async* {
    yield listings[teamId];
    yield* _teamsController.stream.map((_) => listings[teamId]);
  }

  @override
  Future<Result<void>> publishListing(Team team) async {
    published.add(team.id);
    listings[team.id] = TeamListing.of(team);
    _emit();
    return const Result.ok(null);
  }

  @override
  Stream<String?> watchInviteCode(String teamId) async* {
    inviteWatches.add(teamId);
    yield _codeOf(teamId);
    yield* _teamsController.stream.map((_) => _codeOf(teamId));
  }

  @override
  Future<Result<void>> regenerateInviteCode(String teamId) async {
    codes[teamId] = 'NEW$teamId';
    _emit();
    return const Result.ok(null);
  }

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
  Stream<List<RosterPlayer>> watchRoster(
    String teamId, {
    bool withStatus = false,
  }) => Stream.value([
    for (final p in roster[teamId] ?? const <RosterPlayer>[])
      withStatus
          ? p
          : RosterPlayer(
              id: p.id,
              name: p.name,
              number: p.number,
              position: p.position,
              userId: p.userId,
            ),
  ]);

  @override
  Future<Result<void>> savePlayer(String teamId, RosterPlayer player) async =>
      const Result.ok(null);

  @override
  Future<Result<void>> deletePlayer(String teamId, String playerId) async =>
      const Result.ok(null);
}

class FakePlayRepository implements PlayRepository {
  final plays = <String, Play>{};

  /// Per-team plays; teams not listed here see [plays].
  final byTeam = <String, List<Play>>{};
  int saves = 0;

  @override
  Stream<List<Play>> watchPlays(String teamId) =>
      Stream.value(byTeam[teamId] ?? plays.values.toList());

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

class FakeUsauScheduleRepository implements UsauScheduleRepository {
  FakeUsauScheduleRepository({this.schedules = const {}});

  /// Each division's schedule; a division mapped to null fails to load.
  final Map<UsauDivision, UsauDivisionSchedule?> schedules;
  final requests = <(UsauDivision, bool)>[];

  /// When set, schedule loads wait for it to complete.
  Completer<void>? hold;

  @override
  Future<Result<List<UsauDivision>>> getDivisions(String eventUrl) async =>
      Result.ok(schedules.keys.toList());

  @override
  Future<Result<UsauDivisionSchedule>> getSchedule(
    String eventUrl,
    UsauDivision division, {
    bool refresh = false,
  }) async {
    requests.add((division, refresh));
    await hold?.future;
    final s = schedules[division];
    return s == null ? Result.error(Exception('No schedule')) : Result.ok(s);
  }
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
);

class FakeRankingRepository implements RankingRepository {
  FakeRankingRepository(this.divisions);

  final List<RankingDivision> divisions;

  @override
  Stream<List<RankingDivision>> watchDivisions() => Stream.value(divisions);
}

class FakeEventRepository implements EventRepository {
  final events = <String, TeamEvent>{};

  /// Per-team events for multi-team tests; teams not listed here see
  /// [events].
  final byTeam = <String, Map<String, TeamEvent>>{};
  final _changes = StreamController<void>.broadcast();
  bool? lastClearVotes;

  void emit() => _changes.add(null);

  List<TeamEvent> _sorted(String teamId) =>
      (byTeam[teamId] ?? events).values.toList()
        ..sort((a, b) => a.startsAt.compareTo(b.startsAt));

  @override
  Stream<List<TeamEvent>> watchEvents(String teamId) async* {
    yield _sorted(teamId);
    yield* _changes.stream.map((_) => _sorted(teamId));
  }

  @override
  Stream<TeamEvent?> watchEvent(String teamId, String eventId) async* {
    yield events[eventId];
    yield* _changes.stream.map((_) => events[eventId]);
  }

  List<TeamEvent> _public(String teamId) => [
    for (final e in _sorted(teamId))
      if (e.isPublic)
        TeamEvent(
          id: e.id,
          title: e.title,
          type: e.type,
          startsAt: e.startsAt,
          endsAt: e.endsAt,
          location: e.location,
          notes: e.notes,
          isPublic: true,
        ),
  ];

  @override
  Stream<List<TeamEvent>> watchPublicEvents(String teamId) async* {
    yield _public(teamId);
    yield* _changes.stream.map((_) => _public(teamId));
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
    emit();
    return Result.ok(id);
  }

  @override
  Future<Result<void>> deleteEvent(String teamId, String eventId) async {
    (byTeam[teamId] ?? events).remove(eventId);
    emit();
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
    emit();
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
    emit();
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
    emit();
    return const Result.ok(null);
  }

  /// Personal events, keyed by uid then event id.
  final mine = <String, Map<String, TeamEvent>>{};

  List<TeamEvent> _mineSorted(String uid) =>
      (mine[uid] ?? const {}).values.toList()
        ..sort((a, b) => a.startsAt.compareTo(b.startsAt));

  @override
  Stream<List<TeamEvent>> watchMyEvents(String uid) async* {
    yield _mineSorted(uid);
    yield* _changes.stream.map((_) => _mineSorted(uid));
  }

  @override
  Stream<TeamEvent?> watchMyEvent(String uid, String eventId) async* {
    yield mine[uid]?[eventId];
    yield* _changes.stream.map((_) => mine[uid]?[eventId]);
  }

  @override
  Future<Result<String>> saveMyEvent(String uid, TeamEvent event) async {
    final events = mine[uid] ??= {};
    final id = event.isNew ? 'm${events.length + 1}' : event.id;
    events[id] = event.copyWith(id: id);
    emit();
    return Result.ok(id);
  }

  @override
  Future<Result<void>> deleteMyEvent(String uid, String eventId) async {
    mine[uid]?.remove(eventId);
    emit();
    return const Result.ok(null);
  }
}

class FakeThemeRepository extends ThemeRepository {
  ThemeMode _mode = ThemeMode.system;

  @override
  ThemeMode get themeMode => _mode;

  @override
  Future<Result<void>> setThemeMode(ThemeMode mode) async {
    _mode = mode;
    notifyListeners();
    return const Result.ok(null);
  }
}

class FakeChatRepository implements ChatRepository {
  final rooms = <String, ChatRoom>{};
  final messages = <String, List<ChatMessage>>{};
  final files = <String, Uint8List>{};
  int generalEnsured = 0;
  Exception? sendError;
  final _changes = StreamController<void>.broadcast();

  void emit() => _changes.add(null);

  /// Subscribes to changes before the first value, so changes made by a
  /// listener reacting to that value aren't lost.
  Stream<T> _watch<T>(T Function() read) {
    late StreamController<T> controller;
    StreamSubscription<void>? sub;
    controller = StreamController<T>(
      onListen: () {
        sub = _changes.stream.listen((_) => controller.add(read()));
        controller.add(read());
      },
      onCancel: () => sub?.cancel(),
    );
    return controller.stream;
  }

  @override
  Stream<List<ChatRoom>> watchRooms(Team team, String uid) => _watch(
    () =>
        rooms.values
            .where((r) => team.canEdit(uid) || r.accessFor(team, uid).canRead)
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name)),
  );

  @override
  Stream<ChatRoom?> watchRoom(String teamId, String roomId) =>
      _watch(() => rooms[roomId]);

  @override
  Future<Result<String>> saveRoom(
    String teamId,
    ChatRoom room,
    String uid,
  ) async {
    final id = room.isNew ? 'room${rooms.length + 1}' : room.id;
    rooms[id] = ChatRoom.fromMap(id, {...room.toMap(), 'createdBy': uid});
    emit();
    return Result.ok(id);
  }

  @override
  Future<Result<void>> deleteRoom(String teamId, String roomId) async {
    rooms.remove(roomId);
    messages.remove(roomId);
    emit();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> ensureGeneralRoom(String teamId, String uid) async {
    generalEnsured++;
    rooms.putIfAbsent(ChatRoom.generalId, ChatRoom.general);
    emit();
    return const Result.ok(null);
  }

  @override
  Stream<List<ChatMessage>> watchMessages(
    String teamId,
    String roomId, {
    required int limit,
  }) => _watch(() {
    final all = messages[roomId] ?? const <ChatMessage>[];
    return all.skip(all.length > limit ? all.length - limit : 0).toList();
  });

  @override
  Future<Result<void>> sendMessage(
    String teamId,
    String roomId, {
    required AppUser author,
    required String text,
    List<NewAttachment> attachments = const [],
  }) async {
    if (sendError case final e?) return Result.error(e);
    final list = messages.putIfAbsent(roomId, () => []);
    final id = 'm${list.length + 1}';
    list.add(
      ChatMessage(
        id: id,
        authorId: author.uid,
        authorName: author.label,
        text: text.trim(),
        createdAt: DateTime(2026, 10, 30, 12, list.length),
        attachments: [
          for (final (i, a) in attachments.indexed)
            ChatAttachment(
              path: '$roomId/$id/$i',
              name: a.name,
              contentType: a.contentType,
              size: a.size,
            ),
        ],
      ),
    );
    for (final (i, a) in attachments.indexed) {
      files['$roomId/$id/$i'] = a.bytes;
    }
    emit();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> deleteMessage(
    String teamId,
    String roomId,
    ChatMessage message,
  ) async {
    messages[roomId]?.removeWhere((m) => m.id == message.id);
    emit();
    return const Result.ok(null);
  }

  @override
  Future<Result<Uint8List>> downloadAttachment(ChatAttachment a) async {
    final f = files[a.path];
    return f == null ? Result.error(Exception('missing')) : Result.ok(f);
  }
}

class FakeFilePickerService implements FilePickerService {
  /// Returned by the next [pick].
  List<PickedFile> next = const [];
  final saved = <String>[];

  static PickedFile file(String name, int size) =>
      PickedFile(name: name, size: size, read: () async => Uint8List(size));

  @override
  Future<List<PickedFile>> pick({bool imagesOnly = false}) async => next;

  /// Returned by the next [pickVideo].
  PickedFile? nextVideo;

  @override
  Future<PickedFile?> pickVideo(List<String> extensions) async => nextVideo;

  @override
  Future<bool> save(String fileName, Uint8List bytes, String mimeType) async {
    saved.add(fileName);
    return true;
  }
}

class FakeDirectMessageRepository implements DirectMessageRepository {
  final profiles = <UserProfile>[];
  final conversations = <String, Conversation>{};
  final messages = <String, List<ChatMessage>>{};
  final reads = <String>[];
  final _changes = StreamController<void>.broadcast();

  void emit() => _changes.add(null);

  Stream<T> _watch<T>(T Function() read) {
    late StreamController<T> controller;
    StreamSubscription<void>? sub;
    controller = StreamController<T>(
      onListen: () {
        sub = _changes.stream.listen((_) => controller.add(read()));
        controller.add(read());
      },
      onCancel: () => sub?.cancel(),
    );
    return controller.stream;
  }

  @override
  Future<Result<List<UserProfile>>> searchPeople(
    String query, {
    required String excludeUid,
  }) async => Result.ok([
    for (final p in profiles)
      if (p.uid != excludeUid && p.matches(query)) p,
  ]);

  @override
  Stream<List<Conversation>> watchConversations(String uid) => _watch(
    () => conversations.values
        .where((c) => c.participants.contains(uid) && c.hasMessages)
        .toList(),
  );

  @override
  Stream<Conversation?> watchConversation(String id) =>
      _watch(() => conversations[id]);

  @override
  Future<Result<String>> openConversation(AppUser me, UserProfile other) async {
    final id = Conversation.idFor(me.uid, other.uid);
    conversations.putIfAbsent(
      id,
      () => Conversation(
        id: id,
        participants: id.split('_'),
        names: {me.uid: me.label, other.uid: other.name},
      ),
    );
    emit();
    return Result.ok(id);
  }

  @override
  Stream<List<ChatMessage>> watchMessages(String id, {required int limit}) =>
      _watch(() => List.of(messages[id] ?? const <ChatMessage>[]));

  @override
  Future<Result<void>> sendMessage(
    String id, {
    required AppUser author,
    required String text,
    List<NewAttachment> attachments = const [],
  }) async {
    final list = messages.putIfAbsent(id, () => []);
    final at = DateTime(2026, 10, 30, 12, list.length);
    list.add(
      ChatMessage(
        id: 'm${list.length + 1}',
        authorId: author.uid,
        authorName: author.label,
        text: text.trim(),
        createdAt: at,
      ),
    );
    final c = conversations[id]!;
    conversations[id] = Conversation(
      id: id,
      participants: c.participants,
      names: c.names,
      lastMessage: messagePreview(text, attachments.length),
      lastMessageAt: at,
      lastSenderId: author.uid,
      readAt: {...c.readAt, author.uid: at},
    );
    emit();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> deleteMessage(String id, ChatMessage message) async {
    messages[id]?.removeWhere((m) => m.id == message.id);
    emit();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> markRead(String id, String uid) async {
    reads.add(id);
    final c = conversations[id]!;
    conversations[id] = Conversation(
      id: id,
      participants: c.participants,
      names: c.names,
      lastMessage: c.lastMessage,
      lastMessageAt: c.lastMessageAt,
      lastSenderId: c.lastSenderId,
      readAt: {...c.readAt, uid: DateTime(2100)},
    );
    emit();
    return const Result.ok(null);
  }

  @override
  Future<Result<Uint8List>> downloadAttachment(ChatAttachment a) async =>
      Result.error(Exception('missing'));
}

class FakeNotificationRepository implements NotificationRepository {
  FakeNotificationRepository({
    this.prefs = const NotificationPreferences(),
    List<AppNotification> feed = const [],
    this.status = PushStatus.notDetermined,
    this.pushSupported = true,
  }) : feed = [...feed];

  NotificationPreferences prefs;
  final List<AppNotification> feed;
  PushStatus status;
  @override
  final bool pushSupported;
  final synced = <String>[];
  final unregistered = <String>[];
  final opened = StreamController<String>.broadcast();
  final _changes = StreamController<void>.broadcast();

  void emit() => _changes.add(null);

  Stream<T> _watch<T>(T Function() read) {
    late StreamController<T> controller;
    StreamSubscription<void>? sub;
    controller = StreamController<T>(
      onListen: () {
        sub = _changes.stream.listen((_) => controller.add(read()));
        controller.add(read());
      },
      onCancel: () => sub?.cancel(),
    );
    return controller.stream;
  }

  Future<Result<void>> _update(NotificationPreferences next) async {
    prefs = next;
    emit();
    return const Result.ok(null);
  }

  @override
  Stream<NotificationPreferences> watchPreferences(String uid) =>
      _watch(() => prefs);

  @override
  Future<Result<void>> setCategory(
    String uid,
    NotificationCategory category, {
    required bool on,
  }) => _update(
    NotificationPreferences(
      categories: {...prefs.categories, category: on},
      teams: prefs.teams,
      mutedRooms: prefs.mutedRooms,
    ),
  );

  @override
  Future<Result<void>> setTeamCategory(
    String uid,
    String teamId,
    NotificationCategory category, {
    required bool on,
  }) => _update(
    NotificationPreferences(
      categories: prefs.categories,
      teams: {
        ...prefs.teams,
        teamId: {...?prefs.teams[teamId], category: on},
      },
      mutedRooms: prefs.mutedRooms,
    ),
  );

  @override
  Future<Result<void>> resetTeam(String uid, String teamId) => _update(
    NotificationPreferences(
      categories: prefs.categories,
      teams: {...prefs.teams}..remove(teamId),
      mutedRooms: prefs.mutedRooms,
    ),
  );

  @override
  Future<Result<void>> setRoomMuted(
    String uid,
    String teamId,
    String roomId, {
    required bool muted,
  }) {
    final key = NotificationPreferences.roomKey(teamId, roomId);
    return _update(
      NotificationPreferences(
        categories: prefs.categories,
        teams: prefs.teams,
        mutedRooms: muted
            ? {...prefs.mutedRooms, key}
            : ({...prefs.mutedRooms}..remove(key)),
      ),
    );
  }

  @override
  Stream<List<AppNotification>> watchFeed(String uid) =>
      _watch(() => List.of(feed));

  @override
  Future<Result<void>> markRead(String uid, Iterable<String> ids) async {
    final set = ids.toSet();
    for (var i = 0; i < feed.length; i++) {
      final n = feed[i];
      if (!set.contains(n.id)) continue;
      feed[i] = AppNotification(
        id: n.id,
        category: n.category,
        title: n.title,
        body: n.body,
        route: n.route,
        teamId: n.teamId,
        createdAt: n.createdAt,
        read: true,
        count: n.count,
      );
    }
    emit();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> delete(String uid, Iterable<String> ids) async {
    final set = ids.toSet();
    feed.removeWhere((n) => set.contains(n.id));
    emit();
    return const Result.ok(null);
  }

  @override
  Future<PushStatus> pushStatus() async => status;

  @override
  Future<Result<PushStatus>> enablePush(String uid) async {
    if (status == PushStatus.notDetermined) status = PushStatus.enabled;
    return Result.ok(status);
  }

  @override
  Future<void> syncDevice(String uid) async => synced.add(uid);

  @override
  Future<void> unregisterDevice(String uid) async => unregistered.add(uid);

  @override
  Stream<String> get openedRoutes => opened.stream;
}

class FakeTeamPostRepository implements TeamPostRepository {
  /// teamId → posts.
  final posts = <String, List<TeamPost>>{};
  final _changes = StreamController<void>.broadcast();

  /// Whether each watch asked for public posts only, in order.
  final watches = <bool>[];

  List<TeamPost> _of(String teamId, bool publicOnly) => [
    for (final p in posts[teamId] ?? const <TeamPost>[])
      if (!publicOnly || p.isPublic) p,
  ]..sort(TeamPost.newestFirst);

  @override
  Stream<List<TeamPost>> watchPosts(
    String teamId, {
    bool publicOnly = false,
  }) async* {
    watches.add(publicOnly);
    yield _of(teamId, publicOnly);
    yield* _changes.stream.map((_) => _of(teamId, publicOnly));
  }

  @override
  Stream<List<TeamPost>> watchTournamentPosts(
    String groupId,
    String tournamentKey,
  ) async* {
    List<TeamPost> of() => [
      for (final p in _of(groupId, true))
        if (p.tournamentKey == tournamentKey) p,
    ];
    yield of();
    yield* _changes.stream.map((_) => of());
  }

  /// Photos uploaded by [savePost], by name.
  final uploaded = <String>[];

  @override
  Future<Result<void>> savePost(
    String teamId,
    PostDraft draft,
    AppUser author,
  ) async {
    final post = draft.post;
    final list = posts.putIfAbsent(teamId, () => []);
    final images = [
      ...post.images,
      for (final a in draft.newImages)
        ChatAttachment(
          path: 'teams/$teamId/posts/${a.name}',
          name: a.name,
          contentType: a.contentType,
          size: a.size,
        ),
    ];
    uploaded.addAll(draft.newImages.map((a) => a.name));
    if (post.isNew) {
      list.add(
        TeamPost(
          id: 'p${list.length + 1}',
          title: post.title,
          body: post.body,
          location: post.location,
          links: post.links,
          images: images,
          isPublic: post.isPublic,
          tournamentKey: post.tournamentKey,
          authorId: author.uid,
          authorName: author.label,
          createdAt: DateTime.now(),
        ),
      );
    } else {
      final i = list.indexWhere((p) => p.id == post.id);
      if (i < 0) return Result.error(Exception('No post'));
      list[i] = post.copyWith(images: images);
    }
    _changes.add(null);
    return const Result.ok(null);
  }

  @override
  Future<Result<Uint8List>> downloadImage(ChatAttachment image) async =>
      Result.ok(Uint8List.fromList(_png));

  @override
  Future<Result<void>> deletePost(String teamId, String postId) async {
    posts[teamId]?.removeWhere((p) => p.id == postId);
    _changes.add(null);
    return const Result.ok(null);
  }
}

/// A 1×1 PNG, for image widgets in tests.
const _png = <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
];
