// A player's roster history for their profile: every team an admin linked
// them to, the ones they have left included, with their season totals from
// each (`GET /v1/players/:uid/team-history`). The per-team season sums port
// the app's PlayerProfileViewModel._recompute (apps/mobile/lib/ui/profile/
// view_models/player_profile_viewmodel.dart); fixtures/team_history/totals.json
// pins them for both sides.
import { z } from "zod";
import type { StatTotals } from "./browse.js";
import { statsGameFrom, statSheet } from "./stats.js";

/** Most linked roster spots one history returns. */
export const teamHistoryMaxSpots = 50;
/** Most games read per team, in document-id order, a page at a time (a stats game can be ~900 KB). */
export const teamHistoryMaxGames = 1000;
/**
 * Most games read in one history request, across all its teams (current teams first).
 * A team cut short by it, or not reached, is flagged `partial`.
 */
export const teamHistoryGameBudget = 400;

/** Games dated outside these UTC years count toward no season. */
export const teamHistoryMinYear = 1900;
export const teamHistoryMaxYear = 2100;

export const teamHistoryKinds = ["team", "community", "organization"] as const;

/** Every total present (StatTotals with no gaps). */
export type SeasonTotals = Required<StatTotals>;

export interface TeamHistoryEntry {
  teamId: string;
  teamName: string;
  teamKind: (typeof teamHistoryKinds)[number];
  /** Still a member of the team; false once they have left it. */
  current: boolean;
  spot: { id: string; name: string; number: number | null };
  /** Season (the year of the game's date, UTC, e.g. "2026") to their totals; empty without games. */
  seasons: Record<string, SeasonTotals>;
  /** True when totals may not cover every game of the team (more than teamHistoryMaxGames, or the request's teamHistoryGameBudget ran out). Absent otherwise. */
  partial?: boolean;
}

export interface TeamHistory {
  teams: TeamHistoryEntry[];
}

const total = z.number().int().nonnegative();
export const seasonTotalsSchema = z.strictObject({
  games: total,
  points: total,
  goals: total,
  assists: total,
  blocks: total,
  completions: total,
  throwaways: total,
  catches: total,
  drops: total,
});

export const teamHistoryEntrySchema = z.strictObject({
  teamId: z.string().min(1),
  teamName: z.string(),
  teamKind: z.enum(teamHistoryKinds),
  current: z.boolean(),
  spot: z.strictObject({ id: z.string().min(1), name: z.string(), number: z.number().int().nullable() }),
  seasons: z.record(z.string().regex(/^\d{4}$/), seasonTotalsSchema),
  partial: z.boolean().optional(),
});

export const teamHistorySchema = z.strictObject({ teams: z.array(teamHistoryEntrySchema).max(teamHistoryMaxSpots) });

const empty = (): SeasonTotals => ({
  games: 0,
  points: 0,
  goals: 0,
  assists: 0,
  blocks: 0,
  completions: 0,
  throwaways: 0,
  catches: 0,
  drops: 0,
});

/**
 * One roster spot's season totals from a team's games (raw statsGames
 * docs, dates ISO or Date). As the app does: a game with no points counts
 * nothing; a spot that neither played a point nor touched the disc in a
 * game (pointsPlayed 0 and touches 0) has no line for it; otherwise the
 * game adds games 1, points, goals, assists, blocks (hand blocks and
 * breakups), completions, throwaways, catches (goals included) and drops
 * to the season of the game's date. The season is the UTC year: teams and
 * games store no time zone, while the app uses the phone's local year, so a
 * game within hours of New Year can differ (fixture case "near New Year").
 */
export function seasonTotalsFor(spotId: string, games: ReadonlyArray<{ id?: string; [k: string]: unknown }>): Record<string, SeasonTotals> {
  return seasonTotalsForSpots([spotId], games).get(spotId)!;
}

/**
 * seasonTotalsFor for several spots of the same team at once: each game's
 * stat sheet is built once and applied to every spot.
 */
export function seasonTotalsForSpots(
  spotIds: readonly string[],
  games: ReadonlyArray<{ id?: string; [k: string]: unknown }>,
): Map<string, Record<string, SeasonTotals>> {
  const out = new Map(spotIds.map((id) => [id, {} as Record<string, SeasonTotals>]));
  for (const raw of games) {
    const g = statsGameFrom(raw.id ?? "", raw);
    if (g.points.length === 0) continue;
    const sheet = statSheet(g.points);
    const yearNumber = new Date(g.date).getUTCFullYear();
    // A date outside these years is bad data: it counts nothing, so every season key is four digits.
    if (!(yearNumber >= teamHistoryMinYear && yearNumber <= teamHistoryMaxYear)) continue;
    const year = `${yearNumber}`;
    for (const [spotId, seasons] of out) {
      const p = sheet.players.get(spotId);
      if (!p || (p.pointsPlayed === 0 && p.touches === 0)) continue;
      const s = (seasons[year] ??= empty());
      s.games += 1;
      s.points += p.pointsPlayed;
      s.goals += p.goals;
      s.assists += p.assists;
      s.blocks += p.handBlocks + p.breakups;
      s.completions += p.completions;
      s.throwaways += p.throwaways;
      s.catches += p.catches + p.goals;
      s.drops += p.drops;
    }
  }
  return out;
}

/** [into] plus [more], season by season (totals are sums, so games can be added a page at a time). */
export function addSeasonTotals(into: Record<string, SeasonTotals>, more: Record<string, SeasonTotals>): Record<string, SeasonTotals> {
  for (const [year, t] of Object.entries(more)) {
    const s = (into[year] ??= empty());
    for (const k of Object.keys(s) as Array<keyof SeasonTotals>) s[k] += t[k];
  }
  return into;
}

/** Current teams first, then the most recent season, then team name (spot id breaks ties). */
export function orderTeamHistory(entries: TeamHistoryEntry[]): TeamHistoryEntry[] {
  const latest = (e: TeamHistoryEntry) => Math.max(-1, ...Object.keys(e.seasons).map(Number));
  return [...entries].sort(
    (a, b) =>
      Number(b.current) - Number(a.current) ||
      latest(b) - latest(a) ||
      (a.teamName < b.teamName ? -1 : a.teamName > b.teamName ? 1 : 0) ||
      (a.spot.id < b.spot.id ? -1 : a.spot.id > b.spot.id ? 1 : 0),
  );
}
