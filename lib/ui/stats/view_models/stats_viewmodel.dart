import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/event/event_repository.dart';
import '../../../data/repositories/stats/stats_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../domain/models/roster_player.dart';
import '../../../domain/models/stats.dart';
import '../../../domain/models/team.dart';
import '../../../domain/models/team_event.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

typedef NewTournament = ({String name, DateTime startDate, TeamEvent? event});
typedef NewGame = ({
  String opponent,
  DateTime date,
  int gameTo,
  int timeoutsPerHalf,
  TeamEvent? event,
});
typedef NewEvent = ({String title, EventType type, DateTime startsAt});

/// Backs the Stats tab and the season stat sheet.
class StatsViewModel extends ChangeNotifier {
  StatsViewModel({
    required this.teamId,
    required StatsRepository statsRepository,
    required EventRepository eventRepository,
    required TeamRepository teamRepository,
    required AuthRepository authRepository,
  }) : _stats = statsRepository,
       _eventsRepo = eventRepository,
       _auth = authRepository {
    createTournament = Command1<String, NewTournament>(_createTournament);
    createGame = Command1<String, NewGame>(_createGame);
    createEvent = Command1<TeamEvent, NewEvent>(_createEvent);
    deleteGame = Command1<void, String>((id) => _stats.deleteGame(teamId, id));
    deleteTournament = Command1<void, String>(
      (id) => _stats.deleteTournament(teamId, id),
    );
    _subs = [
      _stats.watchPlayers(teamId).listen((p) {
        _players = {for (final x in p) x.id: x};
        notifyListeners();
      }, onError: _onError),
      _stats.watchTournaments(teamId).listen((t) {
        _tournaments = t;
        notifyListeners();
      }, onError: _onError),
      _stats.watchGames(teamId).listen((g) {
        _games = g;
        _loaded = true;
        notifyListeners();
      }, onError: _onError),
      eventRepository.watchEvents(teamId).listen((e) {
        _events = e;
        notifyListeners();
      }, onError: (_) {}),
      teamRepository.watchTeam(teamId).listen((t) {
        _team = t;
        notifyListeners();
      }, onError: (_) {}),
    ];
  }

  final String teamId;
  final StatsRepository _stats;
  final EventRepository _eventsRepo;
  final AuthRepository _auth;
  late final List<StreamSubscription<Object?>> _subs;

  Map<String, RosterPlayer> _players = const {};
  List<StatsTournament> _tournaments = const [];
  List<StatsGame> _games = const [];
  List<TeamEvent> _events = const [];
  Team? _team;

  bool _loaded = false;
  bool get loaded => _loaded || _error != null;

  Object? _error;
  Object? get error => _error;

  /// Creating games and tournaments: owners, coaches and stats keepers.
  bool get canEdit =>
      _team?.canKeepStats(_auth.currentUser?.uid ?? '') ?? false;

  /// Adding schedule events: team admins.
  bool get canCreateEvents =>
      _team?.canEdit(_auth.currentUser?.uid ?? '') ?? false;

  /// Deleting games and tournaments: owners, coaches and captains, not
  /// players with stats access.
  bool get canDelete => canCreateEvents;

  List<StatsTournament> get tournaments => _tournaments;

  List<StatsGame> gamesIn(String tournamentId) => [
    for (final g in _games)
      if (g.tournamentId == tournamentId) g,
  ];

  /// Games outside any tournament.
  List<StatsGame> get standaloneGames => [
    for (final g in _games)
      if (g.tournamentId == null) g,
  ];

  int get wins => _games.where((g) => g.won == true).length;
  int get losses => _games.where((g) => g.won == false).length;

  StatSheet get seasonSheet => StatSheet.fromGames(_games);

  String nameOf(String playerId) => _players[playerId]?.name ?? 'Player';

  RosterPlayer? player(String id) => _players[id];

  /// Schedule events a tournament (tournament events) or a game (any
  /// game, practice or other event, e.g. a scrimmage at practice) can be
  /// linked to, closest to today first.
  List<TeamEvent> linkableEvents(EventType kind) {
    final now = DateTime.now();
    Duration away(TeamEvent e) => e.startsAt.difference(now).abs();
    return [
      for (final e in _events)
        if (kind == EventType.tournament
            ? e.type == EventType.tournament
            : e.type != EventType.social && e.type != EventType.workout)
          e,
    ]..sort((a, b) => away(a).compareTo(away(b)));
  }

  /// Lines already built for [event] by another game or tournament.
  List<StatLine> linesForEvent(TeamEvent? event) =>
      LineSource.forEvent(event?.id, LineSource.from(_tournaments, _games));

  late final Command1<String, NewTournament> createTournament;
  late final Command1<String, NewGame> createGame;

  /// Adds an event to the schedule, e.g. a scrimmage started mid-practice.
  late final Command1<TeamEvent, NewEvent> createEvent;

  late final Command1<void, String> deleteGame;

  /// Deletes a tournament with all its games.
  late final Command1<void, String> deleteTournament;

  Future<Result<TeamEvent>> _createEvent(NewEvent e) async {
    final event = TeamEvent(
      id: '',
      title: e.title,
      type: e.type,
      startsAt: e.startsAt,
      createdBy: _auth.currentUser?.uid,
    );
    final r = await _eventsRepo.saveEvent(
      teamId,
      event,
      _auth.currentUser?.uid ?? '',
    );
    return switch (r) {
      Ok(:final value) => Result.ok(
        TeamEvent(
          id: value,
          title: event.title,
          type: event.type,
          startsAt: event.startsAt,
          createdBy: event.createdBy,
        ),
      ),
      Error(:final error) => Result.error(error),
    };
  }

  Future<Result<String>> _createTournament(NewTournament t) =>
      _stats.saveTournament(
        teamId,
        StatsTournament(
          id: '',
          name: t.name,
          startDate: t.startDate,
          location: t.event?.location ?? '',
          eventId: t.event?.id,
          roster: _players.keys.toList(),
          lines: linesForEvent(t.event),
        ),
      );

  Future<Result<String>> _createGame(NewGame g) => _stats.saveGame(
    teamId,
    StatsGame(
      id: '',
      opponent: g.opponent,
      date: g.date,
      gameTo: g.gameTo,
      timeoutsPerHalf: g.timeoutsPerHalf,
      eventId: g.event?.id,
      lines: linesForEvent(g.event),
    ),
  );

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
