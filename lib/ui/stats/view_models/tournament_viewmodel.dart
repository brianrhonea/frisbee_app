import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/stats/stats_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../domain/models/roster_player.dart';
import '../../../domain/models/stats.dart';
import '../../../domain/models/team.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

typedef NewTournamentGame = ({
  String opponent,
  int gameTo,
  int timeoutsPerHalf,
});

/// A tournament folder: its games, attending roster and saved lines.
class TournamentViewModel extends ChangeNotifier {
  TournamentViewModel({
    required this.teamId,
    required this.tournamentId,
    required StatsRepository statsRepository,
    required TeamRepository teamRepository,
    required AuthRepository authRepository,
  }) : _stats = statsRepository,
       _auth = authRepository {
    addGame = Command1<String, NewTournamentGame>(_addGame);
    deleteGame = Command1<void, String>((id) => _stats.deleteGame(teamId, id));
    deleteTournament = Command0<void>(
      () => _stats.deleteTournament(teamId, tournamentId),
    );
    _subs = [
      teamRepository.watchTeam(teamId).listen((t) {
        _team = t;
        notifyListeners();
      }, onError: (_) {}),
      _stats.watchPlayers(teamId).listen((p) {
        _players = p;
        notifyListeners();
      }, onError: _onError),
      _stats.watchTournaments(teamId).listen((t) {
        _tournament = t.where((x) => x.id == tournamentId).firstOrNull;
        _loaded = true;
        notifyListeners();
      }, onError: _onError),
      _stats.watchGames(teamId).listen((g) {
        _games = [
          for (final x in g.reversed)
            if (x.tournamentId == tournamentId) x,
        ];
        notifyListeners();
      }, onError: _onError),
    ];
  }

  final String teamId;
  final String tournamentId;
  final StatsRepository _stats;
  final AuthRepository _auth;
  late final List<StreamSubscription<Object?>> _subs;

  Team? _team;

  /// Owners, coaches and stats keepers manage it; everyone else views.
  bool get canEdit =>
      _team?.canKeepStats(_auth.currentUser?.uid ?? '') ?? false;

  /// Owners, coaches and captains delete games and the tournament.
  bool get canDelete => _team?.canEdit(_auth.currentUser?.uid ?? '') ?? false;
  static const _uuid = Uuid();

  StatsTournament? _tournament;
  StatsTournament? get tournament => _tournament;

  List<RosterPlayer> _players = const [];

  /// Whole team roster, to pick the tournament roster from.
  List<RosterPlayer> get allPlayers => _players;

  /// Players attending, in roster order.
  List<RosterPlayer> get roster {
    final ids = _tournament?.roster.toSet() ?? const {};
    return [
      for (final p in _players)
        if (ids.contains(p.id)) p,
    ];
  }

  /// Games in the order they were played.
  List<StatsGame> _games = const [];
  List<StatsGame> get games => _games;

  bool _loaded = false;
  bool get loaded => _loaded || _error != null;

  Object? _error;
  Object? get error => _error;

  int get wins => _games.where((g) => g.won == true).length;
  int get losses => _games.where((g) => g.won == false).length;

  StatSheet get sheet => StatSheet.fromGames(_games);

  String nameOf(String id) =>
      _players.where((p) => p.id == id).firstOrNull?.name ?? 'Player';

  /// Result is the new game's id.
  late final Command1<String, NewTournamentGame> addGame;

  late final Command1<void, String> deleteGame;

  /// Deletes the tournament and all its games.
  late final Command0<void> deleteTournament;

  Future<Result<String>> _addGame(NewTournamentGame g) => _stats.saveGame(
    teamId,
    StatsGame(
      id: '',
      opponent: g.opponent,
      date: DateTime.now(),
      gameTo: g.gameTo,
      timeoutsPerHalf: g.timeoutsPerHalf,
      tournamentId: tournamentId,
      eventId: tournament?.eventId,
    ),
  );

  void setRoster(List<String> ids) => _update(
    (t) => t.copyWith(
      roster: ids,
      // Lines can only use attending players.
      lines: [
        for (final l in t.lines)
          if (l.players.every(ids.contains)) l,
      ],
    ),
  );

  /// Adds a line, or replaces the one with the same id.
  void saveLine(String name, List<String> players, {String? id, Side? side}) {
    final line = StatLine(
      id: id ?? _uuid.v4(),
      name: name,
      players: players,
      side: side,
    );
    _update(
      (t) => t.copyWith(
        lines: [
          if (id == null) ...[
            ...t.lines,
            line,
          ] else
            for (final l in t.lines) l.id == id ? line : l,
        ],
      ),
    );
  }

  void deleteLine(String id) => _update(
    (t) => t.copyWith(lines: t.lines.where((l) => l.id != id).toList()),
  );

  void _update(StatsTournament Function(StatsTournament) change) {
    final t = _tournament;
    if (t == null || !canEdit) return;
    _tournament = change(t);
    notifyListeners();
    unawaited(_stats.saveTournament(teamId, _tournament!));
  }

  void _onError(Object e) {
    _error = e;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}
