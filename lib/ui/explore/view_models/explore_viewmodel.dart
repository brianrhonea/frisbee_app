import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/hosted_tournament/hosted_tournament_repository.dart';
import '../../../data/repositories/ranking/ranking_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../domain/models/hosted_tournament.dart';
import '../../../domain/models/ranking.dart';
import '../../../domain/models/team.dart';

/// Team rankings by division, or the player ranking.
enum RankingKind { teams, players }

/// Explore's cards beside search: upcoming tournaments, recent results
/// and a rankings preview. The Rankings page uses it too.
class ExploreViewModel extends ChangeNotifier {
  ExploreViewModel({
    required HostedTournamentRepository tournamentRepository,
    required RankingRepository rankingRepository,
    TeamRepository? teamRepository,
    AuthRepository? authRepository,
    this.initialRanking,
  }) : _uid = authRepository?.currentUser?.uid,
       _kind = initialRanking == playersKey
           ? RankingKind.players
           : RankingKind.teams {
    _subs
      ..add(
        tournamentRepository.watchUpcoming(limit: 30).listen((l) {
          _upcoming = l;
          _tournamentsLoaded = true;
          notifyListeners();
        }, onError: _fail),
      )
      ..add(
        rankingRepository.watchRankings().listen((l) {
          _rankings = [...l]
            ..sort((a, b) {
              final level = a.level.index.compareTo(b.level.index);
              return level != 0
                  ? level
                  : a.division.index.compareTo(b.division.index);
            });
          _rankingsLoaded = true;
          notifyListeners();
        }, onError: _fail),
      )
      ..add(
        rankingRepository.watchRecentResults().listen((l) {
          _results = l;
          notifyListeners();
        }, onError: (Object _) {}),
      )
      ..add(
        rankingRepository.watchPlayerRankings().listen(
          (r) {
            _players = r;
            _playersLoaded = true;
            notifyListeners();
          },
          onError: (Object _) {
            _playersLoaded = true;
            notifyListeners();
          },
        ),
      );
    final uid = authRepository?.currentUser?.uid;
    if (teamRepository != null && uid != null) {
      _subs.add(
        teamRepository.watchMyTeams(uid).listen((teams) {
          _myTeams = teams;
          notifyListeners();
        }, onError: (Object _) {}),
      );
    }
  }

  /// The ranking to open on ("club-mixed", or [playersKey]), from the
  /// page's link.
  final String? initialRanking;

  /// [initialRanking] for the player ranking.
  static const playersKey = 'players';

  final String? _uid;
  RankingKind _kind;
  PlayerRanking _players = const PlayerRanking();
  bool _playersLoaded = false;

  /// Teams or players.
  RankingKind get kind => _kind;

  void setKind(RankingKind kind) {
    _kind = kind;
    notifyListeners();
  }

  /// Rated players, best first.
  PlayerRanking get playerRanking => _players;
  bool get playersLoaded => _playersLoaded || _error != null;

  /// Whether [uid] is the user, to highlight their row.
  bool isMe(String uid) => uid == _uid;

  /// The link to the ranking showing: [playersKey] or a division's key.
  String? get rankingLink =>
      _kind == RankingKind.players ? playersKey : ranking?.key;

  final List<StreamSubscription<Object?>> _subs = [];

  List<HostedTournament> _upcoming = const [];
  List<DivisionRanking> _rankings = const [];
  List<TournamentResult> _results = const [];
  List<Team> _myTeams = const [];
  bool _tournamentsLoaded = false;
  bool _rankingsLoaded = false;
  Object? _error;
  String? _picked;

  bool get tournamentsLoaded => _tournamentsLoaded || _error != null;
  bool get rankingsLoaded => _rankingsLoaded || _error != null;
  Object? get error => _error;

  /// How many tournaments and results Explore's cards show.
  static const previewCount = 4;

  /// Rankings Explore's preview shows.
  static const previewTeams = 5;

  /// Published tournaments from a week ago on, soonest first.
  List<HostedTournament> get upcoming => _upcoming;

  /// Recently finished public tournaments, newest first.
  List<TournamentResult> get results => _results;

  /// Every division with ranked teams, by level then division.
  List<DivisionRanking> get rankings => _rankings;

  /// The ranking shown: the one picked, else the one linked to, else the
  /// division of the user's first team that has one, else the biggest.
  DivisionRanking? get ranking {
    if (_rankings.isEmpty) return null;
    DivisionRanking? byKey(String? key) =>
        _rankings.where((r) => r.key == key).firstOrNull;
    final mine = [
      for (final t in _myTeams)
        if (t.kind == TeamKind.team)
          DivisionRanking.keyFor(t.level, t.division),
    ];
    return byKey(_picked) ??
        byKey(initialRanking) ??
        mine.map(byKey).nonNulls.firstOrNull ??
        (_rankings.toList()
              ..sort((a, b) => b.teams.length.compareTo(a.teams.length)))
            .first;
  }

  void pickRanking(String key) {
    _picked = key;
    notifyListeners();
  }

  /// Whether [teamId] is one of the user's teams, to highlight its row.
  bool isMine(String teamId) => _myTeams.any((t) => t.id == teamId);

  /// Upcoming tournaments whose name, host or place has every word of
  /// [query]; none for an empty query.
  List<HostedTournament> matching(String query) {
    final words = query.toLowerCase().split(RegExp(r'\s+'))
      ..removeWhere((w) => w.isEmpty);
    if (words.isEmpty) return const [];
    return [
      for (final t in _upcoming)
        if (words.every(
          '${t.name} ${t.hostName} ${t.location}'.toLowerCase().contains,
        ))
          t,
    ];
  }

  void _fail(Object e) {
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
