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
/// and a rankings preview. The Rankings page uses it too
/// ([rankingsPage]), with its Level and Division filters.
///
/// Youth is never ranked or shown: the `rankings` Cloud Functions skip
/// it, and a youth ranking that's still stored is left out here too.
class ExploreViewModel extends ChangeNotifier {
  ExploreViewModel({
    required HostedTournamentRepository tournamentRepository,
    required RankingRepository rankingRepository,
    TeamRepository? teamRepository,
    AuthRepository? authRepository,
    this.rankingsPage = false,
    RankingKind kind = RankingKind.teams,
    String? level,
    String? division,
  }) : _uid = authRepository?.currentUser?.uid,
       _kind = kind,
       _level = level,
       _division = division {
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
          _rankings =
              [
                for (final r in l)
                  if (r.isRanked && r.teams.isNotEmpty) r,
              ]..sort((a, b) {
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

  /// The Rankings page: with nothing asked for, it opens on Club Mixed
  /// (else the first ranking), as the website does; Explore's preview
  /// opens on the user's team's division, else the biggest.
  final bool rankingsPage;

  final String? _uid;
  RankingKind _kind;

  /// The level and division asked for (by the link or a filter), by name;
  /// [ranking] falls back when there's no such ranking.
  String? _level;
  String? _division;
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

  /// The Rankings page's link query for what's showing:
  /// `{kind: players}` or `{level: club, division: mixed}`.
  Map<String, String>? get rankingLink {
    if (_kind == RankingKind.players) return const {'kind': 'players'};
    final r = ranking;
    return r == null
        ? null
        : {'level': r.level.name, 'division': r.division.name};
  }

  final List<StreamSubscription<Object?>> _subs = [];

  List<HostedTournament> _upcoming = const [];
  List<DivisionRanking> _rankings = const [];
  List<TournamentResult> _results = const [];
  List<Team> _myTeams = const [];
  bool _tournamentsLoaded = false;
  bool _rankingsLoaded = false;
  Object? _error;

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

  /// The ranking shown: the level and division asked for (see
  /// [RankingChoice.choose] for the fallbacks); with nothing asked for,
  /// Club Mixed (else the first) on the Rankings page, and in Explore's
  /// preview the division of the user's first team that has one, else
  /// the biggest.
  DivisionRanking? get ranking {
    if (_rankings.isEmpty) return null;
    DivisionRanking? byKey(String? key) =>
        _rankings.where((r) => r.key == key).firstOrNull;
    if (rankingsPage || _level != null || _division != null) {
      return byKey(_choice()?.key);
    }
    final mine = [
      for (final t in _myTeams)
        if (t.kind == TeamKind.team)
          DivisionRanking.keyFor(t.level, t.division),
    ];
    return mine.map(byKey).nonNulls.firstOrNull ??
        (_rankings.toList()
              ..sort((a, b) => b.teams.length.compareTo(a.teams.length)))
            .first;
  }

  RankingChoice? _choice() => RankingChoice.choose(
    _rankings.map((r) => r.key),
    level: _level,
    division: _division,
  );

  /// The Level and Division filters for [ranking]: their options (only
  /// those with rankings) and what they're set to.
  RankingChoice? get rankingChoice {
    final r = ranking;
    return r == null
        ? null
        : RankingChoice.choose(
            _rankings.map((x) => x.key),
            level: r.level.name,
            division: r.division.name,
          );
  }

  /// Shows [level]'s ranking for the division showing, else its first.
  void pickLevel(CompetitionLevel level) {
    _division = ranking?.division.name;
    _level = level.name;
    notifyListeners();
  }

  /// Shows [division]'s ranking at the level showing, if it has one.
  void pickDivision(Division division) {
    _level = ranking?.level.name;
    _division = division.name;
    notifyListeners();
  }

  /// Shows the ranking with [key] ("club-mixed").
  void pickRanking(String key) {
    final p = RankingChoice.parseKey(key);
    if (p == null) return;
    _level = p.level.name;
    _division = p.division.name;
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
