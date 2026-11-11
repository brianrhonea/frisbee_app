import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/follow/follow_repository.dart';
import '../../../data/repositories/hosted_tournament/hosted_tournament_repository.dart';
import '../../../data/repositories/notification/notification_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../data/repositories/team_post/team_post_repository.dart';
import '../../../domain/models/chat.dart';
import '../../../domain/models/follow.dart';
import '../../../domain/models/group_tournament.dart';
import '../../../domain/models/hosted_tournament.dart';
import '../../../domain/models/team.dart';
import '../../../domain/models/team_post.dart';
import '../../../domain/tournament_engine/generator.dart';
import '../../../domain/tournament_engine/progress.dart';
import '../../../domain/tournament_engine/standings.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';
import '../../follow/view_models/follow_viewmodel.dart';

typedef HostedScore = ({String gameId, int scoreA, int scoreB});
typedef EntryApplication = ({
  String teamId,
  String divisionId,
  List<String> captainIds,
});
typedef EntryDecision = ({TournamentEntry entry, EntryStatus status});

/// What the user may do with a game.
enum HostedGameAction {
  /// A captain enters the score.
  report,

  /// The other captain's report waits for this captain.
  confirm,

  /// This captain reported; the other has to confirm.
  awaiting,
}

/// A hosted tournament's page: overview, teams and bids, seeding,
/// schedules, results and news. The host's managers (Manage events) run
/// it; team admins apply and pick captains; captains report scores;
/// everyone else follows along.
/// A team can't register for a division with fewer than its
/// [TournamentDivision.effectiveMinRoster] players on its roster.
class RosterTooSmallException implements Exception {
  const RosterTooSmallException(this.teamName, this.players, this.minimum);

  final String teamName;
  final int players;
  final int minimum;

  @override
  String toString() =>
      '$teamName needs at least $minimum players on its '
      "roster to register (it has $players). Add players on the team's "
      'Roster tab, then try again.';
}

class HostedTournamentViewModel extends ChangeNotifier {
  HostedTournamentViewModel({
    required this.tournamentId,
    required HostedTournamentRepository tournamentRepository,
    required TeamRepository teamRepository,
    required AuthRepository authRepository,
    TeamPostRepository? postRepository,
    FollowRepository? followRepository,
    NotificationRepository? notificationRepository,
    DateTime Function()? now,
  }) : _repo = tournamentRepository,
       _teams = teamRepository,
       _posts = postRepository,
       _now = now ?? DateTime.now,
       _auth = authRepository,
       _uid = authRepository.currentUser?.uid ?? '',
       _followSlot = FollowSlot(
         followRepository: followRepository,
         notificationRepository: notificationRepository,
         authRepository: authRepository,
       ) {
    setStatus = Command1<void, HostedStatus>(
      (s) => _repo.setStatus(tournamentId, s),
    );
    apply = Command1<void, EntryApplication>(_apply);
    invite = Command1<void, ({TeamListing team, String divisionId})>(_invite);
    decide = Command1<void, EntryDecision>(_decide);
    updateCaptains =
        Command1<void, ({TournamentEntry entry, List<String> captainIds})>(
          _updateCaptains,
        );
    setPaid = Command1<void, ({String teamId, bool paid})>(_setPaid);
    saveSeeds = Command1<void, List<String>>(_saveSeeds);
    publish = Command0<void>(_publish);
    report = Command1<void, HostedScore>(_report);
    confirm = Command1<void, GroupGame>(_confirm);
    setFinalScore = Command1<void, HostedScore>(_setFinalScore);
    seedBracket = Command0<void>(_seedBracket);
    delete = Command0<void>(() => _repo.deleteTournament(tournamentId));
    saveDivision = Command1<void, TournamentDivision>(_saveDivision);
    deleteDivision = Command1<void, String>(_deleteDivision);
    createTeams = Command1<void, String>(_createTeams);
    postNews = Command1<void, ({String title, String body})>(_postNews);
    _subs = [
      _repo.watchTournament(tournamentId).listen((t) {
        final hostChanged = t?.hostId != _tournament?.hostId;
        _tournament = t;
        _loaded = true;
        if (hostChanged && t != null) _watchHost(t);
        _pickDivision();
        notifyListeners();
      }, onError: _onError),
      _repo.watchDivisions(tournamentId).listen((d) {
        _divisions = {for (final x in d) x.id: x};
        _watchPublished();
        _pickDivision();
        _syncCaptains();
        notifyListeners();
      }, onError: (Object _) {}),
      _repo.watchEntries(tournamentId).listen((e) {
        _entries = e;
        _pickDivision();
        _watchMyPayments();
        _dropWithdrawn();
        _syncCaptains();
        notifyListeners();
      }, onError: (Object _) {}),
      if (_uid.isNotEmpty)
        _teams.watchMyTeams(_uid).listen((teams) {
          _myTeams = teams;
          _pickDivision();
          _watchMyPayments();
          notifyListeners();
        }, onError: (Object _) {}),
    ];
  }

  final String tournamentId;
  final HostedTournamentRepository _repo;
  final TeamRepository _teams;
  final TeamPostRepository? _posts;
  final DateTime Function() _now;
  final AuthRepository _auth;
  final String _uid;
  final FollowSlot _followSlot;
  late final List<StreamSubscription<Object?>> _subs;
  StreamSubscription<Team?>? _hostSub;
  StreamSubscription<List<EntryPayment>>? _paymentsSub;
  StreamSubscription<List<TeamPost>>? _newsSub;
  StreamSubscription<List<GroupGame>>? _gamesSub;
  final _myPaymentSubs = <String, StreamSubscription<EntryPayment?>>{};
  final _publishedSubs = <String, StreamSubscription<List<GroupGame>>>{};
  final _published = <String, bool>{};
  bool _pickedByUser = false;

  HostedTournament? _tournament;
  Team? _host;
  Map<String, TournamentDivision> _divisions = const {};
  List<TournamentEntry> _entries = const [];
  Map<String, EntryPayment> _payments = const {};
  List<Team> _myTeams = const [];
  List<TeamPost> _news = const [];
  String? _divisionId;
  List<GroupGame> _games = const [];
  bool _loaded = false;
  Object? _error;

  late final Command1<void, HostedStatus> setStatus;
  late final Command1<void, EntryApplication> apply;
  late final Command1<void, ({TeamListing team, String divisionId})> invite;
  late final Command1<void, EntryDecision> decide;
  late final Command1<void, ({TournamentEntry entry, List<String> captainIds})>
  updateCaptains;
  late final Command1<void, ({String teamId, bool paid})> setPaid;
  late final Command1<void, List<String>> saveSeeds;
  late final Command0<void> publish;
  late final Command1<void, HostedScore> report;
  late final Command1<void, GroupGame> confirm;
  late final Command1<void, HostedScore> setFinalScore;
  late final Command0<void> seedBracket;
  late final Command0<void> delete;
  late final Command1<void, TournamentDivision> saveDivision;
  late final Command1<void, String> deleteDivision;
  late final Command1<void, String> createTeams;
  late final Command1<void, ({String title, String body})> postNews;

  List<Command<void>> get commands => [
    setStatus,
    apply,
    invite,
    decide,
    updateCaptains,
    setPaid,
    saveSeeds,
    publish,
    report,
    confirm,
    setFinalScore,
    seedBracket,
    delete,
    saveDivision,
    deleteDivision,
    createTeams,
    postNews,
  ];

  bool get loaded => _loaded || _error != null;
  Object? get error => _error;
  HostedTournament? get tournament => _tournament;
  String get uid => _uid;
  List<TeamPost> get news => _news;

  void _onError(Object e) {
    _error = e;
    notifyListeners();
  }

  /// The tournament's Follow button.
  FollowViewModel? get follow {
    final t = _tournament;
    return _followSlot.of(
      t == null ? null : FollowTarget.tournament(t.hostId, t.id, t.name),
    );
  }

  void _watchHost(HostedTournament t) {
    _hostSub?.cancel();
    _hostSub = _teams.watchTeam(t.hostId).listen((h) {
      final wasManager = isManager;
      _host = h;
      if (isManager != wasManager) _watchPayments();
      notifyListeners();
    }, onError: (Object _) {});
    _newsSub?.cancel();
    _newsSub = _posts?.watchTournamentPosts(t.hostId, t.followKey).listen((p) {
      _news = p;
      notifyListeners();
    }, onError: (Object _) {});
  }

  /// News goes out as a public post on the host's page, tagged with the
  /// tournament, so followers of either see it.
  bool get canPostNews =>
      _posts != null && (_host?.has(_uid, TeamPermission.manageTeam) ?? false);

  Future<Result<void>> _postNews(({String title, String body}) n) async {
    final t = _tournament;
    final me = _auth.currentUser;
    final posts = _posts;
    if (t == null || me == null || posts == null) {
      return Result.error(Exception("Can't post here."));
    }
    if (n.body.trim().isEmpty && n.title.trim().isEmpty) {
      return Result.error(Exception('Write something first.'));
    }
    return posts.savePost(
      t.hostId,
      PostDraft(
        post: TeamPost(
          id: '',
          title: n.title.trim(),
          body: n.body.trim(),
          isPublic: true,
          tournamentKey: t.followKey,
        ),
      ),
      me,
    );
  }

  /// Loads a news post's photo.
  Future<Result<Uint8List>> loadImage(ChatAttachment image) =>
      _posts?.downloadImage(image) ??
      Future.value(Result.error(Exception('Photos are unavailable.')));

  /// Teams in the directory matching [query], to invite.
  Future<Result<List<TeamListing>>> searchTeams(String query) async {
    final r = await _teams.searchTeams(query);
    return switch (r) {
      Ok(:final value) => Result.ok([
        for (final t in value)
          if (t.kind == TeamKind.team) t,
      ]),
      Error(:final error) => Result.error(error),
    };
  }

  // ---- Roles --------------------------------------------------------------

  /// The host's members with Manage events run the tournament.
  bool get isManager => _host?.has(_uid, TeamPermission.manageEvents) ?? false;

  /// Teams this user can enter: their teams (not groups) they manage.
  List<Team> get myAdminTeams => [
    for (final t in _myTeams)
      if (t.kind == TeamKind.team && t.has(_uid, TeamPermission.manageTeam)) t,
  ];

  /// Why [team] can't play in a league's [division], or null. A league
  /// division is for teams of its gender division and level (a College
  /// Women division takes college women's teams); a division at the League
  /// level takes teams of any level.
  static String? leagueFitProblem(Team team, TournamentDivision? division) {
    if (division == null) return null;
    if (team.division != division.division) {
      return '${division.label} is for ${division.division.label} teams; '
          '${team.name} plays ${team.division.label}.';
    }
    if (division.level != CompetitionLevel.league &&
        team.level != division.level) {
      return '${division.label} is for ${division.level.label} teams; '
          '${team.name} is ${team.level.label}.';
    }
    return null;
  }

  Team? myTeam(String teamId) =>
      _myTeams.where((t) => t.id == teamId).firstOrNull;

  /// Entries of teams this user manages.
  List<TournamentEntry> get myEntries => [
    for (final e in _entries)
      if (myAdminTeams.any((t) => t.id == e.teamId)) e,
  ];

  /// Admin teams that haven't entered yet.
  List<Team> get teamsToEnter => [
    for (final t in myAdminTeams)
      if (!_entries.any(
        (e) => e.teamId == t.id && e.status != EntryStatus.withdrawn,
      ))
        t,
  ];

  /// Whether this user can apply now: registration is open and the
  /// tournament is public (invited teams answer their invite instead).
  bool get canApply {
    final t = _tournament;
    return t != null &&
        !t.takesPlayers &&
        t.status.acceptsEntries &&
        t.visibility == TournamentVisibility.public &&
        teamsToEnter.isNotEmpty &&
        divisions.isNotEmpty;
  }

  // ---- Divisions and entries ---------------------------------------------

  /// In the tournament's order.
  List<TournamentDivision> get divisions => [
    for (final s in _tournament?.divisions ?? const <DivisionSummary>[])
      ?_divisions[s.id],
  ];

  TournamentDivision? divisionById(String? id) => _divisions[id];

  TournamentDivision? get division => _divisions[_divisionId];

  void selectDivision(String id) {
    if (id == _divisionId || !_divisions.containsKey(id)) return;
    _pickedByUser = true;
    _divisionId = id;
    _watchGames();
    notifyListeners();
  }

  /// Shows the user's own division until they pick another, else the
  /// first.
  void _pickDivision() {
    final mine = _pickedByUser ? null : myDivisionId;
    if (mine != null && mine != _divisionId) {
      _divisionId = mine;
      _watchGames();
      return;
    }
    if (_divisionId != null && _divisions.containsKey(_divisionId)) return;
    final first = divisions.firstOrNull;
    if (first == null) return;
    _divisionId = first.id;
    _watchGames();
  }

  /// Whether each division's schedule is out, for the host's checklist
  /// (the selected division's games are watched in full anyway).
  void _watchPublished() {
    for (final id in [..._publishedSubs.keys]) {
      if (!_divisions.containsKey(id)) {
        _publishedSubs.remove(id)?.cancel();
        _published.remove(id);
      }
    }
    for (final id in _divisions.keys) {
      _publishedSubs[id] ??= _repo.watchGames(tournamentId, id).listen((g) {
        if (_published[id] == g.isNotEmpty) return;
        _published[id] = g.isNotEmpty;
        notifyListeners();
      }, onError: (Object _) {});
    }
  }

  /// Whether [divisionId]'s schedule is published.
  bool publishedIn(String divisionId) => divisionId == _divisionId
      ? _games.isNotEmpty
      : _published[divisionId] ?? false;

  /// The teams the user plays on here: drafted onto (player entry), or an
  /// accepted team they're a member of (team entry).
  Set<String> get myTeamIds => {
    for (final d in _divisions.values)
      for (final t in d.teams)
        if (t.playerIds.contains(_uid)) t.id,
    for (final e in _entries)
      if (e.status == EntryStatus.accepted &&
          _myTeams.any((t) => t.id == e.teamId))
        e.teamId,
  };

  /// The division the user plays in, if any.
  String? get myDivisionId {
    final mine = myTeamIds;
    if (mine.isEmpty) return null;
    for (final d in divisions) {
      if (d.seeds.any(mine.contains) ||
          d.teams.any((t) => mine.contains(t.id))) {
        return d.id;
      }
    }
    return null;
  }

  /// The user's next game to play in the selected division.
  GroupGame? get myNextGame {
    final mine = myTeamIds;
    return gamesToPlay(_games)
        .where((g) => mine.contains(g.teamA) || mine.contains(g.teamB))
        .firstOrNull;
  }

  /// The user's team in [g]: the other team is the opponent.
  String? myTeamIn(GroupGame g) {
    final mine = myTeamIds;
    return mine.contains(g.teamA)
        ? g.teamA
        : mine.contains(g.teamB)
        ? g.teamB
        : null;
  }

  void _watchGames() {
    _gamesSub?.cancel();
    _games = const [];
    final id = _divisionId;
    if (id == null) return;
    _gamesSub = _repo.watchGames(tournamentId, id).listen((g) {
      _games = g;
      _catchUp();
      _goLive();
      _recordPlacements();
      notifyListeners();
    }, onError: (Object _) {});
  }

  List<TournamentEntry> entriesIn(String divisionId, {EntryStatus? status}) => [
    for (final e in _entries)
      if (e.divisionId == divisionId && (status == null || e.status == status))
        e,
  ];

  List<TournamentEntry> entriesWith(EntryStatus status) => [
    for (final e in _entries)
      if (e.status == status) e,
  ];

  TournamentEntry? entryOf(String teamId) =>
      _entries.where((e) => e.teamId == teamId).firstOrNull;

  String teamName(String? id) {
    if (id == null) return 'TBD';
    final entry = entryOf(id);
    if (entry != null) return entry.teamName;
    // Teams drafted from player signups have no entry, only the division.
    for (final d in _divisions.values) {
      final drafted = d.teams.where((t) => t.id == id).firstOrNull;
      if (drafted != null) return drafted.name;
    }
    return 'Team';
  }

  /// Accepted teams of [divisionId] in seed order.
  List<String> seedsOf(String divisionId) =>
      _divisions[divisionId]?.seeds ?? const [];

  // ---- Bid fees -----------------------------------------------------------

  /// Managers see every team's payment; team admins see their own.
  bool get canSeePayments => isManager || myEntries.isNotEmpty;

  EntryPayment? paymentOf(String teamId) => _payments[teamId];

  bool isPaid(String teamId) => _payments[teamId]?.paid ?? false;

  /// Unpaid once the bid fee's due date has passed.
  bool isOverdue(String teamId) {
    final due = _tournament?.bidFee?.dueAt;
    return due != null && !isPaid(teamId) && _now().isAfter(due);
  }

  /// Accepted teams (any division) that haven't paid.
  int get unpaidCount => [
    for (final e in entriesWith(EntryStatus.accepted))
      if (!isPaid(e.teamId)) e,
  ].length;

  void _watchPayments() {
    _paymentsSub?.cancel();
    _paymentsSub = null;
    if (!isManager) {
      _watchMyPayments();
      return;
    }
    for (final s in _myPaymentSubs.values) {
      s.cancel();
    }
    _myPaymentSubs.clear();
    _paymentsSub = _repo.watchPayments(tournamentId).listen((p) {
      _payments = {for (final x in p) x.teamId: x};
      notifyListeners();
    }, onError: (Object _) {});
  }

  /// Team admins read only their own teams' payment docs.
  void _watchMyPayments() {
    if (isManager) return;
    final wanted = {for (final e in myEntries) e.teamId};
    for (final id in [..._myPaymentSubs.keys]) {
      if (!wanted.contains(id)) _myPaymentSubs.remove(id)?.cancel();
    }
    for (final id in wanted) {
      _myPaymentSubs[id] ??= _repo.watchPayment(tournamentId, id).listen((p) {
        _payments = {..._payments, id: ?p};
        notifyListeners();
      }, onError: (Object _) {});
    }
  }

  // ---- Registration actions ----------------------------------------------

  Future<Result<void>> _apply(EntryApplication a) async {
    final t = _tournament;
    final team = myTeam(a.teamId);
    if (t == null || team == null) {
      return Result.error(Exception('Pick one of your teams.'));
    }
    if (t.takesPlayers) {
      return Result.error(
        Exception(
          'Players sign up one by one here; teams are drawn from them.',
        ),
      );
    }
    if (a.captainIds.isEmpty) {
      return Result.error(Exception('Pick at least one captain.'));
    }
    if (a.captainIds.length > TournamentEntry.maxCaptains) {
      return Result.error(
        Exception('Pick up to ${TournamentEntry.maxCaptains} captains.'),
      );
    }
    if (t.isLeague) {
      final problem = leagueFitProblem(team, _divisions[a.divisionId]);
      if (problem != null) return Result.error(Exception(problem));
    }
    // Applying and accepting an invite both register the team.
    final int players;
    try {
      players = (await _teams.watchRoster(team.id).first).length;
    } on Exception catch (e) {
      return Result.error(e);
    }
    final minimum =
        _divisions[a.divisionId]?.effectiveMinRoster ??
        TournamentDivision.defaultMinRoster;
    if (players < minimum) {
      return Result.error(RosterTooSmallException(team.name, players, minimum));
    }
    return _repo.saveEntry(
      tournamentId,
      TournamentEntry(
        teamId: team.id,
        teamName: team.name,
        divisionId: a.divisionId,
        captainIds: a.captainIds,
      ),
    );
  }

  Future<Result<void>> _invite(({TeamListing team, String divisionId}) i) {
    final existing = entryOf(i.team.id);
    if (existing != null && existing.status != EntryStatus.withdrawn) {
      return Future.value(
        Result.error(
          Exception(
            '${i.team.name} is already ${existing.status.label.toLowerCase()}.',
          ),
        ),
      );
    }
    return _repo.saveEntry(
      tournamentId,
      TournamentEntry(
        teamId: i.team.id,
        teamName: i.team.name,
        divisionId: i.divisionId,
        status: EntryStatus.invited,
      ),
    );
  }

  Future<Result<void>> _decide(EntryDecision d) async {
    final division = _divisions[d.entry.divisionId];
    if (d.status == EntryStatus.accepted) {
      if (division == null) {
        return Result.error(Exception('That division no longer exists.'));
      }
      if (division.isFull && !division.seeds.contains(d.entry.teamId)) {
        return Result.error(
          Exception(
            '${division.label} is full (${division.maxTeams} teams). '
            'Waitlist the team or raise the cap.',
          ),
        );
      }
      return _repo.acceptEntry(tournamentId, division, d.entry);
    }
    // Withdrawn, declined or back to the waitlist: out of the seeds. Only
    // managers write the division; a manager's view tidies up after a
    // team withdraws itself (see _syncCaptains).
    return _repo.setEntryStatus(
      tournamentId,
      d.entry,
      d.status,
      division: isManager ? division : null,
    );
  }

  Future<Result<void>> _updateCaptains(
    ({TournamentEntry entry, List<String> captainIds}) u,
  ) async {
    if (u.captainIds.isEmpty) {
      return Result.error(Exception('Pick at least one captain.'));
    }
    return _repo.saveEntry(
      tournamentId,
      u.entry.copyWith(captainIds: u.captainIds),
    );
  }

  bool _syncing = false;

  /// A team that withdraws itself can't write the division, so a
  /// manager's view drops it from the seeds. Runs when entries change (not
  /// divisions), so a just-accepted team is never mistaken for one that
  /// left.
  void _dropWithdrawn() {
    final t = _tournament;
    if (!isManager || _syncing || t == null) return;
    for (final d in _divisions.values) {
      final gone = {
        for (final id in d.seeds)
          if (entryOf(id)?.status == EntryStatus.withdrawn) id,
      };
      // Teams stay in a published schedule; the host sorts that out.
      if (gone.isEmpty || (d.id == _divisionId && isPublished)) continue;
      _syncing = true;
      _repo
          .saveDivision(
            t,
            d.copyWith(
              seeds: [
                for (final id in d.seeds)
                  if (!gone.contains(id)) id,
              ],
              captains: {
                for (final c in d.captains.entries)
                  if (!gone.contains(c.key)) c.key: c.value,
              },
            ),
          )
          .whenComplete(() => _syncing = false);
      return;
    }
  }

  /// Team admins change captains on their entry, but only managers can
  /// write the division; copy changes over when a manager is looking.
  void _syncCaptains() {
    if (!isManager || _syncing) return;
    final t = _tournament;
    if (t == null) return;
    for (final e in entriesWith(EntryStatus.accepted)) {
      final d = _divisions[e.divisionId];
      if (d == null || !d.seeds.contains(e.teamId)) continue;
      if (listEquals(d.captains[e.teamId], e.captainIds)) continue;
      _syncing = true;
      _repo
          .saveDivision(
            t,
            d.copyWith(captains: {...d.captains, e.teamId: e.captainIds}),
          )
          .whenComplete(() => _syncing = false);
      return;
    }
  }

  Future<Result<void>> _setPaid(({String teamId, bool paid}) p) {
    final old = _payments[p.teamId];
    return _repo.savePayment(
      tournamentId,
      EntryPayment(
        teamId: p.teamId,
        paid: p.paid,
        paidAt: p.paid ? (old?.paidAt ?? _now()) : null,
        note: old?.note ?? '',
      ),
    );
  }

  /// A new division's defaults. A tournament: full-field 7v7, game to 15
  /// like club ultimate, starting 9am each day. A league: a weekly evening
  /// round robin, starting at 6:30pm on its first night, two fields.
  TournamentDivision newDivision() {
    final t = _tournament;
    final start = t?.startsOn ?? _now();
    if (t != null && t.isLeague) {
      return TournamentDivision(
        id: '',
        division: Division.mixed,
        level: CompetitionLevel.league,
        maxTeams: 8,
        settings: TournamentSettings(
          startsAt: DateTime(start.year, start.month, start.day, 18, 30),
          format: t.season?.hasPlayoffs == true
              ? TournamentFormat.singleElim
              : TournamentFormat.roundRobin,
          playersOnField: 7,
          gameMinutes: 60,
          breakMinutes: 10,
          scoreCap: 15,
          timeoutsPerHalf: 2,
          fields: 2,
        ),
      );
    }
    final first = DateTime(start.year, start.month, start.day, 9);
    final end = t?.endsOn;
    return TournamentDivision(
      id: '',
      division: Division.mixed,
      level: CompetitionLevel.club,
      maxTeams: 16,
      settings: TournamentSettings(
        playersOnField: 7,
        startsAt: first,
        format: TournamentFormat.poolsPlacement,
        poolCount: 4,
        gameMinutes: 90,
        breakMinutes: 15,
        scoreCap: 15,
        timeoutsPerHalf: 2,
        fields: 4,
        laterDays: daysAfter(first, end),
      ),
    );
  }

  /// Each day after [first] up to [last], starting at [first]'s time.
  static List<DateTime> daysAfter(DateTime first, DateTime? last) {
    if (last == null) return const [];
    final days = <DateTime>[];
    for (
      var d = DateTime(
        first.year,
        first.month,
        first.day + 1,
        first.hour,
        first.minute,
      );
      !DateTime(d.year, d.month, d.day).isAfter(last) && days.length < 6;
      d = DateTime(d.year, d.month, d.day + 1, d.hour, d.minute)
    ) {
      days.add(d);
    }
    return days;
  }

  Future<Result<void>> _saveDivision(TournamentDivision d) async {
    final t = _tournament;
    if (t == null) return Result.error(Exception('Tournament not loaded.'));
    final taken = t.divisions.any(
      (x) => x.id != d.id && x.division == d.division && x.level == d.level,
    );
    if (taken) {
      return Result.error(Exception('There is already a ${d.label} division.'));
    }
    if (d.isNew && t.divisions.length >= HostedTournament.maxDivisions) {
      return Result.error(
        Exception('Up to ${HostedTournament.maxDivisions} divisions.'),
      );
    }
    if (d.seeds.length > d.maxTeams) {
      return Result.error(
        Exception(
          '${d.seeds.length} teams are already in. Raise the cap or '
          'remove teams first.',
        ),
      );
    }
    // A league's results come from its table and playoffs, so the format
    // follows the season: no playoffs is a round robin, otherwise a bracket
    // after it. The host doesn't pick one.
    final season = t.season;
    final saved = t.isLeague && season != null
        ? d.copyWith(
            settings: d.settings.copyWith(
              format: season.hasPlayoffs
                  ? TournamentFormat.singleElim
                  : TournamentFormat.roundRobin,
            ),
          )
        : d;
    final r = await _repo.saveDivision(t, saved);
    if (r case Ok(:final value) when d.isNew) {
      _divisionId = value;
      _watchGames();
    }
    return switch (r) {
      Ok() => const Result.ok(null),
      Error(:final error) => Result.error(error),
    };
  }

  /// A league that takes players turns the host's drafted teams into real
  /// teams (with chat and a roster) before the schedule is published.
  bool get needsTeamsCreated {
    final t = _tournament;
    final d = division;
    return t != null &&
        t.isLeague &&
        t.takesPlayers &&
        d != null &&
        !d.teamsCreated;
  }

  Future<Result<void>> _createTeams(String divisionId) async {
    final t = _tournament;
    final d = _divisions[divisionId];
    if (t == null || d == null) {
      return Result.error(Exception('Pick a division.'));
    }
    if (!isManager) {
      return Result.error(Exception('Only the host can do that.'));
    }
    if (!t.isLeague || !t.takesPlayers) {
      return Result.error(
        Exception('Only leagues where players sign up make teams.'),
      );
    }
    if (d.teams.length < 2) {
      return Result.error(Exception('Draft at least two teams first.'));
    }
    if (_divisionId == divisionId && _games.isNotEmpty) {
      return Result.error(
        Exception('The schedule is published. Create the teams before it.'),
      );
    }
    return _repo.createLeagueTeams(tournamentId, divisionId);
  }

  Future<Result<void>> _deleteDivision(String id) async {
    final t = _tournament;
    if (t == null) return Result.error(Exception('Tournament not loaded.'));
    if (entriesIn(id).any((e) => e.status == EntryStatus.accepted)) {
      return Result.error(
        Exception('Move or remove its accepted teams first.'),
      );
    }
    if (_divisionId == id) {
      _divisionId = null;
      _gamesSub?.cancel();
      _games = const [];
    }
    return _repo.deleteDivision(t, id);
  }

  // ---- Seeding and schedule ----------------------------------------------

  /// Seeds lock once the division's schedule is published; republishing
  /// regenerates every game.
  bool get isPublished => _games.isNotEmpty;

  Future<Result<void>> _saveSeeds(List<String> seeds) async {
    final t = _tournament;
    final d = division;
    if (t == null || d == null) {
      return Result.error(Exception('Pick a division.'));
    }
    return switch (await _repo.saveDivision(t, d.copyWith(seeds: seeds))) {
      Ok() => const Result.ok(null),
      Error(:final error) => Result.error(error),
    };
  }

  /// The schedule [division] would get now, or why it can't have one.
  ({SchedulePlan? plan, String? problem}) preview() {
    final t = _tournament;
    final d = division;
    if (t == null || d == null) {
      return (plan: null, problem: 'Add a division first.');
    }
    if (needsTeamsCreated) {
      return (
        plan: null,
        problem:
            "Create the league's teams first: on the Players tab, draft "
            'teams, then Create teams.',
      );
    }
    try {
      // A league gets its weekly season; anything else the usual schedule.
      return (plan: planFor(t, d, d.seeds), problem: null);
    } on ScheduleException catch (e) {
      return (plan: null, problem: e.message);
    }
  }

  /// The format [d]'s games follow. A league's comes from its season (no
  /// playoffs is a round robin, otherwise a bracket after it), however the
  /// division was saved before the season changed.
  TournamentFormat formatOf(TournamentDivision d) {
    final season = _tournament?.season;
    if (_tournament?.isLeague == true && season != null) {
      return season.hasPlayoffs
          ? TournamentFormat.singleElim
          : TournamentFormat.roundRobin;
    }
    return d.settings.format;
  }

  Future<Result<void>> _publish() async {
    final t = _tournament;
    final d = division;
    final (:plan, :problem) = preview();
    if (t == null || d == null || plan == null) {
      return Result.error(Exception(problem ?? 'Nothing to publish.'));
    }
    final r = await _repo.publishSchedule(
      tournamentId,
      d.copyWith(settings: d.settings.copyWith(format: formatOf(d))),
      plan.games,
    );
    if (r is Error) return r;
    if (t.status.index < HostedStatus.scheduled.index) {
      return _repo.setStatus(tournamentId, HostedStatus.scheduled);
    }
    return r;
  }

  // ---- Games --------------------------------------------------------------

  List<GroupGame> get games => _games;

  int gameNumber(GroupGame g) => g.order + 1;

  /// "Winner of game 5", "Pool A #1" or the team's name.
  String slotLabel(GroupGame g, {required bool a}) {
    final team = a ? g.teamA : g.teamB;
    if (team != null) return teamName(team);
    final source = a ? g.sourceA : g.sourceB;
    String number(String id) =>
        switch (_games.where((x) => x.id == id).firstOrNull) {
          final x? => '${gameNumber(x)}',
          null => '?',
        };
    return switch (source) {
      WinnerOf(:final gameId) => 'Winner of game ${number(gameId)}',
      LoserOf(:final gameId) => 'Loser of game ${number(gameId)}',
      PoolRank(:final poolId, :final rank) => 'Pool $poolId #$rank',
      null => 'TBD',
    };
  }

  Map<String, List<Standing>> get poolStandings => {
    for (final e in poolTeams(_games).entries)
      e.key: standings(e.value, _games.where((g) => g.poolId == e.key)),
  };

  List<GroupGame> get bracketGames => [
    for (final g in _games)
      if (g.stage.isBracket) g,
  ];

  bool isSkipped(GroupGame g) => skippedGame(g, _games);

  bool get canSeedBracket => isManager && bracketSeeds(_games).isNotEmpty;

  bool get awaitingBracketSeeds => awaitingSeeds(_games);

  /// Final places in the selected division, best first; empty until
  /// every game is played.
  List<String> get placements {
    final d = division;
    if (d == null) return const [];
    if (d.placements.isNotEmpty) return d.placements;
    return placementsOf(d.settings.format, d.seeds, _games);
  }

  String? get championId => placements.firstOrNull;

  /// Teams in the selected division whose captain this user is.
  Set<String> get _captainOf {
    final d = division;
    if (d == null) return const {};
    return {
      for (final e in d.captains.entries)
        if (e.value.contains(_uid)) e.key,
    };
  }

  /// The user's games still to play in the selected division.
  List<GroupGame> get myUpcoming => [
    for (final g in gamesToPlay(_games))
      if (_captainOf.contains(g.teamA) || _captainOf.contains(g.teamB)) g,
  ];

  HostedGameAction? actionFor(GroupGame g) {
    if (!g.hasTeams || g.isDone) return null;
    final mine = _captainOf;
    final mineA = mine.contains(g.teamA);
    final mineB = mine.contains(g.teamB);
    if (!mineA && !mineB) return null;
    final r = g.report;
    if (g.status != GameStatus.reported || r == null) {
      return HostedGameAction.report;
    }
    final myTeam = mineA ? g.teamA : g.teamB;
    return r.byTeamId == myTeam
        ? HostedGameAction.awaiting
        : HostedGameAction.confirm;
  }

  bool canSetScore(GroupGame g) =>
      isManager && g.hasTeams && !laterGamesPlayed(g, _games);

  Future<Result<void>> _report(HostedScore s) async {
    final why = scoreError(s.scoreA, s.scoreB);
    if (why != null) return Result.error(Exception(why));
    final g = _games.where((x) => x.id == s.gameId).firstOrNull;
    final mine = _captainOf;
    final team = g == null
        ? null
        : (mine.contains(g.teamA)
              ? g.teamA
              : (mine.contains(g.teamB) ? g.teamB : null));
    final d = division;
    if (team == null || d == null) {
      return Result.error(Exception('Only team captains report scores.'));
    }
    return _repo.reportScore(
      tournamentId,
      d.id,
      s.gameId,
      ScoreReport(scoreA: s.scoreA, scoreB: s.scoreB, byTeamId: team),
    );
  }

  Future<Result<void>> _confirm(GroupGame g) async {
    final r = g.report;
    final d = division;
    if (r == null || d == null) {
      return Result.error(Exception('Nothing to confirm.'));
    }
    final done = g.copyWith(
      status: GameStatus.done,
      scoreA: () => r.scoreA,
      scoreB: () => r.scoreB,
      report: () => null,
    );
    final result = await _repo.confirmScore(
      tournamentId,
      d.id,
      g,
      fillsAfter(done, _games),
    );
    return result;
  }

  Future<Result<void>> _setFinalScore(HostedScore s) async {
    final why = scoreError(s.scoreA, s.scoreB);
    if (why != null) return Result.error(Exception(why));
    final g = _games.where((x) => x.id == s.gameId).firstOrNull;
    final d = division;
    if (g == null || d == null) {
      return Result.error(Exception('Game not found.'));
    }
    if (laterGamesPlayed(g, _games)) {
      return Result.error(
        Exception('Later games already depend on this result.'),
      );
    }
    final done = g.copyWith(
      status: GameStatus.done,
      scoreA: () => s.scoreA,
      scoreB: () => s.scoreB,
      report: () => null,
    );
    final result = await _repo.setFinalScore(
      tournamentId,
      d.id,
      g.id,
      scoreA: s.scoreA,
      scoreB: s.scoreB,
      fills: fillsAfter(done, _games, overwrite: true),
    );
    return result;
  }

  bool _goingLive = false;

  /// The first final score moves a scheduled tournament to live; only
  /// managers can, so their view does it whoever entered the score.
  void _goLive() {
    final t = _tournament;
    if (!isManager || _goingLive || t == null) return;
    if (t.status != HostedStatus.scheduled || !_games.any((g) => g.isDone)) {
      return;
    }
    _goingLive = true;
    _repo
        .setStatus(tournamentId, HostedStatus.live)
        .whenComplete(() => _goingLive = false);
  }

  Future<Result<void>> _seedBracket() async {
    final d = division;
    if (d == null) return const Result.ok(null);
    return _repo.applyFills(tournamentId, d.id, bracketSeeds(_games));
  }

  bool _catchingUp = false;

  /// Moves teams on if a finished game's bracket update didn't land.
  void _catchUp() {
    final d = division;
    final fills = pendingFills(_games);
    if (d == null || fills.isEmpty || _catchingUp) return;
    if (!isManager && _captainOf.isEmpty) return;
    _catchingUp = true;
    _repo
        .applyFills(tournamentId, d.id, fills)
        .whenComplete(() => _catchingUp = false);
  }

  bool _recording = false;

  /// Once a division's games are all played, a manager's view saves its
  /// final places; when every division has them the tournament is final.
  void _recordPlacements() {
    final t = _tournament;
    final d = division;
    if (!isManager || _recording || t == null || d == null) return;
    if (d.placements.isNotEmpty) return;
    final places = placementsOf(formatOf(d), d.seeds, _games);
    if (places.isEmpty) return;
    _recording = true;
    _repo
        .saveDivision(t, d.copyWith(placements: places))
        .then((r) {
          final others = divisions.where((x) => x.id != d.id);
          if (r is Ok && others.every((x) => x.placements.isNotEmpty)) {
            _repo.setStatus(tournamentId, HostedStatus.finished);
          }
        })
        .whenComplete(() => _recording = false);
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _hostSub?.cancel();
    _paymentsSub?.cancel();
    _newsSub?.cancel();
    _gamesSub?.cancel();
    for (final s in _myPaymentSubs.values) {
      s.cancel();
    }
    for (final s in _publishedSubs.values) {
      s.cancel();
    }
    _followSlot.dispose();
    super.dispose();
  }
}
