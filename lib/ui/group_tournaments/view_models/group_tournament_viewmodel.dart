import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/group_tournament/group_tournament_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../domain/models/group_tournament.dart';
import '../../../domain/models/team.dart';
import '../../../domain/tournament_engine/progress.dart';
import '../../../domain/tournament_engine/standings.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';
import '../../../data/repositories/follow/follow_repository.dart';
import '../../../data/repositories/notification/notification_repository.dart';
import '../../../domain/models/follow.dart';
import '../../follow/view_models/follow_viewmodel.dart';

typedef GameScore = ({String gameId, int scoreA, int scoreB});

/// What the user may do with a game.
enum GameAction {
  /// A captain enters the score.
  report,

  /// The other captain's report waits for this captain.
  confirm,

  /// This captain reported; the other has to confirm.
  awaiting,
}

/// A tournament's page: schedule, pools, bracket and teams, with score
/// reporting for captains and full control for organizers.
class GroupTournamentViewModel extends ChangeNotifier {
  GroupTournamentViewModel({
    required this.groupId,
    required this.tournamentId,
    required TeamRepository teamRepository,
    required GroupTournamentRepository tournamentRepository,
    required AuthRepository authRepository,
    FollowRepository? followRepository,
    NotificationRepository? notificationRepository,
  }) : _repo = tournamentRepository,
       _uid = authRepository.currentUser?.uid ?? '',
       _followSlot = FollowSlot(
         followRepository: followRepository,
         notificationRepository: notificationRepository,
         authRepository: authRepository,
       ) {
    report = Command1<void, GameScore>(_report);
    confirm = Command1<void, GroupGame>(_confirm);
    setFinalScore = Command1<void, GameScore>(_setFinalScore);
    seedBracket = Command0<void>(_seedBracket);
    delete = Command0<void>(
      () => _repo.deleteTournament(groupId, tournamentId),
    );
    _subs = [
      teamRepository.watchTeam(groupId).listen((g) {
        _group = g;
        notifyListeners();
      }, onError: (Object _) {}),
      _repo.watchTournament(groupId, tournamentId).listen((t) {
        _tournament = t;
        _loaded = true;
        notifyListeners();
      }, onError: _onError),
      // The public listing, for people following it from outside.
      _repo.watchListings(groupId).listen((l) {
        _listing = l.where((x) => x.tournamentId == tournamentId).firstOrNull;
        notifyListeners();
      }, onError: (Object _) {}),
      _repo.watchGames(groupId, tournamentId).listen((g) {
        _games = g;
        _catchUp();
        notifyListeners();
      }, onError: (Object _) {}),
    ];
  }

  final String groupId;
  final String tournamentId;
  final GroupTournamentRepository _repo;
  final String _uid;
  late final List<StreamSubscription<Object?>> _subs;

  final FollowSlot _followSlot;
  TournamentListing? _listing;

  /// The public summary, shown to people who aren't in the tournament.
  TournamentListing? get listing => _listing;

  /// The tournament's Follow button, once its name is known.
  FollowViewModel? get follow {
    final name = _tournament?.name ?? _listing?.name;
    return _followSlot.of(
      name == null
          ? null
          : FollowTarget.tournament(groupId, tournamentId, name),
    );
  }

  Team? _group;
  GroupTournament? _tournament;
  List<GroupGame> _games = const [];
  bool _loaded = false;
  Object? _error;

  late final Command1<void, GameScore> report;
  late final Command1<void, GroupGame> confirm;
  late final Command1<void, GameScore> setFinalScore;
  late final Command0<void> seedBracket;
  late final Command0<void> delete;

  bool get loaded => _loaded || _error != null;
  Object? get error => _error;
  GroupTournament? get tournament => _tournament;
  List<GroupGame> get games => _games;
  String get uid => _uid;

  void _onError(Object e) {
    _error = e;
    notifyListeners();
  }

  bool get isOrganizer => _group?.canEdit(_uid) ?? false;

  TournamentTeam? get myTeam => _tournament?.teamOf(_uid);

  bool get isScheduled => _games.isNotEmpty;

  String teamName(String? id) => _tournament?.teamName(id) ?? 'TBD';

  /// Games are numbered by schedule order, for "Winner of game 5".
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

  /// The champion's team id, once it's decided.
  String? get championId {
    final t = _tournament;
    return t == null ? null : champion(t, _games);
  }

  /// Pool id → standings, for formats with pools.
  Map<String, List<Standing>> get poolStandings => {
    for (final e in poolTeams(_games).entries)
      e.key: standings(e.value, _games.where((g) => g.poolId == e.key)),
  };

  List<GroupGame> get bracketGames => [
    for (final g in _games)
      if (g.stage.isBracket) g,
  ];

  /// The user's team's games still to play, soonest first.
  List<GroupGame> get myUpcoming {
    final mine = myTeam?.id;
    if (mine == null) return const [];
    return [
      for (final g in gamesToPlay(_games))
        if (g.involves(mine)) g,
    ];
  }

  bool isSkipped(GroupGame g) => skippedGame(g, _games);

  /// Pools are done and the bracket is waiting for its seeds.
  bool get canSeedBracket => isOrganizer && bracketSeeds(_games).isNotEmpty;

  bool get awaitingBracketSeeds => awaitingSeeds(_games);

  bool _isCaptainOf(String? teamId) =>
      teamId != null && _tournament?.team(teamId)?.captainId == _uid;

  /// What a captain can do with [g]; null for nothing.
  GameAction? actionFor(GroupGame g) {
    if (!g.hasTeams || g.isDone) return null;
    final mineA = _isCaptainOf(g.teamA);
    final mineB = _isCaptainOf(g.teamB);
    if (!mineA && !mineB) return null;
    final r = g.report;
    if (g.status != GameStatus.reported || r == null) return GameAction.report;
    final myTeam = mineA ? g.teamA : g.teamB;
    return r.byTeamId == myTeam ? GameAction.awaiting : GameAction.confirm;
  }

  /// The team this user reports for in [g].
  String? _reportingTeam(GroupGame g) => _isCaptainOf(g.teamA)
      ? g.teamA
      : (_isCaptainOf(g.teamB) ? g.teamB : null);

  /// Organizers can set a score unless later games already depend on it.
  bool canSetScore(GroupGame g) =>
      isOrganizer && g.hasTeams && !laterGamesPlayed(g, _games);

  Future<Result<void>> _report(GameScore s) async {
    final why = scoreError(s.scoreA, s.scoreB);
    if (why != null) return Result.error(Exception(why));
    final g = _games.where((x) => x.id == s.gameId).firstOrNull;
    final team = g == null ? null : _reportingTeam(g);
    if (team == null) {
      return Result.error(Exception('Only team captains report scores.'));
    }
    return _repo.reportScore(
      groupId,
      tournamentId,
      s.gameId,
      ScoreReport(scoreA: s.scoreA, scoreB: s.scoreB, byTeamId: team),
    );
  }

  Future<Result<void>> _confirm(GroupGame g) async {
    final r = g.report;
    if (r == null) return Result.error(Exception('Nothing to confirm.'));
    final done = g.copyWith(
      status: GameStatus.done,
      scoreA: () => r.scoreA,
      scoreB: () => r.scoreB,
      report: () => null,
    );
    return _repo.confirmScore(
      groupId,
      tournamentId,
      g,
      fillsAfter(done, _games),
    );
  }

  Future<Result<void>> _setFinalScore(GameScore s) async {
    final why = scoreError(s.scoreA, s.scoreB);
    if (why != null) return Result.error(Exception(why));
    final g = _games.where((x) => x.id == s.gameId).firstOrNull;
    if (g == null) return Result.error(Exception('Game not found.'));
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
    return _repo.setFinalScore(
      groupId,
      tournamentId,
      g.id,
      scoreA: s.scoreA,
      scoreB: s.scoreB,
      fills: fillsAfter(done, _games, overwrite: true),
    );
  }

  Future<Result<void>> _seedBracket() =>
      _repo.applyFills(groupId, tournamentId, bracketSeeds(_games));

  bool _catchingUp = false;

  /// Moves teams on if a finished game's bracket update didn't land (it
  /// goes with the confirm, so this is rare). Anyone playing may do it.
  void _catchUp() {
    final fills = pendingFills(_games);
    if (fills.isEmpty || _catchingUp) return;
    if (!isOrganizer && myTeam == null) return;
    _catchingUp = true;
    _repo
        .applyFills(groupId, tournamentId, fills)
        .whenComplete(() => _catchingUp = false);
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _followSlot.dispose();
    super.dispose();
  }
}
