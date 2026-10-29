import 'dart:math' as math;

/// One division's schedule link on a USA Ultimate event page, e.g. the
/// "Club" button under "Men's Division Schedule".
class UsauDivision {
  const UsauDivision({required this.label, this.level = ''});

  /// "Men", "Mixed", "Women", ...
  final String label;

  /// Competition level, e.g. "Club" or "College". May be blank.
  final String level;

  /// "Club Men", or just [label] without a level.
  String get title => [level, label].where((s) => s.isNotEmpty).join(' ');

  @override
  bool operator ==(Object other) =>
      other is UsauDivision && other.label == label && other.level == level;

  @override
  int get hashCode => Object.hash(label, level);
}

/// A division's schedule page: pool play, crossovers and brackets, grouped
/// into the stages shown as tabs on USA Ultimate.
class UsauDivisionSchedule {
  const UsauDivisionSchedule({
    required this.title,
    required this.url,
    this.stages = const [],
  });

  /// As printed, e.g. "Club - Men".
  final String title;
  final String url;
  final List<UsauStage> stages;
}

/// One tab of a division schedule, e.g. "Friday Pool Play" or
/// "2026 Men's Club Championship".
class UsauStage {
  const UsauStage({
    required this.title,
    this.pools = const [],
    this.gameLists = const [],
    this.brackets = const [],
  });

  final String title;
  final List<UsauPool> pools;
  final List<UsauGameList> gameLists;
  final List<UsauBracket> brackets;

  bool get isEmpty => pools.isEmpty && gameLists.isEmpty && brackets.isEmpty;
}

/// A pool's standings table.
class UsauPool {
  const UsauPool({required this.name, this.teams = const []});

  final String name;

  /// In the order USA Ultimate lists them (current standing).
  final List<UsauPoolTeam> teams;
}

class UsauPoolTeam {
  const UsauPoolTeam({
    required this.name,
    this.seed,
    this.record = '',
    this.url = '',
  });

  final String name;
  final int? seed;

  /// Win-loss as printed, e.g. "3 - 0".
  final String record;

  /// The team's page for this event.
  final String url;
}

/// A table of games, e.g. "Pool A Schedule & Scores" or "Crossover".
class UsauGameList {
  const UsauGameList({required this.title, this.games = const []});

  final String title;
  final List<UsauScheduleGame> games;
}

/// A bracket, e.g. "Championship" or "Fifth Place Bracket".
class UsauBracket {
  const UsauBracket({required this.title, this.rounds = const []});

  final String title;

  /// In play order: the first round first, the final last.
  final List<UsauBracketRound> rounds;
}

class UsauBracketRound {
  const UsauBracketRound({required this.name, this.games = const []});

  /// e.g. "Quarterfinals".
  final String name;
  final List<UsauBracketGame> games;
}

/// A game from a pool or crossover table.
class UsauScheduleGame {
  const UsauScheduleGame({
    required this.home,
    required this.away,
    this.id = '',
    this.date = '',
    this.time = '',
    this.field = '',
    this.status = '',
  });

  final String id;

  /// As printed, e.g. "Fri 10/23".
  final String date;

  /// As printed, e.g. "9:00 AM".
  final String time;
  final String field;

  /// e.g. "Final", "In Progress", "Scheduled".
  final String status;
  final UsauGameSide home;
  final UsauGameSide away;
}

/// A game in a bracket. [slot] is its 1-based position in its round on
/// USA Ultimate's bracket, where round `n` before the final has `2^n` slots.
class UsauBracketGame extends UsauScheduleGame {
  const UsauBracketGame({
    required super.home,
    required super.away,
    super.id,
    super.date,
    super.time,
    super.field,
    super.status,
    this.label = '',
    this.slot,
    this.nextId = '',
  });

  /// e.g. "G1".
  final String label;
  final int? slot;

  /// [id] of the game the winner moves on to, if any.
  final String nextId;
}

/// One team's line in a game.
class UsauGameSide {
  const UsauGameSide({
    required this.name,
    this.seed,
    this.score = '',
    this.won = false,
    this.url = '',
  });

  /// Blank when the team isn't decided yet.
  final String name;
  final int? seed;

  /// As printed; blank for unplayed games.
  final String score;
  final bool won;
  final String url;
}

/// Splits "Ring of Fire (8)" into the team name and seed.
({String name, int? seed}) splitSeed(String text) {
  final m = RegExp(r'^(.*?)\s*\((\d+)\)$').firstMatch(text.trim());
  if (m == null) return (name: text.trim(), seed: null);
  return (name: m[1]!, seed: int.parse(m[2]!));
}

/// Where each game of a bracket goes when drawn as a tree.
class BracketLayout {
  const BracketLayout({
    required this.rows,
    required this.positions,
    required this.links,
  });

  /// Height of the tree, in game slots of the first round.
  final double rows;

  /// Each game's round (column) and vertical center, measured in first-round
  /// slots from the top (0.5 is the middle of the first slot).
  final Map<UsauBracketGame, ({int column, double center})> positions;

  /// Connector lines from a game to the game its winner plays next.
  final List<({UsauBracketGame from, UsauBracketGame to})> links;
}

/// Lays out [bracket] the way USA Ultimate draws it: the final is centered,
/// and a round `n` steps before the final is split into `2^n` slots, of
/// which each game takes the one given by its [UsauBracketGame.slot].
/// Games without a usable slot fill the free slots in order.
BracketLayout bracketLayout(UsauBracket bracket) {
  final rounds = bracket.rounds;
  if (rounds.every((r) => r.games.isEmpty)) {
    return const BracketLayout(rows: 0, positions: {}, links: []);
  }
  final last = rounds.length - 1;
  // Slots per round, widened if a round has more games than its binary
  // share (an irregular bracket).
  final slotCounts = [
    for (var c = 0; c <= last; c++)
      math.max(
        1 << (last - c),
        [
          rounds[c].games.length,
          for (final g in rounds[c].games) g.slot ?? 0,
        ].reduce(math.max),
      ),
  ];
  final rows = slotCounts.reduce(math.max);

  final positions = <UsauBracketGame, ({int column, double center})>{};
  for (var c = 0; c <= last; c++) {
    final count = slotCounts[c];
    final taken = <int>{
      for (final g in rounds[c].games)
        if (g.slot != null && g.slot! >= 1 && g.slot! <= count) g.slot!,
    };
    final used = <int>{};
    var free = 1;
    for (final g in rounds[c].games) {
      var slot = g.slot;
      if (slot == null || slot < 1 || slot > count || !used.add(slot)) {
        while (taken.contains(free) || used.contains(free)) {
          free++;
        }
        slot = free;
        used.add(slot);
      }
      positions[g] = (column: c, center: (slot - 0.5) * rows / count);
    }
  }

  // Trim slots no game uses (e.g. a play-in that only fills the bottom
  // half), keeping half a slot above and below the outermost games.
  final centers = positions.values.map((p) => p.center);
  final top = centers.reduce(math.min) - 0.5;
  final height = centers.reduce(math.max) + 0.5 - top;
  positions.updateAll((_, p) => (column: p.column, center: p.center - top));

  final byId = {
    for (final g in positions.keys)
      if (g.id.isNotEmpty) g.id: g,
  };
  final links = [
    for (final g in positions.keys)
      if (byId[g.nextId] case final next?) (from: g, to: next),
  ];
  return BracketLayout(rows: height, positions: positions, links: links);
}
