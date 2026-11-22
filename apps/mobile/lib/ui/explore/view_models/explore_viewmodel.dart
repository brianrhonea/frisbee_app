import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/discover/discover_repository.dart';
import '../../../data/repositories/hosted_tournament/hosted_tournament_repository.dart';
import '../../../data/repositories/ranking/ranking_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../domain/models/discover.dart';
import '../../../domain/models/group_tournament.dart';
import '../../../domain/models/hosted_tournament.dart';
import '../../../domain/models/ranking.dart';
import '../../../domain/models/team.dart';
import '../../../routing/routes.dart' show ExploreFilter;
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// Team rankings by division, or the player ranking.
enum RankingKind { teams, players }

/// A game being played now at a live event, for Discover's "Live now":
/// its teams' names and running score.
typedef LiveGameRow = ({
  String divisionId,
  GroupGame game,
  String nameA,
  String nameB,
  LiveScore live,
});

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
    DiscoverRepository? discoverRepository,
    this.rankingsPage = false,
    RankingKind kind = RankingKind.teams,
    String? level,
    String? division,
    DateTime Function()? now,
  }) : _uid = authRepository?.currentUser?.uid,
       _tournamentRepo = tournamentRepository,
       _discoverRepo = discoverRepository,
       _now = now ?? DateTime.now,
       _kind = kind,
       _level = level,
       _division = division {
    _subs
      ..add(
        tournamentRepository.watchUpcoming(limit: 30).listen((l) {
          _upcoming = l;
          _watchLive();
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
    loadPublic = Command0(_loadPublic);
    if (!rankingsPage && discoverRepository != null) loadPublic.execute();
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
  final HostedTournamentRepository _tournamentRepo;
  final DiscoverRepository? _discoverRepo;
  final DateTime Function() _now;
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

  // ---- Public lists (GET /v1/public/events, /v1/public/tournaments) ------

  /// Reads public team events (F29) and tournaments' spots left (F10), as
  /// the website's Discover does; its error is the events'.
  late final Command0<void> loadPublic;

  List<PublicTeamEvent> _publicEvents = const [];
  Map<String, TournamentSpots> _spots = const {};
  bool _publicLoaded = false;

  /// Whether Discover lists public team events (it reads the API's lists).
  bool get discoversPublicEvents => _discoverRepo != null;

  /// Whether the public events are in (or failed: see [loadPublic]).
  bool get publicEventsLoaded => _publicLoaded || _discoverRepo == null;

  /// Upcoming public team events across teams and communities, soonest
  /// first.
  List<PublicTeamEvent> get publicEvents => _publicEvents;

  /// Public team events a chip shows (eventsFor on the website): every one
  /// for All, pickup games for Pickup, none for the others.
  List<PublicTeamEvent> publicEventsFor(ExploreFilter? only) => switch (only) {
    null => _publicEvents,
    ExploreFilter.pickup => [
      for (final e in _publicEvents)
        if (e.isPickup) e,
    ],
    _ => const [],
  };

  /// Public team events for [only] whose title, team or place has every
  /// word of [query]; none for an empty query.
  List<PublicTeamEvent> matchingEvents(String query, ExploreFilter? only) {
    final words = query.toLowerCase().split(RegExp(r'\s+'))
      ..removeWhere((w) => w.isEmpty);
    if (words.isEmpty) return const [];
    return [
      for (final e in publicEventsFor(only))
        if (words.every(
          '${e.title} ${e.teamName} ${e.location}'.toLowerCase().contains,
        ))
          e,
    ];
  }

  /// Team spots left in [tournamentId] while registration is open; null
  /// when it shows none.
  TournamentSpots? spotsOf(String tournamentId) => _spots[tournamentId];

  Future<Result<void>> _loadPublic() async {
    final repo = _discoverRepo;
    if (repo == null) return const Result.ok(null);
    final (events, spots) = await (
      repo.upcomingEvents(),
      repo.tournamentSpots(),
    ).wait;
    if (spots case Ok(:final value)) _spots = value;
    _publicLoaded = true;
    switch (events) {
      case Ok(:final value):
        _publicEvents = value;
        notifyListeners();
        return const Result.ok(null);
      case Error(:final error):
        notifyListeners();
        return Result.error(error);
    }
  }

  // ---- Live now -----------------------------------------------------------

  /// Per live event: its divisions' live games, entries and divisions
  /// (for the teams' names), only while it's live.
  final _live = <String, _LiveWatch>{};

  /// Keeps a watch on each live event (status Live) on the list's games
  /// being played; few are live at once, and only recently updated games
  /// are read.
  void _watchLive() {
    if (_rankingsOnly) return;
    final live = {
      for (final t in _upcoming)
        if (t.status == HostedStatus.live) t.id: t,
    };
    for (final id in [..._live.keys]) {
      if (!live.containsKey(id)) _live.remove(id)?.cancel();
    }
    for (final t in live.values) {
      _live[t.id] ??= _LiveWatch(_tournamentRepo, t, notifyListeners);
    }
  }

  bool get _rankingsOnly => rankingsPage;

  /// [tournamentId]'s games being played now (most recently updated
  /// first), for its "Live now" card.
  List<LiveGameRow> liveGamesOf(String tournamentId) {
    final w = _live[tournamentId];
    if (w == null) return const [];
    final now = _now();
    final rows = <LiveGameRow>[];
    for (final MapEntry(key: divisionId, value: games) in w.games.entries) {
      for (final g in games) {
        final l = g.liveAt(now);
        if (l == null || !g.hasTeams) continue;
        rows.add((
          divisionId: divisionId,
          game: g,
          nameA: w.nameOf(g.teamA),
          nameB: w.nameOf(g.teamB),
          live: l,
        ));
      }
    }
    rows.sort((a, b) {
      final x = a.live.updatedAt;
      final y = b.live.updatedAt;
      return x == null || y == null ? 0 : y.compareTo(x);
    });
    return rows;
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    for (final w in _live.values) {
      w.cancel();
    }
    super.dispose();
  }
}

/// The watches behind one live event's "Live now" games.
class _LiveWatch {
  _LiveWatch(
    HostedTournamentRepository repo,
    HostedTournament t,
    void Function() changed,
  ) {
    _subs.add(
      repo.watchEntries(t.id).listen((e) {
        _names = {for (final x in e) x.teamId: x.teamName};
        changed();
      }, onError: (Object _) {}),
    );
    _subs.add(
      repo.watchDivisions(t.id).listen((d) {
        _drafted = {
          for (final div in d)
            for (final team in div.teams) team.id: team.name,
        };
        // Each division's recently updated games (few, often none).
        for (final div in d) {
          _gameSubs[div.id] ??= repo.watchLiveGames(t.id, div.id).listen((g) {
            games[div.id] = g;
            changed();
          }, onError: (Object _) {});
        }
        changed();
      }, onError: (Object _) {}),
    );
  }

  final _subs = <StreamSubscription<Object?>>[];
  final _gameSubs = <String, StreamSubscription<List<GroupGame>>>{};
  final games = <String, List<GroupGame>>{};
  Map<String, String> _names = const {};
  Map<String, String> _drafted = const {};

  String nameOf(String? teamId) => _names[teamId] ?? _drafted[teamId] ?? 'Team';

  void cancel() {
    for (final s in [..._subs, ..._gameSubs.values]) {
      s.cancel();
    }
  }
}
