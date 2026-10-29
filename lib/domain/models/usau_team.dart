/// A team's public profile page on USA Ultimate: details, roster and games.
class UsauTeam {
  const UsauTeam({
    required this.name,
    required this.url,
    this.info = const [],
    this.roster = const [],
    this.games = const [],
    this.events = const [],
  });

  final String name;
  final String url;

  /// Labelled profile details, e.g. ("Competition Level", "Club"), in page
  /// order.
  final List<({String label, String value})> info;
  final List<UsauPlayer> roster;
  final List<UsauGame> games;

  /// Tournaments the team is registered for, from its events tab.
  final List<UsauEvent> events;

  int get wins => games.where((g) => g.result == GameResult.win).length;
  int get losses => games.where((g) => g.result == GameResult.loss).length;

  /// The event named [tournament], if the team's events list has it.
  UsauEvent? eventNamed(String tournament) =>
      events.where((e) => e.name == tournament).firstOrNull;

  /// Combines this page with another tab of the same team, keeping this
  /// page's values and adding anything new from [other].
  UsauTeam merge(UsauTeam other) {
    final labels = info.map((i) => i.label).toSet();
    final gameKeys = games.map((g) => g.key).toSet();
    final eventNames = events.map((e) => e.name).toSet();
    return UsauTeam(
      name: name.isNotEmpty ? name : other.name,
      url: url,
      info: [...info, ...other.info.where((i) => labels.add(i.label))],
      roster: roster.isNotEmpty ? roster : other.roster,
      games: [...games, ...other.games.where((g) => gameKeys.add(g.key))],
      events: [...events, ...other.events.where((e) => eventNames.add(e.name))],
    );
  }
}

/// A tournament on a team's events tab.
class UsauEvent {
  const UsauEvent({
    required this.name,
    this.url = '',
    this.dates = '',
    this.startDate,
    this.endDate,
    this.location = '',
    this.placement = '',
  });

  final String name;
  final String url;

  /// Dates as printed, e.g. "Nov 07, 2026 - Nov 08, 2026".
  final String dates;
  final DateTime? startDate;
  final DateTime? endDate;
  final String location;

  /// Final standing as printed, e.g. "1st" or "5". Blank until it's played.
  final String placement;

  /// True when the event hasn't finished as of [now]. Events without dates
  /// count as upcoming only if they have no placement yet.
  bool isUpcoming(DateTime now) {
    final last = endDate ?? startDate;
    if (last == null) return placement.isEmpty;
    // Dates are UTC noon on the event day; count the whole last day.
    return now.isBefore(last.add(const Duration(hours: 12)));
  }

  /// True when the team finished first.
  bool get won => RegExp(
    r'^(1|1st|first|champions?)$',
    caseSensitive: false,
  ).hasMatch(placement.trim());
}

class UsauPlayer {
  const UsauPlayer({
    required this.name,
    this.number = '',
    this.position = '',
    this.height = '',
    this.pronouns = '',
  });

  final String name;

  /// Jersey number as printed; may be blank or non-numeric (e.g. "00").
  final String number;
  final String position;
  final String height;
  final String pronouns;
}

/// [upcoming] means no score has been posted; [unknown] covers ties and
/// scores that can't be read.
enum GameResult { win, loss, upcoming, unknown }

class UsauGame {
  const UsauGame({
    required this.opponent,
    this.tournament = '',
    this.date = '',
    this.score = '',
    this.opponentUrl = '',
  });

  final String opponent;
  final String tournament;

  /// Date as printed on the page; USAU omits the year on schedules.
  final String date;

  /// This team's score first, e.g. "13-9". Blank for unplayed games.
  final String score;
  final String opponentUrl;

  /// Identifies the game when merging tabs that list it twice.
  String get key => '$tournament|$date|$opponent';

  GameResult get result {
    final m = RegExp(r'(\d+)\s*-\s*(\d+)').firstMatch(score);
    if (m == null) {
      if (RegExp(r'^\s*W\b', caseSensitive: false).hasMatch(score)) {
        return GameResult.win;
      }
      if (RegExp(r'^\s*L\b', caseSensitive: false).hasMatch(score)) {
        return GameResult.loss;
      }
      // Blank, "TBD", "vs", a start time, etc.
      return GameResult.upcoming;
    }
    final (us, them) = (int.parse(m[1]!), int.parse(m[2]!));
    if (us == them) return GameResult.unknown;
    return us > them ? GameResult.win : GameResult.loss;
  }
}
