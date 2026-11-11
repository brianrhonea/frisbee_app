// Stall 10's player ratings, from the stats players' teams log with the
// game tracker. Each player's app publishes season totals to their
// profile (`profiles/{uid}.stats`, "2026" → totals); only public profiles
// that show stats are rated, and only once they have [minPlayerGames].
//
// A player's value is their production per point played:
//   goal +1, assist +1, block +1.5, completion or catch +0.05,
//   throwaway -1, drop -0.75,
// over the current and previous season (last season counting half). It's
// shrunk toward the average by [priorPoints] points, so a hot first few
// games don't top the list, and scaled so the average rated player is 50
// and most fall between 20 and 80.

import type { Data } from "./model";

export const minPlayerGames = 10;

/** Points of average play every player starts with. */
export const priorPoints = 60;

/** How much the previous season counts next to this one. */
export const lastSeasonWeight = 0.5;

export const maxRankedPlayers = 200;

export interface SeasonTotals {
  games: number;
  points: number;
  goals: number;
  assists: number;
  blocks: number;
  completions: number;
  catches: number;
  throwaways: number;
  drops: number;
}

export interface PlayerInput {
  uid: string;
  name: string;
  username: string | null;
  photoUrl: string | null;
  /** Season ("2026") → totals. */
  seasons: Record<string, SeasonTotals>;
}

export interface PlayerRating {
  uid: string;
  name: string;
  username: string | null;
  photoUrl: string | null;
  rating: number;
  games: number;
  points: number;
  goals: number;
  assists: number;
  blocks: number;
  turnovers: number;
}

const num = (v: unknown): number => (typeof v === "number" && Number.isFinite(v) && v >= 0 ? v : 0);

export function seasonTotals(raw: unknown): SeasonTotals {
  const m = (raw && typeof raw === "object" ? raw : {}) as Data;
  return {
    games: num(m.games),
    points: num(m.points),
    goals: num(m.goals),
    assists: num(m.assists),
    blocks: num(m.blocks),
    completions: num(m.completions),
    catches: num(m.catches),
    throwaways: num(m.throwaways),
    drops: num(m.drops),
  };
}

/**
 * The profile as rating input, or null if it can't be rated: private,
 * hiding stats, or without a name.
 */
export function playerInput(uid: string, profile: Data): PlayerInput | null {
  if (profile.private === true) return null;
  const visibility = (profile.visibility ?? {}) as Data;
  if (visibility.stats === false) return null;
  const name = typeof profile.name === "string" ? profile.name.trim() : "";
  if (!name) return null;
  const stats = (profile.stats ?? {}) as Data;
  const seasons: Record<string, SeasonTotals> = {};
  for (const [season, totals] of Object.entries(stats)) seasons[season] = seasonTotals(totals);
  return {
    uid,
    name,
    username: typeof profile.username === "string" ? profile.username : null,
    photoUrl: typeof profile.photoUrl === "string" ? profile.photoUrl : null,
    seasons,
  };
}

/** Production for [t]: see the file comment. */
export function production(t: SeasonTotals): number {
  // Catches include goals; don't count a goal's catch twice.
  const touches = t.completions + Math.max(0, t.catches - t.goals);
  return t.goals + t.assists + 1.5 * t.blocks + 0.05 * touches - t.throwaways - 0.75 * t.drops;
}

/** This season plus half of last season, for the year of [now]. */
export function recentTotals(seasons: Record<string, SeasonTotals>, now: Date): SeasonTotals {
  const year = now.getUTCFullYear();
  const keys = Object.keys(seasonTotals({})) as (keyof SeasonTotals)[];
  const total = seasonTotals({});
  for (const [season, weight] of [
    [String(year), 1],
    [String(year - 1), lastSeasonWeight],
  ] as const) {
    const s = seasons[season];
    if (!s) continue;
    for (const k of keys) total[k] += s[k] * weight;
  }
  return total;
}

/**
 * Rates every player with at least [minPlayerGames] recent games (last
 * season counting half), best first.
 */
export function ratePlayers(players: PlayerInput[], now: Date): PlayerRating[] {
  const eligible = players
    .map((p) => ({ p, t: recentTotals(p.seasons, now) }))
    .filter(({ t }) => t.games >= minPlayerGames && t.points > 0);
  if (eligible.length === 0) return [];

  // The average player's production per point, which everyone is shrunk to.
  const allPoints = eligible.reduce((s, { t }) => s + t.points, 0);
  const mean = eligible.reduce((s, { t }) => s + production(t), 0) / allPoints;
  const values = eligible.map(({ t }) => (production(t) + mean * priorPoints) / (t.points + priorPoints));
  const avg = values.reduce((a, b) => a + b, 0) / values.length;
  const sd = Math.sqrt(values.reduce((s, v) => s + (v - avg) ** 2, 0) / values.length);

  return eligible
    .map(({ p, t }, i) => ({
      uid: p.uid,
      name: p.name,
      username: p.username,
      photoUrl: p.photoUrl,
      // One player, or everyone identical: all average.
      rating: sd > 1e-9 ? Math.min(99, Math.max(1, 50 + (15 * (values[i] - avg)) / sd)) : 50,
      games: Math.round(t.games),
      points: Math.round(t.points),
      goals: Math.round(t.goals),
      assists: Math.round(t.assists),
      blocks: Math.round(t.blocks),
      turnovers: Math.round(t.throwaways + t.drops),
    }))
    .sort((a, b) => b.rating - a.rating || b.games - a.games || a.uid.localeCompare(b.uid));
}

/** The stored player ranking: the top [maxRankedPlayers], numbered. */
export function playerRankingDoc(ratings: PlayerRating[]): Data {
  return {
    minGames: minPlayerGames,
    players: ratings.slice(0, maxRankedPlayers).map((r, i) => ({
      ...r,
      rank: i + 1,
      rating: Math.round(r.rating),
    })),
  };
}
