import '../models/group_tournament.dart';

/// One night of a league's schedule (F30), for the Schedule tab's
/// "‹ Week N ›" stepper. Mirrors `leagueWeeks` in
/// `packages/shared/src/league_weeks.ts`; both are tested against the
/// same cases.
///
/// Weeks are game nights, not rounds: with two games a night a night has
/// two rounds, and a skipped week has no night at all.
class LeagueWeek {
  const LeagueWeek({
    required this.day,
    required this.number,
    required this.playoffs,
    required this.games,
  });

  /// The night (midnight), or null for games with no start yet.
  final DateTime? day;

  /// 1 for the first night.
  final int number;

  /// Every game that night is a playoff (bracket) game.
  final bool playoffs;

  /// In schedule order.
  final List<GroupGame> games;

  /// "Week 3", "Week 9 · Playoffs", or "Not scheduled yet".
  String get label => labelOf();

  /// [label], with [total] (the season's nights) "Week 3 of 8".
  String labelOf([int? total]) {
    if (day == null) return 'Not scheduled yet';
    final week = total == null ? 'Week $number' : 'Week $number of $total';
    return playoffs ? '$week · Playoffs' : week;
  }
}

/// [games] (in schedule order) by night, in local time. Games with no
/// start come last, as one more week.
List<LeagueWeek> leagueWeeks(List<GroupGame> games) {
  final byDay = <DateTime?, List<GroupGame>>{};
  for (final g in games) {
    final at = g.startsAt;
    final key = at == null ? null : DateTime(at.year, at.month, at.day);
    byDay.putIfAbsent(key, () => []).add(g);
  }
  final keys = byDay.keys.toList()
    ..sort((a, b) {
      if (a == null) return b == null ? 0 : 1;
      if (b == null) return -1;
      return a.compareTo(b);
    });
  return [
    for (final (i, k) in keys.indexed)
      LeagueWeek(
        day: k,
        number: i + 1,
        playoffs: byDay[k]!.every((g) => g.stage.isBracket),
        games: byDay[k]!,
      ),
  ];
}

/// How many nights [weeks] has (games with no start yet aren't one).
int leagueNights(List<LeagueWeek> weeks) =>
    weeks.where((w) => w.day != null).length;

/// The week the schedule opens on: the first night on or after [today],
/// so tonight's games during game night and next week's after it; once
/// the season is over, its last night.
int currentWeekIndex(List<LeagueWeek> weeks, DateTime today) {
  final day = DateTime(today.year, today.month, today.day);
  final next = weeks.indexWhere((w) => w.day != null && !w.day!.isBefore(day));
  if (next >= 0) return next;
  final dated = weeks.lastIndexWhere((w) => w.day != null);
  return dated >= 0 ? dated : 0;
}
