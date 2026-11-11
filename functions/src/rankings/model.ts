// Stall 10's own team rankings, from finished games in public hosted
// tournaments (club-style, teams entered from the app), one ranking per
// competition level and division ("club-mixed").
//
// A score-differential rating, solved over the whole window:
//   - every game gives each team a game rating: the opponent's rating plus
//     (winner) or minus (loser) a differential that grows with the margin,
//     from 125 for a one-point game to 600 for a blowout;
//   - a team's rating is the weighted average of its game ratings, where
//     games to more points and more recent games weigh more;
//   - ratings are re-solved together until they settle, so beating a team
//     that later turns out strong is worth more;
//   - lopsided wins over much weaker teams are left out, if the winner has
//     enough other games, so a strong team isn't punished for its schedule.

export type Data = Record<string, unknown>;

/** A finished game. Teams are team doc ids. */
export interface RankedGame {
  teamA: string;
  teamB: string;
  scoreA: number;
  scoreB: number;
  /** When it was played; the tournament's start when games have no time. */
  playedAt: Date;
}

export interface TeamRating {
  teamId: string;
  rating: number;
  wins: number;
  losses: number;
  games: number;
}

export const startingRating = 1000;

/** Fewer games than this and a team is rated but not ranked. */
export const minGames = 5;

/** Games older than this don't count. */
export const windowDays = 365;

const maxDiff = 600;
const minDiff = 125;

/**
 * Rating points the winner earns over the loser for [winner]–[loser]:
 * 125 for a one-point win, rising along a sine curve to 600 once the loser
 * scored half the winner's points or fewer (minus one). A tie earns none.
 */
export function differential(winner: number, loser: number): number {
  if (winner <= loser) return 0;
  if (winner <= 1) return maxDiff;
  const r = loser / (winner - 1);
  const x = Math.min(1, (1 - r) / 0.5);
  return minDiff + (maxDiff - minDiff) * (Math.sin(x * 0.4 * Math.PI) / Math.sin(0.4 * Math.PI));
}

/**
 * How much a game to [winner]–[loser] counts: full weight from 19 points
 * played (13–6, 15–4), less for short games.
 */
export function scoreWeight(winner: number, loser: number): number {
  const counted = winner + Math.max(loser, Math.floor((winner - 1) / 2));
  return Math.min(1, Math.sqrt(counted / 19));
}

/** Games from the last week count fully, falling to a quarter a year back. */
export function dateWeight(playedAt: Date, now: Date): number {
  const days = Math.max(0, (now.getTime() - playedAt.getTime()) / 86_400_000);
  return Math.pow(0.25, Math.min(days, windowDays) / windowDays);
}

/** Games that can be rated: two different teams, sane scores, in the window. */
export function usable(games: RankedGame[], now: Date): RankedGame[] {
  const cutoff = now.getTime() - windowDays * 86_400_000;
  return games.filter(
    (g) =>
      g.teamA &&
      g.teamB &&
      g.teamA !== g.teamB &&
      Number.isInteger(g.scoreA) &&
      Number.isInteger(g.scoreB) &&
      g.scoreA >= 0 &&
      g.scoreB >= 0 &&
      g.scoreA + g.scoreB > 0 &&
      g.playedAt.getTime() >= cutoff &&
      g.playedAt.getTime() <= now.getTime() + 86_400_000,
  );
}

/** Whether [g] is a blowout the winner can drop: see [rate]. */
function isBlowout(g: RankedGame, ratings: Map<string, number>): boolean {
  const [w, l, ws, ls] = g.scoreA > g.scoreB ? [g.teamA, g.teamB, g.scoreA, g.scoreB] : [g.teamB, g.teamA, g.scoreB, g.scoreA];
  if (ws === ls) return false;
  return ws > 2 * ls + 1 && ratings.get(w)! - ratings.get(l)! > maxDiff;
}

/**
 * Rates every team in [games], strongest first. Iterates up to [rounds]
 * times, stopping early once no rating moves by more than 0.01.
 */
export function rate(games: RankedGame[], now: Date, rounds = 2000): TeamRating[] {
  const list = usable(games, now);
  const ratings = new Map<string, number>();
  const record = new Map<string, { wins: number; losses: number; games: number }>();
  for (const g of list) {
    for (const t of [g.teamA, g.teamB]) {
      ratings.set(t, startingRating);
      if (!record.has(t)) record.set(t, { wins: 0, losses: 0, games: 0 });
    }
    const a = record.get(g.teamA)!;
    const b = record.get(g.teamB)!;
    a.games++;
    b.games++;
    if (g.scoreA > g.scoreB) {
      a.wins++;
      b.losses++;
    } else if (g.scoreB > g.scoreA) {
      b.wins++;
      a.losses++;
    }
  }
  const weights = list.map((g) => {
    const hi = Math.max(g.scoreA, g.scoreB);
    const lo = Math.min(g.scoreA, g.scoreB);
    return scoreWeight(hi, lo) * dateWeight(g.playedAt, now);
  });
  const diffs = list.map((g) =>
    g.scoreA >= g.scoreB ? differential(g.scoreA, g.scoreB) : -differential(g.scoreB, g.scoreA),
  );

  for (let round = 0; round < rounds; round++) {
    // Blowouts the winner may drop: it keeps at least [minGames] others.
    const dropped = new Set<number>();
    const kept = new Map<string, number>();
    for (const [t, r] of record) kept.set(t, r.games);
    list.forEach((g, i) => {
      if (!isBlowout(g, ratings)) return;
      const winner = g.scoreA > g.scoreB ? g.teamA : g.teamB;
      if (kept.get(winner)! - 1 < minGames) return;
      kept.set(winner, kept.get(winner)! - 1);
      dropped.add(i);
    });

    const sum = new Map<string, number>();
    const weight = new Map<string, number>();
    list.forEach((g, i) => {
      const w = weights[i];
      const d = diffs[i];
      const winner = d >= 0 ? g.teamA : g.teamB;
      const sides: [string, number][] = [
        [g.teamA, ratings.get(g.teamB)! + d],
        [g.teamB, ratings.get(g.teamA)! - d],
      ];
      for (const [team, gameRating] of sides) {
        // A dropped blowout doesn't count for the winner; the loser keeps it.
        if (dropped.has(i) && team === winner) continue;
        sum.set(team, (sum.get(team) ?? 0) + w * gameRating);
        weight.set(team, (weight.get(team) ?? 0) + w);
      }
    });

    let moved = 0;
    const next = new Map<string, number>();
    for (const [team, old] of ratings) {
      const w = weight.get(team) ?? 0;
      // Halfway to the new average: undamped, ratings can swing back and
      // forth between rounds forever instead of settling.
      const value = w > 0 ? (old + sum.get(team)! / w) / 2 : old;
      next.set(team, value);
      moved = Math.max(moved, Math.abs(value - old));
    }
    // Ratings only mean anything relative to each other: keep the
    // average at the starting rating so they don't drift.
    const mean = [...next.values()].reduce((a, b) => a + b, 0) / Math.max(1, next.size);
    for (const [team, value] of next) ratings.set(team, value - mean + startingRating);
    if (moved < 0.01) break;
  }

  return [...ratings.entries()]
    .map(([teamId, rating]) => ({ teamId, rating, ...record.get(teamId)! }))
    .sort((a, b) => b.rating - a.rating || b.wins - a.wins || a.teamId.localeCompare(b.teamId));
}

/** The ranking doc id for a division: "club-mixed". */
export const rankingKey = (level: string, division: string): string => `${level}-${division}`;

/** Whether a tournament's games count toward rankings. */
export function countsForRankings(t: Data): boolean {
  return (
    t.visibility === "public" &&
    (t.entryType ?? "teams") === "teams" &&
    // A weekly league isn't a tournament: its standings aren't comparable.
    (t.kind ?? "tournament") === "tournament" &&
    (t.status === "live" || t.status === "finished")
  );
}

export const maxRanked = 200;

/**
 * The stored ranking for one division: the ranked teams (at least
 * [minGames] games), best first, numbered; [names] by team id.
 */
export function rankingDoc(
  level: string,
  division: string,
  ratings: TeamRating[],
  names: Map<string, string>,
): Data {
  const teams = ratings
    .filter((r) => r.games >= minGames)
    .slice(0, maxRanked)
    .map((r, i) => ({
      rank: i + 1,
      teamId: r.teamId,
      name: names.get(r.teamId) ?? "Team",
      rating: Math.round(r.rating),
      wins: r.wins,
      losses: r.losses,
    }));
  return { level, division, teams, minGames };
}

/** A finished tournament's results for Explore: each division's top two. */
export interface DivisionResult {
  label: string;
  champion: { teamId: string; name: string } | null;
  runnerUp: { teamId: string; name: string } | null;
}

const levelLabels: Record<string, string> = {
  club: "Club",
  college: "College",
  youth: "Youth",
  league: "League",
  pickup: "Pickup",
};
const divisionLabels: Record<string, string> = {
  mixed: "Mixed",
  open: "Open",
  women: "Women",
  masters: "Masters",
};

/** "Club Mixed", like the app's DivisionSummary.label. */
export const divisionLabel = (level: string, division: string): string =>
  `${levelLabels[level] ?? level} ${divisionLabels[division] ?? division}`;

export function divisionResult(div: Data, names: Map<string, string>): DivisionResult {
  const places = Array.isArray(div.placements) ? (div.placements as unknown[]).map(String) : [];
  const team = (id: string | undefined) => (id ? { teamId: id, name: names.get(id) ?? "Team" } : null);
  return {
    label: divisionLabel(String(div.level ?? "club"), String(div.division ?? "mixed")),
    champion: team(places[0]),
    runnerUp: team(places[1]),
  };
}
