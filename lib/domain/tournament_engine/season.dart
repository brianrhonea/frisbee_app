part of 'generator.dart';

/// The schedule for a hosted tournament's [division]: a league's weekly
/// season when [t] is a league with a season, otherwise the usual
/// tournament schedule. [seeds] are the accepted teams in seed order.
SchedulePlan planFor(
  HostedTournament t,
  TournamentDivision division,
  List<String> seeds,
) {
  final season = t.season;
  return t.isLeague && season != null
      ? seasonFor(seeds, division.settings, season)
      : scheduleFor(seeds, division.settings);
}

/// Each night of [season]: [TournamentSettings.startsAt] and every seven
/// days after it, leaving out [LeagueSeason.skipDates], until the season
/// has [LeagueSeason.weeks] nights.
List<DateTime> seasonNights(TournamentSettings s, LeagueSeason season) {
  int dayKey(DateTime d) => d.year * 10000 + d.month * 100 + d.day;
  final skip = {for (final d in season.skipDates) dayKey(d)};
  final first = s.startsAt;
  final nights = <DateTime>[];
  for (var week = 0; nights.length < season.weeks; week++) {
    // Built from the calendar date so a clock change doesn't shift the hour.
    final night = DateTime(
      first.year,
      first.month,
      first.day + 7 * week,
      first.hour,
      first.minute,
    );
    if (!skip.contains(dayKey(night))) nights.add(night);
  }
  return nights;
}

/// A league's season for [teams] (in seed order): a round robin spread
/// over the regular-season nights, then single-elimination playoffs for
/// the top [LeagueSeason.playoffTeams] over the last
/// [LeagueSeason.playoffWeeks] nights.
///
/// Regular-season games are pool games in pool "A" (round = week, so
/// standings and playoff seeding work as for a tournament's pool play);
/// playoff slots are filled from those standings by `bracketSeeds`. With
/// an odd number of teams one sits out each week (see [byesIn]); if the
/// season has more weeks than the round robin has rounds, the rounds
/// repeat, and if fewer, the season ends before everyone has met.
SchedulePlan seasonFor(
  List<String> teams,
  TournamentSettings s,
  LeagueSeason season,
) {
  if (teams.length < 2) {
    throw const ScheduleException('A league needs at least two teams.');
  }
  final regularWeeks = season.regularWeeks;
  if (regularWeeks < 1) {
    throw const ScheduleException(
      'Leave at least one week for the regular season.',
    );
  }
  final nights = seasonNights(s, season);
  final b = _Builder();

  // Which night (0-based) each game is on.
  final nightOf = <String, int>{};

  final rounds = roundRobin(teams);
  var next = 0;
  for (var w = 0; w < regularWeeks; w++) {
    for (var g = 0; g < season.gamesPerNight; g++) {
      for (final (a, c) in rounds[next % rounds.length]) {
        final id = b.add(
          stage: GameStage.pool,
          round: w + 1,
          label: 'Week ${w + 1}',
          poolId: 'A',
          a: _Entrant.team(a),
          c: _Entrant.team(c),
        );
        nightOf[id] = w;
      }
      next++;
    }
  }

  if (season.hasPlayoffs) {
    final size = min(season.playoffTeams, teams.length);
    final before = b.games.length;
    _singleElim(b, [
      for (var rank = 1; rank <= size; rank++)
        _Entrant.source(PoolRank('A', rank)),
    ]);
    final bracket = b.games.sublist(before);
    final bracketRounds = bracket.map((g) => g.round).fold(0, max);
    final weeks = season.playoffWeeks;
    for (final g in bracket) {
      // The final lands on the season's last night. With fewer weeks than
      // rounds, early rounds share a night.
      final night = weeks >= bracketRounds
          ? weeks - bracketRounds + g.round - 1
          : (g.round - 1) * weeks ~/ bracketRounds;
      nightOf[g.id] = regularWeeks + night;
    }
  }

  final fields = max(1, s.fields);
  final slotLength = Duration(minutes: s.gameMinutes + s.breakMinutes);
  final scheduled = <GroupGame>[];
  final days = <ScheduleDay>[];
  final earlier = <String>{};
  for (var n = 0; n < nights.length; n++) {
    final pending = [
      for (final g in b.games)
        if (nightOf[g.id] == n) g,
    ];
    if (pending.isEmpty) continue;
    final slotOf = <String, int>{};
    var slot = 0;
    var last = -1;
    while (pending.isNotEmpty) {
      final busy = <String>{};
      var used = 0;
      for (final g in [...pending]) {
        if (used == fields) break;
        // A bracket game waits for the games its teams come from.
        final ready = [g.sourceA, g.sourceB].every(
          (src) => switch (src) {
            WinnerOf(:final gameId) || LoserOf(:final gameId) =>
              earlier.contains(gameId) || (slotOf[gameId] ?? slot) < slot,
            _ => true,
          },
        );
        final playing = [?g.teamA, ?g.teamB];
        if (!ready || playing.any(busy.contains)) continue;
        busy.addAll(playing);
        slotOf[g.id] = slot;
        pending.remove(g);
        used++;
        last = slot;
        scheduled.add(
          g.copyWith(
            order: scheduled.length,
            field: used,
            startsAt: nights[n].add(slotLength * slot),
          ),
        );
      }
      slot++;
      if (slot > b.games.length * 2 + 2) {
        throw const ScheduleException("These games can't be scheduled.");
      }
    }
    earlier.addAll(slotOf.keys);
    days.add(
      ScheduleDay(
        startsAt: nights[n],
        endsAt: nights[n].add(
          slotLength * last + Duration(minutes: s.gameMinutes),
        ),
        games: slotOf.length,
      ),
    );
  }
  return SchedulePlan(games: scheduled, days: days);
}

/// The teams in [teams] with no pool game in [week] (1-based): the bye.
List<String> byesIn(List<String> teams, Iterable<GroupGame> games, int week) {
  final playing = {
    for (final g in games)
      if (g.stage == GameStage.pool && g.round == week) ...[?g.teamA, ?g.teamB],
  };
  return [
    for (final t in teams)
      if (!playing.contains(t)) t,
  ];
}
