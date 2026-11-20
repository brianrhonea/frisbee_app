import '../models/group_tournament.dart';
import '../models/hosted_tournament.dart';
import 'progress.dart';
import 'standings.dart';

/// When a team's tournament card shows.
enum TournamentDayPhase {
  /// The team plays (or played) today, or the event is live.
  today,

  /// The evening before the team's first game of the next day.
  tomorrow,
}

/// What a score needs from the team's captains.
enum ScoreDueKind {
  /// The game has started (or has no time) and nobody has reported it.
  report,

  /// The other team reported it; this team confirms.
  confirm,

  /// This team reported it; the other team hasn't confirmed yet.
  awaiting,
}

/// A team's game, from the team's side.
class TeamGame {
  const TeamGame({required this.game, required this.teamId});

  final GroupGame game;
  final String teamId;

  bool get _isA => game.teamA == teamId;

  /// The other team; null while its slot isn't filled yet.
  String? get opponent => _isA ? game.teamB : game.teamA;

  int? get scoreFor => _isA ? game.scoreA : game.scoreB;
  int? get scoreAgainst => _isA ? game.scoreB : game.scoreA;
  bool get won => game.isDone && game.winner == teamId;
}

/// A team's day at a tournament: its next game, its last result, its
/// record and pool place, and whether a score is due. The same rules as
/// tournamentDay in packages/shared/src/tournament_day.ts (vectors in
/// packages/shared/fixtures/tournament_day).
class TournamentDay {
  const TournamentDay({
    required this.phase,
    this.next,
    this.last,
    this.wins = 0,
    this.losses = 0,
    this.pool,
    this.poolPlace,
    this.poolSize,
    this.scoreDue,
    this.scoreDueKind,
    this.awaiting = false,
  });

  final TournamentDayPhase phase;

  /// With no [next] game yet, whether one of the bracket's empty slots
  /// comes from this team (its pool place, or the winner or loser of a game
  /// it played): its next game is still to be decided. False once it's
  /// out, when its games are done.

  /// The team's next game still to play, earliest first.
  final TeamGame? next;

  /// Its most recent final.
  final TeamGame? last;
  final int wins;
  final int losses;

  /// The pool it plays in, its place there (1 = top; null until it has a
  /// pool result, since before that it's only the seed) and the pool's
  /// size.
  final String? pool;
  final int? poolPlace;
  final int? poolSize;

  /// The earliest game whose score the team's captains act on.
  final GroupGame? scoreDue;
  final ScoreDueKind? scoreDueKind;
  final bool awaiting;

  /// The card for [teamId] on [games] at [now], or null when there's
  /// nothing to show: no game today, not live, and not the evening
  /// (17:00 on) before a game tomorrow. [live] is the event's status.
  static TournamentDay? of(
    List<GroupGame> games,
    String teamId, {
    required DateTime now,
    bool live = false,
  }) {
    bool mine(GroupGame g) => g.teamA == teamId || g.teamB == teamId;
    int byTime(GroupGame a, GroupGame b) {
      final x = a.startsAt;
      final y = b.startsAt;
      if (x != null && y != null && x != y) return x.compareTo(y);
      if ((x == null) != (y == null)) return x == null ? 1 : -1;
      return a.order.compareTo(b.order);
    }

    final toPlay = gamesToPlay(games).where(mine).toList()..sort(byTime);
    final done = games.where((g) => g.isDone && mine(g)).toList()..sort(byTime);
    final next = toPlay.firstOrNull;
    final last = done.lastOrNull;

    final today = DateTime(now.year, now.month, now.day);
    DateTime? dayOf(GroupGame? g) => switch (g?.startsAt) {
      final d? => DateTime(d.year, d.month, d.day),
      null => null,
    };
    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    final playsToday =
        dayOf(next) == today ||
        done.any((g) => dayOf(g) == today) ||
        toPlay.any((g) => dayOf(g) == today);
    final TournamentDayPhase phase;
    if (playsToday || (live && next != null)) {
      phase = TournamentDayPhase.today;
    } else if (dayOf(next) == tomorrow && now.hour >= 17) {
      phase = TournamentDayPhase.tomorrow;
    } else {
      return null;
    }

    var wins = 0;
    for (final g in done) {
      if (g.winner == teamId) wins++;
    }

    String? pool;
    int? place;
    int? rank;
    int? size;
    for (final MapEntry(key: id, value: teams) in poolTeams(games).entries) {
      if (!teams.contains(teamId)) continue;
      final rows = standings(
        teams,
        games.where((g) => g.stage == GameStage.pool && g.poolId == id),
      );
      pool = id;
      size = rows.length;
      rank = rows.indexWhere((s) => s.teamId == teamId) + 1;
      final played = done.any(
        (g) => g.stage == GameStage.pool && g.poolId == id,
      );
      if (played) place = rank;
      break;
    }

    GroupGame? due;
    ScoreDueKind? kind;
    for (final g in toPlay) {
      if (!g.hasTeams) continue;
      final r = g.report;
      if (g.status == GameStatus.reported && r != null) {
        due = g;
        kind = r.byTeamId == teamId
            ? ScoreDueKind.awaiting
            : ScoreDueKind.confirm;
        break;
      }
      final starts = g.startsAt;
      if (starts == null || !starts.isAfter(now)) {
        due = g;
        kind = ScoreDueKind.report;
        break;
      }
    }

    bool fromMe(SlotSource? s) => switch (s) {
      PoolRank(:final poolId, rank: final r) => poolId == pool && r == rank,
      WinnerOf(:final gameId) => done.any(
        (g) => g.id == gameId && g.winner == teamId,
      ),
      LoserOf(:final gameId) => done.any(
        (g) => g.id == gameId && g.isDone && g.winner != teamId,
      ),
      null => false,
    };
    final awaiting =
        next == null &&
        gamesToPlay(games).any(
          (g) =>
              (g.teamA == null && fromMe(g.sourceA)) ||
              (g.teamB == null && fromMe(g.sourceB)),
        );

    return TournamentDay(
      phase: phase,
      next: next == null ? null : TeamGame(game: next, teamId: teamId),
      last: last == null ? null : TeamGame(game: last, teamId: teamId),
      wins: wins,
      losses: done.length - wins,
      pool: pool,
      poolPlace: place,
      poolSize: size,
      scoreDue: due,
      scoreDueKind: kind,
      awaiting: awaiting,
    );
  }
}

/// Whether a team entered in [entered] has a tournament ahead (or on):
/// an entry still in play (accepted, invited, applied or waitlisted)
/// whose last day (its end, else its start; none counts) is no earlier
/// than yesterday, as dates are the host's local midnight. The team page
/// then shows Tournaments as a tab of its own, out of More. The same rule
/// as hasTournamentAhead in packages/shared/src/tournament_day.ts.
bool hasTournamentAhead(List<EnteredTournament> entered, DateTime now) {
  final yesterday = DateTime(now.year, now.month, now.day - 1);
  return entered.any((e) {
    if (e.status != EntryStatus.accepted && !e.status.isActive) return false;
    final last = e.endsOn ?? e.startsOn;
    if (last == null) return true;
    return !DateTime(last.year, last.month, last.day).isBefore(yesterday);
  });
}
