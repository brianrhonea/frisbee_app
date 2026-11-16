// Stall 10's team rankings (the `rankings` Cloud Functions write
// `rankings/{level-division}` nightly): the levels and divisions they
// cover, the Rankings page's two filters (Level, Division) with their
// default, and what signed-out visitors get from `GET /v1/public/rankings`.
//
// Youth is never ranked: the functions skip youth divisions and youth
// teams, and every reader (API, website, app) also leaves out a youth key.
// The filter logic is mirrored in the app (apps/mobile/lib/domain/models/
// ranking.dart, RankingChoice) and checked against the shared vectors in
// fixtures/rankings (written by the app's tests).
import { z } from "zod";
import { type CompetitionLevel, type Division, divisions } from "./team.js";

/**
 * The levels that are ranked, in the filter's order. Listed on purpose
 * rather than "every level but youth", so a level added later isn't
 * ranked (or shown) until it's added here.
 */
export const rankedLevels = ["club", "college", "league", "pickup"] as const satisfies readonly CompetitionLevel[];
export type RankedLevel = (typeof rankedLevels)[number];

/** The divisions, in the filter's order. */
export const rankingDivisions = divisions;

export const rankedLevelLabels: Record<RankedLevel, string> = { club: "Club", college: "College", league: "League", pickup: "Pickup" };
export const rankingDivisionLabels: Record<Division, string> = { mixed: "Mixed", open: "Open", women: "Women", masters: "Masters" };

/** The ranking shown when nothing (or nothing that has data) is asked for, if it has data. */
export const defaultRankingKey = "club-mixed";

export const isRankedLevel = (v: unknown): v is RankedLevel => (rankedLevels as readonly unknown[]).includes(v);
export const isRankingDivision = (v: unknown): v is Division => (rankingDivisions as readonly unknown[]).includes(v);

/** The doc id for a level and division: "club-mixed". */
export const rankingKey = (level: string, division: string): string => `${level}-${division}`;

/** A ranking key's level and division, or null for anything not ranked (youth, unknown, malformed). */
export function parseRankingKey(key: unknown): { level: RankedLevel; division: Division } | null {
  if (typeof key !== "string") return null;
  const parts = key.split("-");
  if (parts.length !== 2) return null;
  const [level, division] = parts;
  return isRankedLevel(level) && isRankingDivision(division) ? { level, division } : null;
}

/** "Club Mixed". */
export const rankingLabel = (level: RankedLevel, division: Division): string =>
  `${rankedLevelLabels[level]} ${rankingDivisionLabels[division]}`;

/** The ranked keys among [keys], each once, by level then division (the filters' order). Youth and unknown keys are left out. */
export function orderedRankingKeys(keys: Iterable<string>): string[] {
  const order = (k: string) => {
    const p = parseRankingKey(k)!;
    return rankedLevels.indexOf(p.level) * 10 + rankingDivisions.indexOf(p.division);
  };
  return [...new Set([...keys].filter((k) => parseRankingKey(k) !== null))].sort((a, b) => order(a) - order(b));
}

/** What a link or a pick asks for; any of it may be missing or wrong. */
export interface RankingWant {
  level?: string | null;
  division?: string | null;
}

/** The two filters and what they're set to. */
export interface RankingChoice {
  level: RankedLevel;
  division: Division;
  key: string;
  /** Levels with any ranking, in order: the Level filter's options. */
  levels: RankedLevel[];
  /** Divisions ranked at [level], in order: the Division filter's options. */
  divisions: Division[];
}

/**
 * Reads the Rankings page's link: `?level=club&division=mixed`, or the old
 * `?division=club-mixed` (a key, used when no level is given). A youth or
 * unknown key reads as nothing asked for.
 */
export function rankingWantFromQuery(q: { level?: string | null; division?: string | null; d?: string | null }): RankingWant {
  const legacy = q.d ?? (q.division?.includes("-") ? q.division : null);
  if (legacy && !q.level) {
    const p = parseRankingKey(legacy);
    return p ? { level: p.level, division: p.division } : {};
  }
  return { level: q.level ?? null, division: q.division?.includes("-") ? null : (q.division ?? null) };
}

/**
 * Which ranking the filters show, given the [keys] that have data, or null
 * when none does. The level and division asked for if that ranking has
 * data; else the level asked for, at its first division with data; else
 * the division asked for, at the first level that has it; else Club Mixed,
 * else the first ranking. Club Mixed wins ties, so it's the default.
 */
export function chooseRanking(keys: Iterable<string>, want: RankingWant = {}): RankingChoice | null {
  const ordered = orderedRankingKeys(keys);
  if (ordered.length === 0) return null;
  const prefer = ordered.includes(defaultRankingKey) ? [defaultRankingKey, ...ordered.filter((k) => k !== defaultRankingKey)] : ordered;
  const parsed = prefer.map((k) => ({ key: k, ...parseRankingKey(k)! }));
  const level = isRankedLevel(want.level) ? want.level : null;
  const division = isRankingDivision(want.division) ? want.division : null;
  const pick =
    parsed.find((p) => (!level || p.level === level) && (!division || p.division === division)) ??
    (level ? parsed.find((p) => p.level === level) : undefined) ??
    parsed[0]!;
  const all = ordered.map((k) => parseRankingKey(k)!);
  return {
    level: pick.level,
    division: pick.division,
    key: pick.key,
    levels: rankedLevels.filter((l) => all.some((p) => p.level === l)),
    divisions: rankingDivisions.filter((d) => all.some((p) => p.level === pick.level && p.division === d)),
  };
}

/** The Rankings page's link for a choice: `/rankings?level=club&division=mixed`. */
export const rankingsHref = (level: string, division: string): string =>
  `/rankings?level=${encodeURIComponent(level)}&division=${encodeURIComponent(division)}`;

/** A ranked team, as visitors get it. */
export const publicRankedTeamSchema = z.strictObject({
  rank: z.number().int().min(1),
  teamId: z.string().min(1),
  name: z.string(),
  rating: z.number().int(),
  wins: z.number().int().min(0),
  losses: z.number().int().min(0),
});
export type PublicRankedTeam = z.infer<typeof publicRankedTeamSchema>;

/** One level and division's ranking, as visitors get it. */
export const publicDivisionRankingSchema = z.strictObject({
  key: z.string(),
  level: z.enum(rankedLevels),
  division: z.enum(rankingDivisions),
  /** Games a team needs to be ranked. */
  minGames: z.number().int().min(0),
  /** ISO time of the last rebuild, if known. */
  updatedAt: z.string().nullable(),
  /** Best first, numbered from 1. */
  teams: z.array(publicRankedTeamSchema),
});
export type PublicDivisionRanking = z.infer<typeof publicDivisionRankingSchema>;

/** `GET /v1/public/rankings`: every ranking with teams, by level then division. Never youth. */
export const publicRankingsSchema = z.strictObject({ rankings: z.array(publicDivisionRankingSchema) });
export type PublicRankings = z.infer<typeof publicRankingsSchema>;
