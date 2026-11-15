// A community's own tournaments (teams/{groupId}/groupTournaments/{id} and
// its games), GroupTournament and GroupGame in the app's
// lib/domain/models/group_tournament.dart, with the app's tournament
// engine (lib/domain/tournament_engine: generator, progress, standings,
// team_builder) ported for the group tournament slice. Dates are ISO
// strings here; the API stores them as timestamps.
//
// The engine's functions live in one object (groupEngine) so they don't
// clash with other slices' exports through index.ts.
import { z } from "zod";

// ---- Model -------------------------------------------------------------------

export const groupTournamentFormats = ["roundRobin", "poolsSingleElim", "singleElim", "doubleElim", "poolsPlacement"] as const;
export type GroupTournamentFormat = (typeof groupTournamentFormats)[number];

/** TournamentFormat's label and summary. */
export const groupTournamentFormatInfo: Record<GroupTournamentFormat, { label: string; summary: string }> = {
  roundRobin: { label: "Round robin", summary: "Everyone plays everyone; best record wins" },
  poolsSingleElim: { label: "Pool play + single elimination", summary: "Pools first, then a bracket seeded by pool finish" },
  singleElim: { label: "Single elimination", summary: "Lose once and you are out" },
  doubleElim: { label: "Double elimination", summary: "Lose twice and you are out" },
  poolsPlacement: { label: "Pool play + placement bracket", summary: "Pools, then brackets where every team plays for a final place" },
};
export const groupFormatHasPools = (f: GroupTournamentFormat) => f === "roundRobin" || f === "poolsSingleElim" || f === "poolsPlacement";
export const groupFormatHasBracket = (f: GroupTournamentFormat) => f !== "roundRobin";

export const groupTournamentStatuses = ["setup", "scheduled", "done"] as const;
export type GroupTournamentStatus = (typeof groupTournamentStatuses)[number];
export const groupTournamentStatusLabels: Record<GroupTournamentStatus, string> = {
  setup: "Setting up",
  scheduled: "Scheduled",
  done: "Finished",
};

export const groupScoringModes = ["points", "time"] as const;
export type GroupScoringMode = (typeof groupScoringModes)[number];

export const groupGameStages = ["pool", "winners", "losers", "grandFinal", "reset", "crossover", "placement"] as const;
export type GroupGameStage = (typeof groupGameStages)[number];
export const groupGameStageLabels: Record<GroupGameStage, string> = {
  pool: "Pool",
  winners: "Bracket",
  losers: "Losers' bracket",
  grandFinal: "Final",
  reset: "Final (if needed)",
  crossover: "Crossover",
  placement: "Placement",
};
export const groupGameStatuses = ["scheduled", "reported", "done"] as const;
export type GroupGameStatus = (typeof groupGameStatuses)[number];

/** What the editor offers (TournamentSettings and the editor's steppers). */
export const groupTournamentLimits = {
  name: 100,
  teamName: 40,
  teams: 64,
  participants: 1000,
  playerName: 80,
  laterDays: 30,
  fieldSizes: [3, 4, 5, 6, 7],
  defaultTeams: 4,
  maxScore: 99,
} as const;

/** TournamentTeam.toMap. */
export interface GroupTournamentTeam {
  id: string;
  name: string;
  captainId: string | null;
  playerIds: string[];
  playerNames: Record<string, string>;
}

/** TournamentSettings.toMap, dates as ISO strings. */
export interface GroupTournamentSettings {
  format: GroupTournamentFormat;
  playersOnField: number;
  poolCount: number;
  gameMinutes: number;
  breakMinutes: number;
  scoreCap: number;
  timeoutsPerHalf: number;
  fields: number;
  startsAt: string;
  idealEndsAt: string | null;
  laterDays: string[];
  scoring: GroupScoringMode;
}

/** A tournament as the website reads it (GroupTournament.fromMap). */
export interface GroupTournamentDoc {
  name?: string;
  eventId?: string | null;
  settings?: Partial<GroupTournamentSettings>;
  status?: GroupTournamentStatus;
  teams?: GroupTournamentTeam[];
  participantIds?: string[];
  captains?: Record<string, string>;
  createdBy?: string;
  createdAt?: string;
}

export type GroupSlotSource = { type: "winner" | "loser"; game: string } | { type: "pool"; pool: string; rank: number };

export interface GroupScoreReport {
  scoreA: number;
  scoreB: number;
  /** The team whose captain reported it. */
  byTeam: string;
}

/** GroupGame.toMap (with its id), dates as ISO strings. */
export interface GroupGame {
  id: string;
  order: number;
  stage: GroupGameStage;
  round: number;
  label: string;
  pool: string | null;
  field: number;
  startsAt: string | null;
  teamA: string | null;
  teamB: string | null;
  sourceA: GroupSlotSource | null;
  sourceB: GroupSlotSource | null;
  status: GroupGameStatus;
  scoreA: number | null;
  scoreB: number | null;
  report: GroupScoreReport | null;
  ifNeeded: boolean;
  /** Only for games deciding a final place: the winner's place. */
  place?: number | null;
}

/** tournamentDirectory/{groupId}_{tournamentId} (TournamentListing). */
export interface GroupTournamentListing {
  groupId: string;
  tournamentId: string;
  name: string;
  startsAt: string;
  endsOn: string | null;
  status: GroupTournamentStatus;
  format: GroupTournamentFormat;
}

const num = (v: unknown, fallback: number) => (typeof v === "number" && Number.isFinite(v) ? Math.trunc(v) : fallback);
const oneOf = <T extends string>(list: readonly T[], v: unknown, fallback: T): T => (list.includes(v as T) ? (v as T) : fallback);
const isoOr = (v: unknown): string | null => (typeof v === "string" && !Number.isNaN(Date.parse(v)) ? v : null);

/** TournamentSettings.fromMap: defaults for anything missing. */
export function readGroupSettings(raw: unknown): GroupTournamentSettings {
  const m = (raw && typeof raw === "object" ? raw : {}) as Record<string, unknown>;
  return {
    format: oneOf(groupTournamentFormats, m.format, "poolsSingleElim"),
    playersOnField: num(m.playersOnField, 5),
    poolCount: num(m.poolCount, 2),
    gameMinutes: num(m.gameMinutes, 40),
    breakMinutes: num(m.breakMinutes, 10),
    scoreCap: num(m.scoreCap, 11),
    timeoutsPerHalf: num(m.timeoutsPerHalf, 1),
    fields: num(m.fields, 1),
    startsAt: isoOr(m.startsAt) ?? new Date(1970, 0, 1).toISOString(),
    idealEndsAt: isoOr(m.idealEndsAt),
    laterDays: Array.isArray(m.laterDays) ? m.laterDays.flatMap((d) => (isoOr(d) ? [isoOr(d)!] : [])) : [],
    scoring: oneOf(groupScoringModes, m.scoring, "points"),
  };
}

/** TournamentTeam.fromMap for each team. */
export function readGroupTeams(raw: unknown): GroupTournamentTeam[] {
  if (!Array.isArray(raw)) return [];
  return raw
    .filter((t): t is Record<string, unknown> => !!t && typeof t === "object")
    .map((t) => ({
      id: String(t.id ?? ""),
      name: String(t.name ?? ""),
      captainId: typeof t.captainId === "string" ? t.captainId : null,
      playerIds: Array.isArray(t.playerIds) ? t.playerIds.map(String) : [],
      playerNames: Object.fromEntries(
        Object.entries(t.playerNames && typeof t.playerNames === "object" ? (t.playerNames as Record<string, unknown>) : {}).map(([k, v]) => [k, String(v)]),
      ),
    }));
}

function readSource(raw: unknown): GroupSlotSource | null {
  if (!raw || typeof raw !== "object") return null;
  const s = raw as Record<string, unknown>;
  if (s.type === "winner" || s.type === "loser") return { type: s.type, game: String(s.game) };
  if (s.type === "pool") return { type: "pool", pool: String(s.pool), rank: num(s.rank, 1) };
  return null;
}

/** GroupGame.fromMap. */
export function readGroupGame(id: string, m: Record<string, unknown>): GroupGame {
  const r = m.report && typeof m.report === "object" ? (m.report as Record<string, unknown>) : null;
  return {
    id,
    order: num(m.order, 0),
    stage: oneOf(groupGameStages, m.stage, "pool"),
    round: num(m.round, 1),
    label: String(m.label ?? ""),
    pool: typeof m.pool === "string" ? m.pool : null,
    field: num(m.field, 1),
    startsAt: isoOr(m.startsAt) ?? (m.startsAt instanceof Date ? m.startsAt.toISOString() : null),
    teamA: typeof m.teamA === "string" ? m.teamA : null,
    teamB: typeof m.teamB === "string" ? m.teamB : null,
    sourceA: readSource(m.sourceA),
    sourceB: readSource(m.sourceB),
    status: oneOf(groupGameStatuses, m.status, "scheduled"),
    scoreA: typeof m.scoreA === "number" ? Math.trunc(m.scoreA) : null,
    scoreB: typeof m.scoreB === "number" ? Math.trunc(m.scoreB) : null,
    report: r ? { scoreA: num(r.scoreA, 0), scoreB: num(r.scoreB, 0), byTeam: String(r.byTeam ?? "") } : null,
    ifNeeded: m.ifNeeded === true,
    place: typeof m.place === "number" ? Math.trunc(m.place) : null,
  };
}

/** TournamentSettings.summary: "5v5 · to 11 · 40 min · 1 timeout per half". */
export function groupSettingsSummary(s: GroupTournamentSettings): string {
  const days = 1 + s.laterDays.length;
  return [
    ...(s.laterDays.length ? [`${days} days`] : []),
    `${s.playersOnField}v${s.playersOnField}`,
    ...(s.scoring === "time" ? [`${s.gameMinutes} min timed`, "tied at time: one more point"] : [`to ${s.scoreCap}`, `${s.gameMinutes} min`]),
    `${s.timeoutsPerHalf} timeout${s.timeoutsPerHalf === 1 ? "" : "s"} per half`,
  ].join(" · ");
}

// ---- Requests ----------------------------------------------------------------

const isoDate = z.iso.datetime({ offset: true, message: "Pick a date and time." });
const uid = z.string().regex(/^[A-Za-z0-9_-]{1,128}$/, "Invalid player.");

const settingsSchema = z.strictObject({
  format: z.enum(groupTournamentFormats).default("poolsSingleElim"),
  playersOnField: z.number().int().min(3).max(7).default(5),
  poolCount: z.number().int().min(1).max(32).default(2),
  gameMinutes: z.number().int().min(5).max(240).default(40),
  breakMinutes: z.number().int().min(0).max(120).default(10),
  scoreCap: z.number().int().min(1).max(groupTournamentLimits.maxScore).default(11),
  timeoutsPerHalf: z.number().int().min(0).max(10).default(1),
  fields: z.number().int().min(1).max(64).default(1),
  startsAt: isoDate,
  idealEndsAt: isoDate.nullable().default(null),
  laterDays: z.array(isoDate).max(groupTournamentLimits.laterDays, "Up to 30 more days.").default([]),
  scoring: z.enum(groupScoringModes).default("points"),
});

const teamSchema = z.strictObject({
  id: z.string().regex(/^[A-Za-z0-9_-]{1,40}$/, "Invalid team."),
  name: z.string().trim().min(1, "Give every team a name.").max(groupTournamentLimits.teamName, "Keep team names under 40 characters."),
  captainId: uid.nullable().default(null),
  playerIds: z.array(uid).max(groupTournamentLimits.participants).default([]),
  playerNames: z.record(uid, z.string().max(groupTournamentLimits.playerName)).default({}),
});

/**
 * `POST /v1/teams/:teamId/group-tournaments`, `PUT .../:id` and
 * `POST .../:id/schedule`: the editor's draft. The API works out
 * participantIds, captains, status and who made it.
 */
export const saveGroupTournamentRequestSchema = z
  .strictObject({
    name: z.string().trim().min(1, "Give the tournament a name.").max(groupTournamentLimits.name, "Keep the name under 100 characters."),
    eventId: z.string().regex(/^[A-Za-z0-9_-]{1,100}$/, "Invalid event.").nullable().default(null),
    settings: settingsSchema,
    teams: z.array(teamSchema).max(groupTournamentLimits.teams, "A tournament can have up to 64 teams.").default([]),
  })
  .superRefine((t, ctx) => {
    const ids = new Set<string>();
    const players = new Set<string>();
    for (const team of t.teams) {
      if (ids.has(team.id)) ctx.addIssue({ code: "custom", message: "Each team needs its own id.", path: ["teams"] });
      ids.add(team.id);
      for (const p of team.playerIds) {
        if (players.has(p)) ctx.addIssue({ code: "custom", message: "A player can only be on one team.", path: ["teams"] });
        players.add(p);
      }
      if (team.captainId !== null && !team.playerIds.includes(team.captainId)) {
        ctx.addIssue({ code: "custom", message: "A captain must play on their team.", path: ["teams"] });
      }
    }
    if (players.size > groupTournamentLimits.participants) {
      ctx.addIssue({ code: "custom", message: "A tournament can have up to 1,000 players.", path: ["teams"] });
    }
  });
export type SaveGroupTournamentRequest = z.input<typeof saveGroupTournamentRequestSchema>;

/** `POST .../games/:gameId/report`, `.../confirm` (the score being confirmed) and `PUT .../score`. */
export const groupGameScoreRequestSchema = z
  .strictObject({
    scoreA: z.number().int().min(0, "Scores go from 0 to 99.").max(99, "Scores go from 0 to 99."),
    scoreB: z.number().int().min(0, "Scores go from 0 to 99.").max(99, "Scores go from 0 to 99."),
  })
  .refine((s) => s.scoreA !== s.scoreB, { message: "Games can't end in a tie.", path: ["scoreB"] });
export type GroupGameScoreRequest = z.input<typeof groupGameScoreRequestSchema>;

// ---- Engine: standings (standings.dart) ----------------------------------

export interface GroupStanding {
  teamId: string;
  wins: number;
  losses: number;
  pointsFor: number;
  pointsAgainst: number;
}
const pointDiff = (s: GroupStanding) => s.pointsFor - s.pointsAgainst;

const isDone = (g: GroupGame) => g.status === "done";
const hasTeams = (g: GroupGame) => g.teamA !== null && g.teamB !== null;
const winnerOf = (g: GroupGame) => (!isDone(g) ? null : g.scoreA! > g.scoreB! ? g.teamA : g.teamB);
const loserOf = (g: GroupGame) => (!isDone(g) ? null : g.scoreA! > g.scoreB! ? g.teamB : g.teamA);
const isBracket = (stage: GroupGameStage) => stage !== "pool";

/** "A", "B", ... */
const poolName = (i: number) => String.fromCharCode(65 + i);

function poolTeams(games: GroupGame[]): Map<string, string[]> {
  const pools = new Map<string, Set<string>>();
  for (const g of games) {
    if (g.stage !== "pool" || g.pool === null) continue;
    if (!pools.has(g.pool)) pools.set(g.pool, new Set());
    for (const t of [g.teamA, g.teamB]) if (t !== null) pools.get(g.pool)!.add(t);
  }
  return new Map([...pools.keys()].sort().map((k) => [k, [...pools.get(k)!]]));
}

const poolComplete = (pool: string, games: GroupGame[]) => games.filter((g) => g.stage === "pool" && g.pool === pool).every(isDone);

/**
 * [teamIds] ranked by pool results: most wins, then head to head among the
 * tied teams, then point differential, then points scored, then seed.
 */
function standings(teamIds: string[], games: GroupGame[]): GroupStanding[] {
  const done = games.filter((g) => isDone(g) && teamIds.includes(g.teamA!) && teamIds.includes(g.teamB!));
  const rows = new Map(teamIds.map((id) => [id, { teamId: id, wins: 0, losses: 0, pointsFor: 0, pointsAgainst: 0 }]));
  for (const g of done) {
    const a = rows.get(g.teamA!)!;
    const b = rows.get(g.teamB!)!;
    a.pointsFor += g.scoreA!;
    a.pointsAgainst += g.scoreB!;
    b.pointsFor += g.scoreB!;
    b.pointsAgainst += g.scoreA!;
    if (winnerOf(g) === a.teamId) {
      a.wins++;
      b.losses++;
    } else {
      b.wins++;
      a.losses++;
    }
  }
  const headToHead = (s: GroupStanding, tied: Set<string>) =>
    done.filter((g) => winnerOf(g) === s.teamId && tied.has(g.teamA!) && tied.has(g.teamB!)).length;
  const byWins = new Map<number, GroupStanding[]>();
  for (const r of rows.values()) {
    if (!byWins.has(r.wins)) byWins.set(r.wins, []);
    byWins.get(r.wins)!.push(r);
  }
  return [...byWins.keys()]
    .sort((a, b) => b - a)
    .flatMap((wins) => {
      const group = byWins.get(wins)!;
      const tied = new Set(group.map((s) => s.teamId));
      return group.sort(
        (x, y) =>
          headToHead(y, tied) - headToHead(x, tied) ||
          pointDiff(y) - pointDiff(x) ||
          y.pointsFor - x.pointsFor ||
          teamIds.indexOf(x.teamId) - teamIds.indexOf(y.teamId),
      );
    });
}

// ---- Engine: generator (generator.dart) -----------------------------------

export class GroupScheduleError extends Error {}

export interface GroupScheduleDay {
  startsAt: string;
  /** When the day's last game should finish; startsAt if it has none. */
  endsAt: string;
  games: number;
}
export interface GroupSchedulePlan {
  games: GroupGame[];
  days: GroupScheduleDay[];
  endsAt: string;
}

/** Every pairing of [teams], by round (circle method). */
function roundRobin<T>(teams: T[]): Array<Array<[T, T]>> {
  const list: Array<T | null> = [...teams, ...(teams.length % 2 === 1 ? [null] : [])];
  const n = list.length;
  if (n < 2) return [];
  const rounds: Array<Array<[T, T]>> = [];
  for (let r = 0; r < n - 1; r++) {
    const round: Array<[T, T]> = [];
    for (let i = 0; i < Math.floor(n / 2); i++) {
      const a = list[i]!;
      const c = list[n - 1 - i]!;
      if (a !== null && c !== null) round.push([a, c]);
    }
    rounds.push(round);
    list.splice(1, 0, list.pop()!);
  }
  return rounds;
}

/** Bracket positions for [size] seeds (a power of two), in match order. */
function seedOrder(size: number): number[] {
  let order = [1];
  while (order.length < size) {
    const n = order.length * 2;
    order = order.flatMap((s) => [s, n + 1 - s]);
  }
  return order;
}

function bracketSize(n: number) {
  let p = 1;
  while (p < n) p *= 2;
  return p;
}

const roundName = (matches: number, round: number) =>
  matches === 1 ? "Final" : matches === 2 ? "Semifinal" : matches === 4 ? "Quarterfinal" : `Round ${round}`;

function ordinal(n: number): string {
  const teen = n % 100 >= 11 && n % 100 <= 13;
  const suffix = teen ? "th" : n % 10 === 1 ? "st" : n % 10 === 2 ? "nd" : n % 10 === 3 ? "rd" : "th";
  return `${n}${suffix}`;
}

/** Suggested pool count (one round robin up to 6, pools of 4 or 5 above). */
const suggestedPools = (teams: number) => (teams <= 6 ? 1 : Math.max(2, Math.round(teams / 4.5)));

type Entrant = { team: string; source: null } | { team: null; source: GroupSlotSource };
const entrantTeam = (team: string): Entrant => ({ team, source: null });
const entrantSource = (source: GroupSlotSource): Entrant => ({ team: null, source });
interface Match {
  winner: Entrant | null;
  loser: Entrant | null;
  gameId: string | null;
}

class Builder {
  games: GroupGame[] = [];

  add(o: { stage: GroupGameStage; round: number; label: string; a: Entrant; c: Entrant; pool?: string; ifNeeded?: boolean; place?: number | null }): string {
    const id = `g${String(this.games.length + 1).padStart(3, "0")}`;
    this.games.push({
      id,
      order: this.games.length,
      stage: o.stage,
      round: o.round,
      label: o.label,
      pool: o.pool ?? null,
      field: 1,
      startsAt: null,
      teamA: o.a.team,
      teamB: o.c.team,
      sourceA: o.a.source,
      sourceB: o.c.source,
      status: "scheduled",
      scoreA: null,
      scoreB: null,
      report: null,
      ifNeeded: o.ifNeeded ?? false,
      place: o.place ?? null,
    });
    return id;
  }

  /** A game between [a] and [c], or a bye if either is missing. */
  match(o: { stage: GroupGameStage; round: number; label: string; a: Entrant | null; c: Entrant | null; place?: number | null }): Match {
    if (o.a === null || o.c === null) return { winner: o.a ?? o.c, loser: null, gameId: null };
    const id = this.add({ ...o, a: o.a, c: o.c });
    return { winner: entrantSource({ type: "winner", game: id }), loser: entrantSource({ type: "loser", game: id }), gameId: id };
  }
}

/** Snake-seeds [teams] into [count] pools and adds each pool's round robin. */
function pools(b: Builder, teams: string[], count: number): Map<string, string[]> {
  const ids = Array.from({ length: count }, (_, i) => poolName(i));
  const map = new Map(ids.map((p) => [p, [] as string[]]));
  teams.forEach((t, i) => {
    const lap = Math.floor(i / count);
    const at = i % count;
    map.get(ids[lap % 2 === 0 ? at : count - 1 - at]!)!.push(t);
  });
  const rounds = new Map(ids.map((p) => [p, roundRobin(map.get(p)!)]));
  const most = Math.max(0, ...[...rounds.values()].map((r) => r.length));
  for (let r = 0; r < most; r++) {
    for (const p of ids) {
      const pr = rounds.get(p)!;
      if (r >= pr.length) continue;
      for (const [a, c] of pr[r]!) {
        b.add({ stage: "pool", round: r + 1, label: count === 1 ? `Round ${r + 1}` : `Pool ${p} · Round ${r + 1}`, pool: p, a: entrantTeam(a), c: entrantTeam(c) });
      }
    }
  }
  return map;
}

/** Bracket seeds from pool finish, so pool-mates meet as late as possible. */
function crossSeed(map: Map<string, string[]>): Entrant[] {
  const ids = [...map.keys()];
  const deepest = Math.max(0, ...[...map.values()].map((p) => p.length));
  const out: Entrant[] = [];
  for (let rank = 1; rank <= deepest; rank++) {
    for (const p of rank % 2 === 1 ? ids : [...ids].reverse()) {
      if (map.get(p)!.length >= rank) out.push(entrantSource({ type: "pool", pool: p, rank }));
    }
  }
  return out;
}

function firstRound(entrants: Entrant[]): Array<Entrant | null> {
  return seedOrder(bracketSize(entrants.length)).map((seed) => (seed <= entrants.length ? entrants[seed - 1]! : null));
}

function singleElim(b: Builder, entrants: Entrant[]) {
  let current = firstRound(entrants);
  let round = 1;
  while (current.length > 1) {
    const matches = current.length / 2;
    const next: Array<Entrant | null> = [];
    for (let i = 0; i < matches; i++) {
      next.push(b.match({ stage: "winners", round, label: roundName(matches, round), a: current[2 * i]!, c: current[2 * i + 1]! }).winner);
    }
    current = next;
    round++;
  }
}

function placement(b: Builder, entrants: Entrant[]) {
  const crossover = entrants.length < bracketSize(entrants.length);
  let level: Array<[Array<Entrant | null>, number]> = [[firstRound(entrants), 1]];
  let round = 1;
  while (level.length > 0) {
    const next: Array<[Array<Entrant | null>, number]> = [];
    for (const [slots, place] of level) {
      if (slots.length < 2) continue;
      const matches = slots.length / 2;
      const name = roundName(matches, round);
      const label =
        place === 1
          ? round === 1 && crossover
            ? "Crossover"
            : name
          : matches === 1
            ? `${ordinal(place)} place`
            : `${ordinal(place)}–${ordinal(place + slots.length - 1)} ${name.toLowerCase()}`;
      const stage: GroupGameStage = round === 1 && crossover ? "crossover" : place === 1 ? "winners" : "placement";
      const results: Match[] = [];
      for (let i = 0; i < matches; i++) {
        results.push(b.match({ stage, round, label, a: slots[2 * i]!, c: slots[2 * i + 1]!, place: matches === 1 ? place : null }));
      }
      if (matches === 1) continue;
      next.push([results.map((r) => r.winner), place]);
      next.push([results.map((r) => r.loser), place + matches]);
    }
    level = next;
    round++;
  }
}

function doubleElim(b: Builder, entrants: Entrant[]) {
  let winners = firstRound(entrants);
  const droppedByRound: Array<Array<Entrant | null>> = [];
  let round = 1;
  while (winners.length > 1) {
    const matches = winners.length / 2;
    const results: Match[] = [];
    for (let i = 0; i < matches; i++) {
      results.push(b.match({ stage: "winners", round, label: `Winners' ${roundName(matches, round).toLowerCase()}`, a: winners[2 * i]!, c: winners[2 * i + 1]! }));
    }
    winners = results.map((r) => r.winner);
    droppedByRound.push(results.map((r) => r.loser));
    round++;
  }
  const wbChampion = winners[0]!;

  let lbRound = 0;
  const lbMatches = (sideA: Array<Entrant | null>, sideB: Array<Entrant | null>) => {
    lbRound++;
    return sideA.map((a, i) => b.match({ stage: "losers", round: lbRound, label: `Losers' round ${lbRound}`, a, c: sideB[i]! }).winner);
  };
  const halves = (xs: Array<Entrant | null>) =>
    lbMatches(
      xs.filter((_, i) => i % 2 === 0),
      xs.filter((_, i) => i % 2 === 1),
    );
  let losers = droppedByRound[0]!;
  if (losers.length > 1) losers = halves(losers);
  for (let r = 1; r < droppedByRound.length; r++) {
    const drop = droppedByRound[r]!;
    losers = lbMatches(losers, r % 2 === 1 ? [...drop].reverse() : drop);
    if (losers.length > 1) losers = halves(losers);
  }
  const lbChampion = losers[0]!;

  const finalRound = droppedByRound.length + 1;
  const grand = b.match({ stage: "grandFinal", round: finalRound, label: "Final", a: wbChampion, c: lbChampion });
  if (grand.gameId === null) return;
  b.add({
    stage: "reset",
    round: finalRound + 1,
    label: "Final (if needed)",
    a: entrantSource({ type: "loser", game: grand.gameId }),
    c: entrantSource({ type: "winner", game: grand.gameId }),
    ifNeeded: true,
  });
}

/** Games each game waits for: its source games, and for pool seeds every game of that pool. */
function dependencies(games: GroupGame[]): Map<string, Set<string>> {
  const byPool = new Map<string, Set<string>>();
  for (const g of games) {
    if (g.stage !== "pool") continue;
    const k = g.pool ?? "";
    if (!byPool.has(k)) byPool.set(k, new Set());
    byPool.get(k)!.add(g.id);
  }
  const from = (s: GroupSlotSource | null): string[] =>
    s === null ? [] : s.type === "pool" ? [...(byPool.get(s.pool) ?? [])] : [s.game];
  return new Map(games.map((g) => [g.id, new Set([...from(g.sourceA), ...from(g.sourceB)])]));
}

/** How many of [total] games each of [days] days gets; earlier days take the extra ones. */
function gamesPerDay(total: number, days: number): number[] {
  return Array.from({ length: days }, (_, d) => Math.floor(total / days) + (d < total % days ? 1 : 0));
}

const minute = 60_000;

function schedule(games: GroupGame[], s: GroupTournamentSettings): GroupSchedulePlan {
  const fields = Math.max(1, s.fields);
  const slotLength = (s.gameMinutes + s.breakMinutes) * minute;
  const deps = dependencies(games);
  const starts = [s.startsAt, ...s.laterDays].map((d) => Date.parse(d));
  const quotas = gamesPerDay(games.length, starts.length);
  const scheduled: GroupGame[] = [];
  const days: GroupScheduleDay[] = [];
  const earlier = new Set<string>();
  let next = 0;
  for (let d = 0; d < starts.length; d++) {
    const pending = games.slice(next, next + quotas[d]!);
    next += quotas[d]!;
    const slotOf = new Map<string, number>();
    let slot = 0;
    let last = -1;
    while (pending.length > 0) {
      const busy = new Set<string>();
      let used = 0;
      for (const g of [...pending]) {
        if (used === fields) break;
        const ready = [...deps.get(g.id)!].every((dep) => earlier.has(dep) || (slotOf.get(dep) ?? slot) < slot);
        const teams = [g.teamA, g.teamB].filter((t): t is string => t !== null);
        if (!ready || teams.some((t) => busy.has(t))) continue;
        for (const t of teams) busy.add(t);
        slotOf.set(g.id, slot);
        pending.splice(pending.indexOf(g), 1);
        used++;
        last = slot;
        scheduled.push({ ...g, order: scheduled.length, field: used, startsAt: new Date(starts[d]! + slotLength * slot).toISOString() });
      }
      slot++;
      if (slot > games.length * 2 + 2) throw new GroupScheduleError("These games can't be scheduled.");
    }
    for (const k of slotOf.keys()) earlier.add(k);
    const start = starts[d]!;
    days.push({
      startsAt: new Date(start).toISOString(),
      endsAt: new Date(last < 0 ? start : start + slotLength * last + s.gameMinutes * minute).toISOString(),
      games: quotas[d]!,
    });
  }
  return { games: scheduled, days, endsAt: days[days.length - 1]!.endsAt };
}

/** Every game for [teams] in seed order under [s], scheduled (scheduleFor). */
function scheduleFor(teams: string[], s: GroupTournamentSettings): GroupSchedulePlan {
  if (teams.length < 2) throw new GroupScheduleError("A tournament needs at least two teams.");
  const b = new Builder();
  const poolCount = Math.min(Math.max(s.poolCount, 1), Math.floor(teams.length / 2));
  switch (s.format) {
    case "roundRobin":
      pools(b, teams, 1);
      break;
    case "poolsSingleElim":
      singleElim(b, crossSeed(pools(b, teams, poolCount)));
      break;
    case "singleElim":
      singleElim(b, teams.map(entrantTeam));
      break;
    case "doubleElim":
      doubleElim(b, teams.map(entrantTeam));
      break;
    case "poolsPlacement":
      placement(b, poolCount === 1 ? teams.map(entrantTeam) : crossSeed(pools(b, teams, poolCount)));
      break;
  }
  return schedule(b.games, s);
}

/** Minutes the plan runs past [idealEndsAt]; 0 if it fits or has none. */
const overrunMinutes = (plan: GroupSchedulePlan, idealEndsAt: string | null) =>
  idealEndsAt === null ? 0 : Math.max(0, Math.trunc((Date.parse(plan.endsAt) - Date.parse(idealEndsAt)) / minute));

// ---- Engine: progress (progress.dart) --------------------------------------

/** A team to write into a waiting game once it's known. */
export interface GroupSlotFill {
  gameId: string;
  teamA: string | null;
  teamB: string | null;
}

const sourceGame = (s: GroupSlotSource | null) => (s && s.type !== "pool" ? s.game : null);

/**
 * Teams that move on once [finished] is final. The if-needed final only
 * gets its teams when the losers' bracket team (team B) won the first
 * final. With [overwrite] (an organizer correcting a score), filled slots
 * are replaced too.
 */
function fillsAfter(finished: GroupGame, games: GroupGame[], overwrite = false): GroupSlotFill[] {
  const winner = winnerOf(finished);
  const loser = loserOf(finished);
  if (winner === null || loser === null) return [];
  const resolve = (s: GroupSlotSource | null) =>
    s && s.type !== "pool" && s.game === finished.id ? (s.type === "winner" ? winner : loser) : null;
  const fill = (current: string | null, s: GroupSlotSource | null) => {
    const team = resolve(s);
    if (team === null || team === current) return null;
    return current === null || overwrite ? team : null;
  };
  const out: GroupSlotFill[] = [];
  for (const g of games) {
    if (g.id === finished.id || isDone(g)) continue;
    const a = fill(g.teamA, g.sourceA);
    const b = fill(g.teamB, g.sourceB);
    if (a === null && b === null) continue;
    if (g.stage === "reset" && finished.stage === "grandFinal" && winner !== finished.teamB) continue;
    out.push({ gameId: g.id, teamA: a, teamB: b });
  }
  return out;
}

/** Whether a game fed by [game]'s result has been played or reported. */
const laterGamesPlayed = (game: GroupGame, games: GroupGame[]) =>
  games.some((g) => g.status !== "scheduled" && [g.sourceA, g.sourceB].some((s) => sourceGame(s) === game.id));

/** Fills that should already have been written for finished games. */
const pendingFills = (games: GroupGame[]) => games.filter(isDone).flatMap((g) => fillsAfter(g, games));

/** Bracket seeds from pool standings once every pool is complete. */
function bracketSeeds(games: GroupGame[]): GroupSlotFill[] {
  const map = poolTeams(games);
  if (map.size === 0 || ![...map.keys()].every((p) => poolComplete(p, games))) return [];
  const ranked = new Map(
    [...map.entries()].map(([p, teams]) => [
      p,
      standings(
        teams,
        games.filter((g) => g.pool === p),
      ).map((s) => s.teamId),
    ]),
  );
  const resolve = (s: GroupSlotSource | null) => (s && s.type === "pool" ? (ranked.get(s.pool)?.[s.rank - 1] ?? null) : null);
  const out: GroupSlotFill[] = [];
  for (const g of games) {
    const a = g.teamA === null ? resolve(g.sourceA) : null;
    const b = g.teamB === null ? resolve(g.sourceB) : null;
    if (a !== null || b !== null) out.push({ gameId: g.id, teamA: a, teamB: b });
  }
  return out;
}

const awaitingSeeds = (games: GroupGame[]) =>
  games.some((g) => (g.teamA === null && g.sourceA?.type === "pool") || (g.teamB === null && g.sourceB?.type === "pool"));

/** Games still to be played; the if-needed final drops out once it isn't needed. */
function gamesToPlay(games: GroupGame[]): GroupGame[] {
  const grand = games.find((g) => g.stage === "grandFinal");
  const resetNeeded = !grand || !isDone(grand) ? true : winnerOf(grand) === grand.teamB;
  return games.filter((g) => !isDone(g) && !(g.ifNeeded && !resetNeeded));
}

const skippedGame = (game: GroupGame, games: GroupGame[]) => game.ifNeeded && !isDone(game) && !gamesToPlay(games).some((g) => g.id === game.id);

/** The winner once every game that needs playing is done. */
function championOf(format: GroupTournamentFormat, games: GroupGame[]): string | null {
  if (games.length === 0 || gamesToPlay(games).length > 0) return null;
  if (format === "roundRobin") {
    const pool = [...poolTeams(games).values()][0] ?? [];
    return standings(pool, games)[0]?.teamId ?? null;
  }
  const finalGame = games.find((g) => g.place === 1);
  if (finalGame) return winnerOf(finalGame);
  const reset = games.find((g) => g.stage === "reset");
  if (reset && isDone(reset)) return winnerOf(reset);
  const grand = games.find((g) => g.stage === "grandFinal");
  if (grand) return winnerOf(grand);
  const fed = new Set(games.flatMap((g) => [g.sourceA, g.sourceB].flatMap((s) => (s?.type === "winner" ? [s.game] : []))));
  const last = games.filter((g) => isBracket(g.stage) && !fed.has(g.id)).at(-1);
  return last ? winnerOf(last) : null;
}

/** Final places, best first, once every game is played. */
function placementsOf(format: GroupTournamentFormat, seeds: string[], games: GroupGame[]): string[] {
  if (games.length === 0 || gamesToPlay(games).length > 0) return [];
  const byPlace = new Map<number, string>();
  for (const g of games) {
    if (g.place == null || !isDone(g)) continue;
    byPlace.set(g.place, winnerOf(g)!);
    byPlace.set(g.place + 1, loserOf(g)!);
  }
  const placed = [...byPlace.keys()].sort((a, b) => a - b).map((p) => byPlace.get(p)!);
  if (placed.length === 0) {
    if (format === "roundRobin") {
      const pool = [...poolTeams(games).values()][0] ?? [];
      placed.push(...standings(pool, games).map((s) => s.teamId));
    } else {
      const champ = championOf(format, games);
      if (champ !== null) placed.push(champ);
    }
  }
  return [...placed, ...seeds.filter((t) => !placed.includes(t))];
}

/** Valid scores: whole numbers, no ties. */
function scoreError(a: number | null | undefined, b: number | null | undefined, max = 99): string | null {
  if (a == null || b == null || !Number.isInteger(a) || !Number.isInteger(b)) return "Enter both scores.";
  if (a < 0 || b < 0 || a > max || b > max) return `Scores go from 0 to ${max}.`;
  if (a === b) return "Games can't end in a tie.";
  return null;
}

/** Writes [fills] into [games] (a copy). */
function applyFills(games: GroupGame[], fills: GroupSlotFill[]): GroupGame[] {
  const byId = new Map(fills.map((f) => [f.gameId, f]));
  return games.map((g) => {
    const f = byId.get(g.id);
    return f ? { ...g, teamA: f.teamA ?? g.teamA, teamB: f.teamB ?? g.teamB } : g;
  });
}

// ---- Engine: team builder (team_builder.dart) ------------------------------

export interface GroupPlayer {
  uid: string;
  name: string;
}

function shuffle<T>(xs: T[], random: () => number): T[] {
  const out = [...xs];
  for (let i = out.length - 1; i > 0; i--) {
    const j = Math.floor(random() * (i + 1));
    [out[i], out[j]] = [out[j]!, out[i]!];
  }
  return out;
}

/** Deals [players] at random into [teams], evenly; each team with players gets a random captain. */
function dealPlayers(players: GroupPlayer[], teams: GroupTournamentTeam[], random: () => number = Math.random): GroupTournamentTeam[] {
  if (teams.length === 0) return [];
  const unique = shuffle([...new Map(players.map((p) => [p.uid, p])).values()], random);
  const rosters = teams.map(() => [] as GroupPlayer[]);
  unique.forEach((p, i) => rosters[i % teams.length]!.push(p));
  return teams.map((t, i) => ({
    ...t,
    captainId: rosters[i]![0]?.uid ?? null,
    playerIds: rosters[i]!.map((p) => p.uid),
    playerNames: Object.fromEntries(rosters[i]!.map((p) => [p.uid, p.name])),
  }));
}

/** [count] empty teams "Team n"; ids continue after any in [existing]. */
function blankTeams(count: number, existing: GroupTournamentTeam[] = []): GroupTournamentTeam[] {
  let next = existing.length + 1;
  const taken = new Set(existing.map((t) => t.id));
  const out: GroupTournamentTeam[] = [];
  for (let i = 0; i < count; i++) {
    while (taken.has(`team${next}`)) next++;
    const id = `team${next}`;
    taken.add(id);
    out.push({ id, name: `Team ${next++}`, captainId: null, playerIds: [], playerNames: {} });
  }
  return out;
}

/**
 * Moves [player] onto [teamId] (off any other team), or off every team
 * when null. A captain who moves stops being captain; a team left without
 * one gets its first player.
 */
function movePlayer(teams: GroupTournamentTeam[], player: GroupPlayer, teamId: string | null): GroupTournamentTeam[] {
  return teams.map((t) => {
    if (t.id === teamId && !t.playerIds.includes(player.uid)) {
      return {
        ...t,
        playerIds: [...t.playerIds, player.uid],
        playerNames: { ...t.playerNames, [player.uid]: player.name },
        captainId: t.captainId ?? player.uid,
      };
    }
    if (t.id !== teamId && t.playerIds.includes(player.uid)) {
      const ids = t.playerIds.filter((u) => u !== player.uid);
      const names = { ...t.playerNames };
      delete names[player.uid];
      return { ...t, playerIds: ids, playerNames: names, captainId: t.captainId === player.uid ? (ids[0] ?? null) : t.captainId };
    }
    return t;
  });
}

/** The app's tournament engine, for group tournaments. */
export const groupEngine = {
  poolName,
  poolTeams,
  poolComplete,
  standings,
  roundRobin,
  seedOrder,
  ordinal,
  suggestedPools,
  gamesPerDay,
  scheduleFor,
  overrunMinutes,
  fillsAfter,
  laterGamesPlayed,
  pendingFills,
  bracketSeeds,
  awaitingSeeds,
  gamesToPlay,
  skippedGame,
  championOf,
  placementsOf,
  scoreError,
  applyFills,
  dealPlayers,
  blankTeams,
  movePlayer,
  winnerOf,
  loserOf,
  isDone,
  hasTeams,
  isBracket,
};
