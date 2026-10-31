import 'model_utils.dart';

/// Which side of the disc we're on.
enum Side {
  offense('O'),
  defense('D');

  const Side(this.short);
  final String short;

  Side get flipped => this == offense ? defense : offense;
}

enum StatKind {
  /// Our pull to start a D point; records hang time and out of bounds.
  pull,

  /// Picked the disc up after a turnover or pull. A touch, not a catch.
  pickup,

  /// Completed pass; [StatAction.throwerId] threw it.
  catch_,

  /// Caught in the endzone; the thrower gets the assist. Ends the point.
  goal,

  /// Holder threw it away.
  throwaway,

  /// Receiver dropped a catchable pass from [StatAction.throwerId].
  drop,
  handBlock,

  /// A "D": pass broken up.
  breakup,

  /// Defender's mark got open for a completion or score.
  beat,

  /// Opponent turned it over without a block (to us on O).
  theirTurnover,

  /// [StatAction.playerId] came on for [StatAction.subOutId] mid-point.
  sub,
}

/// One tracked event within a point.
class StatAction {
  const StatAction(
    this.kind, {
    this.playerId,
    this.throwerId,
    this.subOutId,
    this.hangTimeMs,
    this.outOfBounds = false,
  });

  final StatKind kind;
  final String? playerId;
  final String? throwerId;
  final String? subOutId;

  /// Pull hang time.
  final int? hangTimeMs;

  /// Pull landed out of bounds.
  final bool outOfBounds;

  factory StatAction.fromMap(Map<String, dynamic> m) => StatAction(
    enumByName(StatKind.values, m['kind'], StatKind.catch_),
    playerId: m['playerId'] as String?,
    throwerId: m['throwerId'] as String?,
    subOutId: m['subOutId'] as String?,
    hangTimeMs: (m['hangTimeMs'] as num?)?.toInt(),
    outOfBounds: m['outOfBounds'] as bool? ?? false,
  );

  Map<String, dynamic> toMap() => {
    'kind': kind.name,
    'playerId': ?playerId,
    'throwerId': ?throwerId,
    'subOutId': ?subOutId,
    'hangTimeMs': ?hangTimeMs,
    if (outOfBounds) 'outOfBounds': true,
  };

  /// Whether this action hands possession to the other team.
  bool get turnsOver => switch (kind) {
    StatKind.throwaway || StatKind.drop => true,
    StatKind.handBlock || StatKind.breakup || StatKind.theirTurnover => true,
    _ => false,
  };
}

enum PointResult { weScored, theyScored }

/// A named set of seven players, e.g. "O-line".
class StatLine {
  const StatLine({
    required this.id,
    required this.name,
    required this.players,
    this.side,
  });

  static const size = 7;

  final String id;
  final String name;
  final List<String> players;

  /// What the line is built for; null for either.
  final Side? side;

  factory StatLine.fromMap(Map<String, dynamic> m) => StatLine(
    id: m['id'] as String? ?? '',
    name: m['name'] as String? ?? '',
    players: [for (final p in m['players'] as List? ?? const []) '$p'],
    side: switch (m['side']) {
      final String name => enumByName(Side.values, name, Side.offense),
      _ => null,
    },
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'players': players,
    'side': side?.name,
  };

  /// Same name, side and players, in any order.
  String get key => '$name|${side?.name}|${([...players]..sort()).join(',')}';
}

class StatPoint {
  const StatPoint({
    required this.line,
    required this.startedOn,
    this.actions = const [],
    this.result,
  });

  /// Roster ids of the seven players who started the point. Empty for a
  /// point recorded only as an opponent score.
  final List<String> line;
  final Side startedOn;
  final List<StatAction> actions;

  /// Null while the point is being played.
  final PointResult? result;

  factory StatPoint.fromMap(Map<String, dynamic> m) => StatPoint(
    line: [for (final p in m['line'] as List? ?? const []) '$p'],
    startedOn: enumByName(Side.values, m['startedOn'], Side.offense),
    actions: [
      for (final a in m['actions'] as List? ?? const [])
        StatAction.fromMap(Map<String, dynamic>.from(a as Map)),
    ],
    result: switch (m['result']) {
      final String name => enumByName(
        PointResult.values,
        name,
        PointResult.weScored,
      ),
      _ => null,
    },
  );

  Map<String, dynamic> toMap() => {
    'line': line,
    'startedOn': startedOn.name,
    'actions': [for (final a in actions) a.toMap()],
    'result': result?.name,
  };

  /// Who's on the field now, after substitutions.
  List<String> get onField {
    final field = [...line];
    for (final a in actions) {
      if (a.kind != StatKind.sub) continue;
      final i = field.indexOf(a.subOutId ?? '');
      if (i >= 0 && a.playerId != null) field[i] = a.playerId!;
    }
    return field;
  }

  /// Everyone who played any part of the point.
  Set<String> get played => {
    ...line,
    for (final a in actions)
      if (a.kind == StatKind.sub && a.playerId != null) a.playerId!,
  };

  /// Side we're on after replaying [actions].
  Side get side {
    var s = startedOn;
    for (final a in actions) {
      if (a.turnsOver) s = s.flipped;
    }
    return s;
  }

  /// Player holding the disc, if we're on O and someone has it.
  String? get holder {
    String? h;
    for (final a in actions) {
      h = switch (a.kind) {
        StatKind.pickup || StatKind.catch_ || StatKind.goal => a.playerId,
        // An injured holder subs out; the sub takes the disc, no catch.
        StatKind.sub when h != null && a.subOutId == h => a.playerId,
        _ when a.turnsOver => null,
        _ => h,
      };
    }
    return h;
  }

  bool get hasPull => actions.any((a) => a.kind == StatKind.pull);

  StatPoint copyWith({
    List<StatAction>? actions,
    PointResult? Function()? result,
  }) => StatPoint(
    line: line,
    startedOn: startedOn,
    actions: actions ?? this.actions,
    result: result != null ? result() : this.result,
  );
}

List<StatLine> _lines(Object? raw) => [
  for (final l in raw as List? ?? const [])
    StatLine.fromMap(Map<String, dynamic>.from(l as Map)),
];

/// A timeout called by us or them.
class GameTimeout {
  const GameTimeout({
    required this.ours,
    required this.half,
    required this.point,
    this.action = 0,
  });

  final bool ours;

  /// 1 or 2.
  final int half;

  /// Index of the point it was called during, or before if none was in
  /// play.
  final int point;

  /// How many of that point's actions came before it.
  final int action;

  factory GameTimeout.fromMap(Map<String, dynamic> m) => GameTimeout(
    ours: m['ours'] as bool? ?? true,
    half: (m['half'] as num?)?.toInt() ?? 1,
    point: (m['point'] as num?)?.toInt() ?? 0,
    action: (m['action'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toMap() => {
    'ours': ours,
    'half': half,
    'point': point,
    'action': action,
  };
}

class StatsGame {
  const StatsGame({
    required this.id,
    required this.opponent,
    required this.date,
    this.gameTo = 15,
    this.tournamentId,
    this.eventId,
    this.points = const [],
    this.finished = false,
    this.lines = const [],
    this.timeoutsPerHalf = 2,
    this.timeouts = const [],
  });

  /// Common "game to" targets.
  static const targets = [7, 11, 13, 15, 17, 21];

  /// Timeout allowances to choose from.
  static const timeoutChoices = [0, 1, 2, 3, 4];

  final String id;
  final String opponent;
  final DateTime date;

  /// Score that wins the game.
  final int gameTo;

  /// Folder this game lives in; null for a standalone game.
  final String? tournamentId;

  /// Linked schedule event, if any.
  final String? eventId;
  final List<StatPoint> points;

  /// Ended by hand, e.g. at a time cap.
  final bool finished;

  /// Lines built for a standalone game. Games in a tournament use the
  /// tournament's lines instead.
  final List<StatLine> lines;

  /// Timeouts each team gets per half.
  final int timeoutsPerHalf;
  final List<GameTimeout> timeouts;

  factory StatsGame.fromMap(String id, Map<String, dynamic> m) => StatsGame(
    id: id,
    opponent: m['opponent'] as String? ?? '',
    date: parseDate(m['date']) ?? DateTime.now(),
    gameTo: (m['gameTo'] as num?)?.toInt() ?? 15,
    tournamentId: m['tournamentId'] as String?,
    eventId: m['eventId'] as String?,
    points: [
      for (final p in m['points'] as List? ?? const [])
        StatPoint.fromMap(Map<String, dynamic>.from(p as Map)),
    ],
    finished: m['finished'] as bool? ?? false,
    lines: _lines(m['lines']),
    timeoutsPerHalf: (m['timeoutsPerHalf'] as num?)?.toInt() ?? 2,
    timeouts: [
      for (final t in m['timeouts'] as List? ?? const [])
        GameTimeout.fromMap(Map<String, dynamic>.from(t as Map)),
    ],
  );

  /// Everything but the id, which is the document id.
  Map<String, dynamic> toMap() => {
    'opponent': opponent,
    'date': date,
    'gameTo': gameTo,
    'tournamentId': tournamentId,
    'eventId': eventId,
    'points': [for (final p in points) p.toMap()],
    'finished': finished,
    'lines': [for (final l in lines) l.toMap()],
    'timeoutsPerHalf': timeoutsPerHalf,
    'timeouts': [for (final t in timeouts) t.toMap()],
  };

  int get ourScore =>
      points.where((p) => p.result == PointResult.weScored).length;
  int get theirScore =>
      points.where((p) => p.result == PointResult.theyScored).length;

  /// Someone reached [gameTo].
  bool get reachedGamePoint => ourScore >= gameTo || theirScore >= gameTo;

  /// No more stats can be recorded.
  bool get over => finished || reachedGamePoint;

  /// Halftime comes when either team reaches this score, e.g. 8 in a
  /// game to 15.
  int get halfAt => (gameTo + 1) ~/ 2;

  /// Index of the point that took the game to halftime, if played.
  int? get halftimePoint {
    var us = 0, them = 0;
    for (final (i, p) in points.indexed) {
      if (p.result == PointResult.weScored) us++;
      if (p.result == PointResult.theyScored) them++;
      if (us >= halfAt || them >= halfAt) return i;
    }
    return null;
  }

  /// Half being played now.
  int get half => halftimePoint == null ? 1 : 2;

  /// Timeouts [ours] (or theirs) has left this half.
  int timeoutsLeft({required bool ours}) {
    final used = timeouts.where((t) => t.ours == ours && t.half == half);
    return (timeoutsPerHalf - used.length).clamp(0, timeoutsPerHalf);
  }

  /// Null while in play or tied.
  bool? get won =>
      !over || ourScore == theirScore ? null : ourScore > theirScore;

  StatsGame copyWith({
    List<StatPoint>? points,
    bool? finished,
    int? gameTo,
    List<StatLine>? lines,
    int? timeoutsPerHalf,
    List<GameTimeout>? timeouts,
  }) => StatsGame(
    id: id,
    opponent: opponent,
    date: date,
    gameTo: gameTo ?? this.gameTo,
    tournamentId: tournamentId,
    eventId: eventId,
    points: points ?? this.points,
    finished: finished ?? this.finished,
    lines: lines ?? this.lines,
    timeoutsPerHalf: timeoutsPerHalf ?? this.timeoutsPerHalf,
    timeouts: timeouts ?? this.timeouts,
  );
}

/// Where saved lines can be imported from: a tournament or a game.
class LineSource {
  const LineSource({
    required this.id,
    required this.name,
    required this.lines,
    this.eventId,
  });

  final String id;
  final String name;
  final List<StatLine> lines;
  final String? eventId;

  /// Every tournament and game with lines, newest first. Tournaments use
  /// their lines; games in a tournament share them, so only standalone
  /// games count.
  static List<LineSource> from(
    Iterable<StatsTournament> tournaments,
    Iterable<StatsGame> games,
  ) {
    final dated = [
      for (final t in tournaments)
        if (t.lines.isNotEmpty)
          (
            t.startDate,
            LineSource(
              id: t.id,
              name: t.name,
              lines: t.lines,
              eventId: t.eventId,
            ),
          ),
      for (final g in games)
        if (g.tournamentId == null && g.lines.isNotEmpty)
          (
            g.date,
            LineSource(
              id: g.id,
              name: 'vs ${g.opponent}',
              lines: g.lines,
              eventId: g.eventId,
            ),
          ),
    ]..sort((a, b) => b.$1.compareTo(a.$1));
    return [for (final (_, s) in dated) s];
  }

  /// Lines already built for [eventId], e.g. an earlier scrimmage at the
  /// same practice, without duplicates.
  static List<StatLine> forEvent(String? eventId, List<LineSource> sources) {
    if (eventId == null) return const [];
    final seen = <String>{};
    return [
      for (final s in sources)
        if (s.eventId == eventId)
          for (final l in s.lines)
            if (seen.add(l.key)) l,
    ];
  }
}

/// A tournament folder: who's attending and the lines built for it.
class StatsTournament {
  const StatsTournament({
    required this.id,
    required this.name,
    required this.startDate,
    this.location = '',
    this.eventId,
    this.roster = const [],
    this.lines = const [],
  });

  final String id;
  final String name;
  final DateTime startDate;
  final String location;
  final String? eventId;

  /// Roster ids attending this tournament.
  final List<String> roster;
  final List<StatLine> lines;

  factory StatsTournament.fromMap(String id, Map<String, dynamic> m) =>
      StatsTournament(
        id: id,
        name: m['name'] as String? ?? '',
        startDate: parseDate(m['startDate']) ?? DateTime.now(),
        location: m['location'] as String? ?? '',
        eventId: m['eventId'] as String?,
        roster: [for (final p in m['roster'] as List? ?? const []) '$p'],
        lines: _lines(m['lines']),
      );

  /// Everything but the id, which is the document id.
  Map<String, dynamic> toMap() => {
    'name': name,
    'startDate': startDate,
    'location': location,
    'eventId': eventId,
    'roster': roster,
    'lines': [for (final l in lines) l.toMap()],
  };

  StatsTournament copyWith({List<String>? roster, List<StatLine>? lines}) =>
      StatsTournament(
        id: id,
        name: name,
        startDate: startDate,
        location: location,
        eventId: eventId,
        roster: roster ?? this.roster,
        lines: lines ?? this.lines,
      );
}

/// Running totals for one player.
class PlayerStats {
  PlayerStats(this.playerId);

  final String playerId;
  int pointsO = 0;
  int pointsD = 0;
  int pickups = 0;
  int catches = 0;
  int goals = 0;
  int assists = 0;
  int completions = 0;
  int throwaways = 0;
  int drops = 0;
  int handBlocks = 0;
  int breakups = 0;
  int beats = 0;
  int pulls = 0;
  int pullsOutOfBounds = 0;
  int _timedPulls = 0;
  int _hangTimeMs = 0;

  /// Finished O points played, and how many we scored (held).
  int finishedO = 0;
  int holds = 0;

  /// Finished D points played, and how many we scored (broke).
  int finishedD = 0;
  int breaks = 0;

  double _oCredit = 0;
  double _dCredit = 0;

  int get pointsPlayed => pointsO + pointsD;

  /// Share of the player's O points we scored. Null with none finished.
  double? get oEfficiency => finishedO == 0 ? null : holds / finishedO;

  /// Share of the player's D points we broke. Null with none finished.
  double? get dEfficiency => finishedD == 0 ? null : breaks / finishedD;

  /// Average [Involvement.credit] per finished O point. 1.0 means on the
  /// field for a hold every point without touching the disc; goals,
  /// assists, touches and blocks push it higher.
  double? get oRating => finishedO == 0 ? null : _oCredit / finishedO;

  /// Average [Involvement.credit] per finished D point.
  double? get dRating => finishedD == 0 ? null : _dCredit / finishedD;

  /// Every time the player had the disc.
  int get touches => pickups + catches + goals;

  int get throws => completions + throwaways;

  /// Catches (goals included) over catchable passes. Null with no targets.
  double? get catchPct {
    final caught = catches + goals;
    final targets = caught + drops;
    return targets == 0 ? null : caught / targets;
  }

  double? get completionPct => throws == 0 ? null : completions / throws;

  /// Average pull hang time in seconds. Null with no timed pulls.
  double? get avgHangTime =>
      _timedPulls == 0 ? null : _hangTimeMs / _timedPulls / 1000;

  /// Score: goal and assist +1, hand block +2, breakup +1, and -1 each for
  /// a throwaway, drop or getting beat. Pulls don't count.
  int get plusMinus =>
      goals + assists + 2 * handBlocks + breakups - throwaways - drops - beats;
}

/// What one player did in one point, for the O and D ratings.
class Involvement {
  int goals = 0;
  int assists = 0;
  int touches = 0;
  int handBlocks = 0;
  int breakups = 0;
  int throwaways = 0;
  int drops = 0;

  static const scoredCredit = 1.0;
  static const goalBonus = 0.5;
  static const assistBonus = 0.5;
  static const touchBonus = 0.1;
  static const handBlockBonus = 1.0;
  static const breakupBonus = 0.5;

  /// Costs a little more than a goal or assist earns.
  static const turnoverPenalty = 0.75;

  /// If we scored: 1, plus 0.5 per goal or assist, 0.1 per touch, 1 per
  /// hand block and 0.5 per breakup. If we didn't, nothing. Either way,
  /// each throwaway or drop costs 0.75, so a turnover on a point we lose
  /// goes negative.
  double credit({required bool scored}) {
    final penalty = (throwaways + drops) * turnoverPenalty;
    if (!scored) return -penalty;
    return scoredCredit +
        goals * goalBonus +
        assists * assistBonus +
        touches * touchBonus +
        handBlocks * handBlockBonus +
        breakups * breakupBonus -
        penalty;
  }
}

/// Team O and D efficiency over finished points.
class TeamEfficiency {
  int oPoints = 0;
  int holds = 0;
  int dPoints = 0;
  int breaks = 0;

  double? get oEfficiency => oPoints == 0 ? null : holds / oPoints;
  double? get breakRate => dPoints == 0 ? null : breaks / dPoints;
}

/// Per-player stats computed from tracked points.
class StatSheet {
  StatSheet._(this.players, this.team);

  /// Player id → stats, for everyone who played or recorded a stat.
  final Map<String, PlayerStats> players;
  final TeamEfficiency team;

  factory StatSheet.fromPoints(Iterable<StatPoint> points) {
    final m = <String, PlayerStats>{};
    final team = TeamEfficiency();
    PlayerStats p(String id) => m[id] ??= PlayerStats(id);
    for (final point in points) {
      final onO = point.startedOn == Side.offense;
      for (final id in point.played) {
        onO ? p(id).pointsO++ : p(id).pointsD++;
      }
      final inv = <String, Involvement>{};
      Involvement i(String id) => inv[id] ??= Involvement();
      for (final a in point.actions) {
        if (a.playerId case final id?) {
          switch (a.kind) {
            case StatKind.pickup || StatKind.catch_:
              i(id).touches++;
            case StatKind.goal:
              i(id)
                ..touches += 1
                ..goals += 1;
              if (a.throwerId case final t?) i(t).assists++;
            case StatKind.handBlock:
              i(id).handBlocks++;
            case StatKind.breakup:
              i(id).breakups++;
            case StatKind.throwaway:
              i(id).throwaways++;
            case StatKind.drop:
              i(id).drops++;
            default:
              break;
          }
        }
      }
      if (point.result case final result?) {
        final scored = result == PointResult.weScored;
        if (onO) {
          team.oPoints++;
          if (scored) team.holds++;
        } else {
          team.dPoints++;
          if (scored) team.breaks++;
        }
        for (final id in point.played) {
          final s = p(id);
          final credit = (inv[id] ?? Involvement()).credit(scored: scored);
          if (onO) {
            s.finishedO++;
            if (scored) s.holds++;
            s._oCredit += credit;
          } else {
            s.finishedD++;
            if (scored) s.breaks++;
            s._dCredit += credit;
          }
        }
      }
      for (final a in point.actions) {
        final id = a.playerId;
        final thrower = a.throwerId;
        switch (a.kind) {
          case StatKind.pull:
            if (id == null) break;
            final s = p(id);
            s.pulls++;
            if (a.outOfBounds) s.pullsOutOfBounds++;
            if (a.hangTimeMs case final ms?) {
              s._timedPulls++;
              s._hangTimeMs += ms;
            }
          case StatKind.pickup:
            if (id != null) p(id).pickups++;
          case StatKind.catch_:
            if (id != null) p(id).catches++;
            if (thrower != null) p(thrower).completions++;
          case StatKind.goal:
            if (id != null) p(id).goals++;
            if (thrower != null) {
              final t = p(thrower);
              t.assists++;
              t.completions++;
            }
          case StatKind.throwaway:
            if (id != null) p(id).throwaways++;
          case StatKind.drop:
            // The throw was on target, so the thrower isn't charged.
            if (id != null) p(id).drops++;
            if (thrower != null) p(thrower).completions++;
          case StatKind.handBlock:
            if (id != null) p(id).handBlocks++;
          case StatKind.breakup:
            if (id != null) p(id).breakups++;
          case StatKind.beat:
            if (id != null) p(id).beats++;
          case StatKind.theirTurnover || StatKind.sub:
            break;
        }
      }
    }
    return StatSheet._(m, team);
  }

  factory StatSheet.fromGames(Iterable<StatsGame> games) =>
      StatSheet.fromPoints(games.expand((g) => g.points));

  /// Highest +/- first.
  List<PlayerStats> get ranked =>
      players.values.toList()
        ..sort((a, b) => b.plusMinus.compareTo(a.plusMinus));
}
