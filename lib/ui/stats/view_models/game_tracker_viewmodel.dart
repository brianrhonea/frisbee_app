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

/// Actions that wait for a player tap: "Score, then who caught it".
const armableKinds = {
  StatKind.goal,
  StatKind.drop,
  StatKind.handBlock,
  StatKind.breakup,
  StatKind.beat,
};

/// A change that [GameTrackerViewModel.undo] can take back: the game as it
/// was before, and what the change was, for the Undo button.
typedef _UndoStep = ({StatsGame before, String label, Side? sideOverride});

/// Live stat tracking for one game.
///
/// On O, tapping a player records a catch from the current holder (or a
/// pickup when nobody has it). Scores, drops and defensive plays are armed
/// first, then credited to the next player tapped. Once someone reaches
/// the game's target score, tracking stops. Every change to the game can
/// be undone, newest first.
class GameTrackerViewModel extends ChangeNotifier {
  GameTrackerViewModel({
    required this.teamId,
    required this.gameId,
    required StatsRepository statsRepository,
    required TeamRepository teamRepository,
    required AuthRepository authRepository,
  }) : _stats = statsRepository,
       _auth = authRepository {
    deleteGame = Command0<void>(() => _stats.deleteGame(teamId, gameId));
    _subs = [
      teamRepository.watchTeam(teamId).listen((t) {
        _team = t;
        notifyListeners();
      }, onError: (_) {}),
      _stats.watchPlayers(teamId).listen((p) {
        _players = {for (final x in p) x.id: x};
        notifyListeners();
      }, onError: _onError),
      _stats.watchGames(teamId).listen((g) {
        _otherGames = [
          for (final x in g)
            if (x.id != gameId) x,
        ];
        // Local edits are the source of truth once loaded.
        if (_game == null) {
          _game = g.where((x) => x.id == gameId).firstOrNull;
          _loaded = true;
        }
        notifyListeners();
      }, onError: _onError),
      _stats.watchTournaments(teamId).listen((t) {
        _tournaments = {for (final x in t) x.id: x};
        notifyListeners();
      }, onError: _onError),
    ];
  }

  final String teamId;
  final String gameId;
  final StatsRepository _stats;
  final AuthRepository _auth;
  late final List<StreamSubscription<Object?>> _subs;
  static const _uuid = Uuid();

  Team? _team;

  /// Owners, coaches and stats keepers keep stats; everyone else views.
  bool get canEdit =>
      _team?.canKeepStats(_auth.currentUser?.uid ?? '') ?? false;

  /// Owners, coaches and captains may delete the game.
  bool get canDelete => _team?.canEdit(_auth.currentUser?.uid ?? '') ?? false;

  late final Command0<void> deleteGame;

  Object? _saveError;

  /// The last save that failed, until a later one succeeds.
  Object? get saveError => _saveError;

  StatsGame? _game;
  StatsGame? get game => _game;

  Map<String, RosterPlayer> _players = const {};
  Map<String, StatsTournament> _tournaments = const {};
  List<StatsGame> _otherGames = const [];

  bool _loaded = false;
  bool get loaded => _loaded || _error != null;

  Object? _error;
  Object? get error => _error;

  StatsTournament? get tournament => _tournaments[_game?.tournamentId];

  String nameOf(String? id) => _players[id]?.name ?? 'Player';
  RosterPlayer? player(String id) => _players[id];

  // ---- Game ----------------------------------------------------------------

  /// No more stats: someone reached game point or the game was ended.
  bool get over => _game?.over ?? false;

  int get gameTo => _game?.gameTo ?? 15;

  /// Fixes the target score, e.g. a game that's really to 15, not 11.
  /// Raising it past both scores reopens tracking.
  void setGameTo(int target) {
    final g = _game;
    if (g == null || target < 1) return;
    _armed = null;
    _commit(g.copyWith(gameTo: target), undo: 'Game point change');
  }

  // ---- Timeouts --------------------------------------------------------------

  int get timeoutsPerHalf => _game?.timeoutsPerHalf ?? 2;
  int get half => _game?.half ?? 1;
  List<GameTimeout> get timeouts => _game?.timeouts ?? const [];

  int timeoutsLeft({required bool ours}) =>
      _game?.timeoutsLeft(ours: ours) ?? 0;

  bool canCallTimeout({required bool ours}) =>
      canEdit && !over && timeoutsLeft(ours: ours) > 0;

  void callTimeout({required bool ours}) {
    final g = _game;
    if (g == null || !canCallTimeout(ours: ours)) return;
    final t = GameTimeout(
      ours: ours,
      half: g.half,
      point: currentPoint == null ? points.length : points.length - 1,
      action: currentPoint?.actions.length ?? 0,
    );
    _commit(
      g.copyWith(timeouts: [...g.timeouts, t]),
      undo: ours ? 'Our timeout' : 'Their timeout',
    );
  }

  /// Takes back a timeout logged by mistake.
  void removeTimeout(GameTimeout t) {
    final g = _game;
    if (g == null) return;
    _commit(
      g.copyWith(timeouts: [...g.timeouts]..remove(t)),
      undo: 'Timeout removed',
    );
  }

  void setTimeoutsPerHalf(int n) {
    final g = _game;
    if (g == null || n < 0) return;
    _commit(g.copyWith(timeoutsPerHalf: n));
  }

  /// Ends (or resumes) the game by hand, e.g. at a time cap.
  void setFinished(bool value) {
    final g = _game;
    if (g == null) return;
    _armed = null;
    _commit(
      g.copyWith(finished: value),
      undo: value ? 'Game ended' : 'Game resumed',
    );
  }

  // ---- Lines -----------------------------------------------------------------

  /// Players who can be put on a line: the tournament roster, or the whole
  /// team for a standalone game.
  List<RosterPlayer> get available {
    final ids = tournament?.roster.toSet();
    return [
      for (final p in _players.values)
        if (ids == null || ids.contains(p.id)) p,
    ];
  }

  /// The tournament's lines (shared by its games), or this game's own.
  List<StatLine> get savedLines =>
      tournament?.lines ?? _game?.lines ?? const [];

  /// Saves a new line, or replaces the one with [id].
  void saveLine(String name, List<String> players, {String? id, Side? side}) {
    if (players.length != StatLine.size) return;
    final line = StatLine(
      id: id ?? _uuid.v4(),
      name: name,
      players: players,
      side: side,
    );
    _setLines([
      if (id == null) ...[
        ...savedLines,
        line,
      ] else
        for (final l in savedLines) l.id == id ? line : l,
    ]);
  }

  void deleteLine(String id) => _setLines([
    for (final l in savedLines)
      if (l.id != id) l,
  ]);

  /// Other tournaments and games to copy lines from; those linked to the
  /// same schedule event come first.
  List<LineSource> get lineSources {
    final own = tournament?.id;
    final all = [
      for (final s in LineSource.from(_tournaments.values, _otherGames))
        if (s.id != own) s,
    ];
    final event = _game?.eventId;
    return [
      ...all.where((s) => event != null && s.eventId == event),
      ...all.where((s) => event == null || s.eventId != event),
    ];
  }

  /// Lines from the linked event that this game doesn't have yet.
  List<StatLine> get eventLinesToImport {
    final have = {for (final l in savedLines) l.key};
    return [
      for (final l in LineSource.forEvent(_game?.eventId, lineSources))
        if (!have.contains(l.key)) l,
    ];
  }

  /// Copies [lines] in, skipping duplicates and lines with players who
  /// aren't available here. Returns how many were added.
  int importLines(List<StatLine> lines) {
    final have = {for (final l in savedLines) l.key};
    final ok = {for (final p in available) p.id};
    final added = [
      for (final l in lines)
        if (l.players.every(ok.contains) && have.add(l.key))
          StatLine(
            id: _uuid.v4(),
            name: l.name,
            players: l.players,
            side: l.side,
          ),
    ];
    if (added.isNotEmpty) _setLines([...savedLines, ...added]);
    return added.length;
  }

  void _setLines(List<StatLine> lines) {
    if (!canEdit) return;
    final t = tournament;
    if (t != null) {
      final saved = t.copyWith(lines: lines);
      _tournaments = {..._tournaments, t.id: saved};
      notifyListeners();
      unawaited(_stats.saveTournament(teamId, saved).then(_saved));
    } else if (_game case final g?) {
      _commit(g.copyWith(lines: lines));
    }
  }

  /// Starting line of the most recent point played on [side].
  List<String>? lastLineFor(Side side) => points.reversed
      .where((p) => p.startedOn == side && p.line.length == StatLine.size)
      .firstOrNull
      ?.line;

  /// Saved lines for [side] first, then lines built for either side.
  List<StatLine> linesFor(Side side) => [
    ...savedLines.where((l) => l.side == side),
    ...savedLines.where((l) => l.side == null),
  ];

  /// Starts the next point with [players], or swaps the line of a point
  /// that hasn't had any action yet. [saveAs] also saves it as a line.
  void useLine(List<String> players, {String? saveAs, Side? saveSide}) {
    if (players.length != StatLine.size || over) return;
    if (saveAs != null && saveAs.isNotEmpty) {
      saveLine(saveAs, players, side: saveSide);
    }
    final current = currentPoint;
    if (current != null && current.actions.isEmpty) {
      _replaceCurrent(
        StatPoint(line: players, startedOn: current.startedOn),
        undo: 'Line change',
      );
    } else if (current == null) {
      _setPoints([
        ...points,
        StatPoint(line: players, startedOn: nextSide),
      ], undo: 'Start of point $pointNumber');
      _sideOverride = null;
    }
  }

  // Line being picked for the next point.
  final Set<String> _draft = {};
  Set<String> get draftLine => _draft;
  bool get draftReady => _draft.length == StatLine.size;

  void toggleDraft(String id) {
    if (!_draft.remove(id) && _draft.length < StatLine.size) _draft.add(id);
    notifyListeners();
  }

  void fillDraft(List<String> ids) {
    _draft
      ..clear()
      ..addAll(ids.take(StatLine.size));
    notifyListeners();
  }

  void clearDraft() {
    _draft.clear();
    notifyListeners();
  }

  /// Starts the next point with the drafted line, in roster order.
  void startDraft() {
    if (!draftReady) return;
    final ids = [
      for (final p in available)
        if (_draft.contains(p.id)) p.id,
    ];
    _draft.clear();
    useLine(ids);
  }

  /// Players on the field now.
  List<String> get onField => currentPoint?.onField ?? const [];

  /// Available players not on the field.
  List<RosterPlayer> get bench {
    final field = onField.toSet();
    return [
      for (final p in available)
        if (!field.contains(p.id)) p,
    ];
  }

  /// [inId] replaces [outId] mid-point. If [outId] has the disc (an
  /// injury), [inId] takes it over without a catch and throws next.
  bool canSubOut(String id) => canTrack && onField.contains(id);

  void substitute(String outId, String inId) {
    if (!canSubOut(outId) || onField.contains(inId)) return;
    _record(StatAction(StatKind.sub, playerId: inId, subOutId: outId));
  }

  // ---- Point state -------------------------------------------------------------

  List<StatPoint> get points => _game?.points ?? const [];

  /// The point being played, if any.
  StatPoint? get currentPoint =>
      points.isNotEmpty && points.last.result == null ? points.last : null;

  /// 1-based number of the current (or next) point.
  int get pointNumber => points.length + (currentPoint == null ? 1 : 0);

  Side? _sideOverride;

  /// Side the next point starts on: after we score we pull (D), after they
  /// score we receive (O), unless set by hand.
  Side get nextSide {
    if (_sideOverride case final s?) return s;
    final last = points.lastOrNull;
    if (last == null) return Side.offense;
    return last.result == PointResult.weScored ? Side.defense : Side.offense;
  }

  Side get side => currentPoint?.side ?? nextSide;

  /// O/D can be changed by hand until the point's first action.
  bool get canSetSide =>
      canEdit && (currentPoint?.actions.isEmpty ?? true) && !over;

  void setSide(Side s) {
    if (!canSetSide) return;
    final current = currentPoint;
    if (current != null) {
      _replaceCurrent(
        StatPoint(line: current.line, startedOn: s),
        undo: 'Switch to ${s.short}',
      );
    } else {
      _sideOverride = s;
      notifyListeners();
    }
  }

  String? get holder => currentPoint?.holder;

  /// Who has touched the disc this possession, in order.
  List<String> get passChain {
    final chain = <String>[];
    for (final a in currentPoint?.actions ?? const <StatAction>[]) {
      if (a.turnsOver) {
        chain.clear();
      } else if (a.kind case StatKind.pickup || StatKind.catch_) {
        chain.add(a.playerId!);
      }
    }
    return chain;
  }

  StatKind? _armed;

  /// Action waiting for a player tap.
  StatKind? get armed => _armed;

  bool get canTrack => canEdit && currentPoint != null && !over;

  // ---- Pull ------------------------------------------------------------------

  /// We pull at the start of a D point, before anything else happens.
  bool get canPull =>
      canTrack &&
      currentPoint!.startedOn == Side.defense &&
      !currentPoint!.hasPull &&
      !currentPoint!.actions.any((a) => a.turnsOver);

  /// Whoever pulled last this game, as the default puller.
  String? get lastPuller {
    for (final p in points.reversed) {
      for (final a in p.actions) {
        if (a.kind == StatKind.pull && onField.contains(a.playerId)) {
          return a.playerId;
        }
      }
    }
    return null;
  }

  void recordPull(
    String playerId, {
    required Duration hangTime,
    required bool outOfBounds,
  }) {
    if (!canPull || !onField.contains(playerId)) return;
    final point = currentPoint!;
    final pull = StatAction(
      StatKind.pull,
      playerId: playerId,
      hangTimeMs: hangTime.inMilliseconds,
      outOfBounds: outOfBounds,
    );
    // Keep the pull first even if a stat was logged before it.
    _replaceCurrent(
      point.copyWith(actions: [pull, ...point.actions]),
      undo: describe(pull),
    );
  }

  // ---- Recording ---------------------------------------------------------------

  void arm(StatKind kind) {
    if (!armableKinds.contains(kind) || !canTrack) return;
    final onO = side == Side.offense;
    final needsDisc = kind == StatKind.goal || kind == StatKind.drop;
    if (needsDisc ? !onO || holder == null : onO) return;
    _armed = _armed == kind ? null : kind;
    notifyListeners();
  }

  /// A player on the field was tapped.
  void tapPlayer(String id) {
    final point = currentPoint;
    if (point == null || over || !point.onField.contains(id)) return;
    final armed = _armed;
    final h = point.holder;
    if (armed != null) {
      final passed = armed == StatKind.goal || armed == StatKind.drop;
      // The holder can't catch their own throw.
      if (passed && id == h) return;
      _armed = null;
      final a = StatAction(armed, playerId: id, throwerId: passed ? h : null);
      if (armed == StatKind.goal) {
        _replaceCurrent(
          point.copyWith(
            actions: [...point.actions, a],
            result: () => PointResult.weScored,
          ),
          undo: 'Score: ${describe(a)}',
        );
      } else {
        _record(a);
      }
      return;
    }
    if (point.side != Side.offense || h == id) return;
    _record(
      h == null
          ? StatAction(StatKind.pickup, playerId: id)
          : StatAction(StatKind.catch_, playerId: id, throwerId: h),
    );
  }

  /// Arms Score: the next player tapped caught the goal.
  bool get canScore => canTrack && side == Side.offense && holder != null;

  void throwaway() {
    final h = holder;
    if (!canTrack || h == null) return;
    _record(StatAction(StatKind.throwaway, playerId: h));
  }

  /// Opponent turned it over unforced.
  void weGotIt() {
    if (!canTrack || side != Side.defense) return;
    _record(const StatAction(StatKind.theirTurnover));
  }

  /// Opponent scored. Allowed any time, even between points, so a missed
  /// turnover never blocks the scoreboard.
  bool get canOpponentScore => canEdit && !over && _game != null;

  void theyScored() {
    if (!canOpponentScore) return;
    _armed = null;
    final point = currentPoint;
    if (point == null) {
      _setPoints([
        ...points,
        StatPoint(
          line: const [],
          startedOn: nextSide,
          result: PointResult.theyScored,
        ),
      ], undo: 'They scored');
      _sideOverride = null;
    } else {
      _replaceCurrent(
        point.copyWith(result: () => PointResult.theyScored),
        undo: 'They scored',
      );
    }
  }

  /// Changes made on this screen, oldest first, so each can be undone.
  final List<_UndoStep> _history = [];
  static const _maxHistory = 200;

  /// Undo works even at game point or after ending the game, so a wrong
  /// final score can be fixed. Changes from before this screen was opened
  /// can still be stepped back one action at a time.
  bool get canUndo =>
      canEdit &&
      (_armed != null ||
          _history.isNotEmpty ||
          (!(_game?.finished ?? true) && points.isNotEmpty));

  /// What [undo] will take back, e.g. "Alex → Sam", for the Undo button.
  String? get undoLabel {
    if (!canUndo) return null;
    if (_armed case final kind?) return 'Cancel ${_armedLabel(kind)}';
    if (_history.lastOrNull case final step?) return step.label;
    final point = points.last;
    if (point.result == PointResult.theyScored) return 'They scored';
    if (point.actions.lastOrNull case final a?) {
      return a.kind == StatKind.goal ? 'Score: ${describe(a)}' : describe(a);
    }
    return 'Start of point ${points.length}';
  }

  static String _armedLabel(StatKind kind) => switch (kind) {
    StatKind.goal => 'Score',
    StatKind.drop => 'Drop',
    StatKind.handBlock => 'Hand block',
    StatKind.breakup => 'D',
    StatKind.beat => 'Got beat',
    _ => kind.name,
  };

  /// Takes back the last change: an armed action first, then changes made
  /// on this screen exactly as they were, then (for older changes) the last
  /// action, reopening the previous point when needed.
  void undo() {
    if (!canUndo) return;
    if (_armed != null) {
      _armed = null;
      notifyListeners();
      return;
    }
    if (_history.isNotEmpty) {
      final step = _history.removeLast();
      _sideOverride = step.sideOverride;
      _commit(step.before);
      return;
    }
    final point = points.last;
    if (point.result != null) {
      if (point.line.isEmpty && point.actions.isEmpty) {
        // Score-only point: remove it entirely.
        _setPoints(points.take(points.length - 1).toList());
        return;
      }
      // Reopen the point; our goal is taken back off, leaving the thrower
      // holding the disc.
      final actions = [...point.actions];
      if (point.result == PointResult.weScored &&
          actions.lastOrNull?.kind == StatKind.goal) {
        actions.removeLast();
      }
      _replaceCurrent(point.copyWith(actions: actions, result: () => null));
    } else if (point.actions.isNotEmpty) {
      _replaceCurrent(
        point.copyWith(
          actions: point.actions.take(point.actions.length - 1).toList(),
        ),
      );
    } else {
      _setPoints(points.take(points.length - 1).toList());
    }
  }

  // ---- Readouts ------------------------------------------------------------------

  StatSheet get sheet => StatSheet.fromPoints(points);

  /// Plain-language description for the point log; the log adds a label
  /// for the kind of play.
  String describe(StatAction a) => switch (a.kind) {
    StatKind.pull => [
      '${nameOf(a.playerId)} pulls',
      if (a.hangTimeMs case final ms?)
        '${(ms / 1000).toStringAsFixed(1)}s hang',
      if (a.outOfBounds) 'out of bounds',
    ].join(' · '),
    StatKind.pickup => '${nameOf(a.playerId)} picks it up',
    StatKind.catch_ => '${nameOf(a.throwerId)} → ${nameOf(a.playerId)}',
    StatKind.goal =>
      '${nameOf(a.throwerId)} → ${nameOf(a.playerId)} in the endzone',
    StatKind.throwaway => '${nameOf(a.playerId)} throws it away',
    StatKind.drop =>
      a.throwerId == null
          ? '${nameOf(a.playerId)} drops it'
          : '${nameOf(a.playerId)} drops it from ${nameOf(a.throwerId)}',
    StatKind.handBlock => '${nameOf(a.playerId)} blocks it at the mark',
    StatKind.breakup => '${nameOf(a.playerId)} breaks up the pass',
    StatKind.beat => '${nameOf(a.playerId)} got beat',
    StatKind.theirTurnover => 'They turn it over',
    StatKind.sub => '${nameOf(a.playerId)} in for ${nameOf(a.subOutId)}',
  };

  // ---- Internals -----------------------------------------------------------------

  void _record(StatAction a) {
    final point = currentPoint;
    if (point == null) return;
    _replaceCurrent(
      point.copyWith(actions: [...point.actions, a]),
      undo: describe(a),
    );
  }

  void _replaceCurrent(StatPoint p, {String? undo}) =>
      _setPoints([...points.take(points.length - 1), p], undo: undo);

  void _setPoints(List<StatPoint> pts, {String? undo}) {
    final g = _game;
    if (g == null) return;
    _commit(g.copyWith(points: pts), undo: undo);
  }

  /// Saves [g]. With an [undo] label, the game as it was goes on the undo
  /// history.
  void _commit(StatsGame g, {String? undo}) {
    if (!canEdit) return;
    if (undo != null && _game != null) {
      _history.add((before: _game!, label: undo, sideOverride: _sideOverride));
      if (_history.length > _maxHistory) _history.removeAt(0);
    }
    _game = g;
    notifyListeners();
    unawaited(_stats.saveGame(teamId, g).then(_saved));
  }

  void _saved(Result<Object?> r) {
    final error = switch (r) {
      Ok() => null,
      Error(:final error) => error,
    };
    if (error == _saveError) return;
    _saveError = error;
    notifyListeners();
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
