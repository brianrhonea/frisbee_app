// Team stats (teams/{id}/statsGames, statsTournaments; StatsGame,
// StatsTournament and StatSheet in the app's lib/domain/models/stats.dart).
// A game holds its points, lines and timeouts in one document, saved whole.
// The schemas port the statsGames and statsTournaments rules in
// firestore.rules, plus bounds on the nested shapes the rules never looked
// at, so a save stays under Firestore's 1 MiB document limit. The
// calculations, the tracker and its save scheduling are ports of the app's
// models and GameTrackerViewModel, so the website and the app agree.
import { z } from "zod";
import { isoDateTime } from "./dates.js";

// ---- Shapes ------------------------------------------------------------------

export const statKinds = [
  "pull",
  "pickup",
  "catch_",
  "goal",
  "throwaway",
  "drop",
  "handBlock",
  "breakup",
  "beat",
  "theirTurnover",
  "sub",
] as const;
export type StatKind = (typeof statKinds)[number];

export const statSides = ["offense", "defense"] as const;
export type StatSide = (typeof statSides)[number];
export const pointResults = ["weScored", "theyScored"] as const;
export type PointResult = (typeof pointResults)[number];

export const sideShort: Record<StatSide, string> = { offense: "O", defense: "D" };
export const flipSide = (s: StatSide): StatSide => (s === "offense" ? "defense" : "offense");

/** One tracked event within a point (StatAction.toMap: null ids left out, outOfBounds only when true). */
export interface StatAction {
  kind: StatKind;
  playerId?: string;
  throwerId?: string;
  subOutId?: string;
  hangTimeMs?: number;
  outOfBounds?: true;
}

/** A named set of seven players (StatLine). */
export interface StatLine {
  id: string;
  name: string;
  players: string[];
  side: StatSide | null;
}

export interface StatPoint {
  /** The seven who started it; empty for a point recorded only as an opponent score. */
  line: string[];
  startedOn: StatSide;
  actions: StatAction[];
  result: PointResult | null;
}

export interface GameTimeout {
  ours: boolean;
  /** 1 or 2. */
  half: number;
  /** Index of the point it was called during (or before, between points). */
  point: number;
  /** How many of that point's actions came before it. */
  action: number;
}

/** A game as the website handles it; [date] is ISO. */
export interface StatsGame {
  id: string;
  opponent: string;
  date: string;
  gameTo: number;
  tournamentId: string | null;
  eventId: string | null;
  points: StatPoint[];
  finished: boolean;
  lines: StatLine[];
  timeoutsPerHalf: number;
  timeouts: GameTimeout[];
}

/** A tournament folder; [startDate] is ISO. */
export interface StatsTournament {
  id: string;
  name: string;
  startDate: string;
  location: string;
  eventId: string | null;
  roster: string[];
  lines: StatLine[];
}

/** The roster spot a stat names (RosterPlayer; the API's RosterPlayer is the public card). */
export interface StatsPlayer {
  id: string;
  name: string;
  number: number | null;
  position: "handler" | "cutter" | "hybrid";
  userId: string | null;
  /** Admins only (rosterStatus). */
  paid?: boolean;
}

export const lineSize = 7;
/** Common "game to" targets (StatsGame.targets) and timeout allowances. */
export const gameToTargets = [7, 11, 13, 15, 17, 21] as const;
export const timeoutChoices = [0, 1, 2, 3, 4] as const;

/** The rules' limits, and the website's bounds on what the rules leave open. */
export const statsLimits = {
  opponent: 100,
  gameToMax: 50,
  refId: 100,
  points: 150,
  lines: 50,
  timeoutsPerHalfMax: 10,
  timeouts: 40,
  tournamentName: 100,
  location: 200,
  tournamentRoster: 200,
  // Not in the rules (they check only the lists' lengths):
  actionsPerPoint: 500,
  linePlayers: 30,
  lineName: 100,
  id: 128,
  hangTimeMs: 600_000,
  /** Points, lines and timeouts together, as JSON: well under 1 MiB. */
  gameBytes: 900_000,
  // Roster spots (match /roster/{playerId}).
  playerName: 80,
} as const;

// ---- Reading stored docs (the app's fromMap defaults) ----------------------------

const str = (v: unknown, d = "") => (typeof v === "string" ? v : d);
const num = (v: unknown, d: number) => (typeof v === "number" && Number.isFinite(v) ? Math.trunc(v) : d);
const list = (v: unknown): unknown[] => (Array.isArray(v) ? v : []);
const obj = (v: unknown): Record<string, unknown> => (v && typeof v === "object" && !Array.isArray(v) ? (v as Record<string, unknown>) : {});
const byName = <T extends string>(values: readonly T[], v: unknown, d: T): T => (values.includes(v as T) ? (v as T) : d);
const optStr = (v: unknown) => (typeof v === "string" ? v : null);
/** Date, ISO string or ms, as ISO (parseDate); now when missing. */
function isoOf(v: unknown): string {
  const d = v instanceof Date ? v : typeof v === "string" || typeof v === "number" ? new Date(v) : null;
  return d && !Number.isNaN(d.getTime()) ? d.toISOString() : new Date().toISOString();
}

export function statActionFrom(raw: unknown): StatAction {
  const m = obj(raw);
  const a: StatAction = { kind: byName(statKinds, m.kind, "catch_") };
  if (typeof m.playerId === "string") a.playerId = m.playerId;
  if (typeof m.throwerId === "string") a.throwerId = m.throwerId;
  if (typeof m.subOutId === "string") a.subOutId = m.subOutId;
  if (typeof m.hangTimeMs === "number" && Number.isFinite(m.hangTimeMs)) a.hangTimeMs = Math.trunc(m.hangTimeMs);
  if (m.outOfBounds === true) a.outOfBounds = true;
  return a;
}

export function statLineFrom(raw: unknown): StatLine {
  const m = obj(raw);
  return {
    id: str(m.id),
    name: str(m.name),
    players: list(m.players).map((p) => `${p}`),
    side: typeof m.side === "string" ? byName(statSides, m.side, "offense") : null,
  };
}

export function statPointFrom(raw: unknown): StatPoint {
  const m = obj(raw);
  return {
    line: list(m.line).map((p) => `${p}`),
    startedOn: byName(statSides, m.startedOn, "offense"),
    actions: list(m.actions).map(statActionFrom),
    result: typeof m.result === "string" ? byName(pointResults, m.result, "weScored") : null,
  };
}

export function gameTimeoutFrom(raw: unknown): GameTimeout {
  const m = obj(raw);
  return { ours: typeof m.ours === "boolean" ? m.ours : true, half: num(m.half, 1), point: num(m.point, 0), action: num(m.action, 0) };
}

/** A statsGames doc (Timestamps as ISO or Date) as the app reads it. */
export function statsGameFrom(id: string, raw: unknown): StatsGame {
  const m = obj(raw);
  return {
    id,
    opponent: str(m.opponent),
    date: isoOf(m.date),
    gameTo: num(m.gameTo, 15),
    tournamentId: optStr(m.tournamentId),
    eventId: optStr(m.eventId),
    points: list(m.points).map(statPointFrom),
    finished: typeof m.finished === "boolean" ? m.finished : false,
    lines: list(m.lines).map(statLineFrom),
    timeoutsPerHalf: num(m.timeoutsPerHalf, 2),
    timeouts: list(m.timeouts).map(gameTimeoutFrom),
  };
}

export function statsTournamentFrom(id: string, raw: unknown): StatsTournament {
  const m = obj(raw);
  return {
    id,
    name: str(m.name),
    startDate: isoOf(m.startDate),
    location: str(m.location),
    eventId: optStr(m.eventId),
    roster: list(m.roster).map((p) => `${p}`),
    lines: list(m.lines).map(statLineFrom),
  };
}

export function statsPlayerFrom(id: string, raw: unknown, status?: unknown): StatsPlayer {
  const m = obj(raw);
  return {
    id,
    name: str(m.name),
    number: typeof m.number === "number" && Number.isFinite(m.number) ? Math.trunc(m.number) : null,
    position: byName(["handler", "cutter", "hybrid"] as const, m.position, "hybrid"),
    userId: optStr(m.userId),
    paid: obj(status).paid === true,
  };
}

/**
 * Roster order: by number (no number last), then name, comparing code
 * units as the app does (RosterPlayer.compareRoster), not localeCompare.
 */
export function sortPlayers(players: StatsPlayer[]): StatsPlayer[] {
  return [...players].sort((a, b) => (a.number ?? 1000) - (b.number ?? 1000) || (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
}

// ---- Request schemas ------------------------------------------------------------------

const id = z.string().min(1).max(statsLimits.id);
/** A tournament or event id: validString(…, 100) in the rules; also one path segment. */
const refId = z
  .string()
  .min(1)
  .max(statsLimits.refId)
  .refine((s) => !s.includes("/"), "Invalid id.");
/** An ISO date (with Z or an offset) Firestore can store as a timestamp. */
const isoDate = isoDateTime("Give a date.");

export const statActionSchema = z
  .strictObject({
    kind: z.enum(statKinds),
    playerId: id.optional(),
    throwerId: id.optional(),
    subOutId: id.optional(),
    hangTimeMs: z.number().int().min(0).max(statsLimits.hangTimeMs).optional(),
    outOfBounds: z.boolean().optional(),
  })
  .transform((a): StatAction => {
    const out: StatAction = { kind: a.kind };
    if (a.playerId !== undefined) out.playerId = a.playerId;
    if (a.throwerId !== undefined) out.throwerId = a.throwerId;
    if (a.subOutId !== undefined) out.subOutId = a.subOutId;
    if (a.hangTimeMs !== undefined) out.hangTimeMs = a.hangTimeMs;
    if (a.outOfBounds) out.outOfBounds = true;
    return out;
  });

export const statLineSchema = z.strictObject({
  id,
  name: z.string().max(statsLimits.lineName),
  players: z.array(id).max(statsLimits.linePlayers),
  side: z.enum(statSides).nullable().default(null),
});

export const statPointSchema = z.strictObject({
  line: z.array(id).max(statsLimits.linePlayers),
  startedOn: z.enum(statSides),
  actions: z.array(statActionSchema).max(statsLimits.actionsPerPoint).default([]),
  result: z.enum(pointResults).nullable().default(null),
});

export const gameTimeoutSchema = z.strictObject({
  ours: z.boolean(),
  half: z.number().int().min(1).max(2),
  point: z.number().int().min(0).max(statsLimits.points),
  action: z.number().int().min(0).max(statsLimits.actionsPerPoint),
});

const linesSchema = z.array(statLineSchema).max(statsLimits.lines, `Keep at most ${statsLimits.lines} lines.`);

/**
 * `POST /v1/teams/:teamId/stats-games` and `PUT .../stats-games/:gameId`:
 * the whole game (StatsGame.toMap). Every key the rule's hasOnly lists but
 * updatedAt, which the API stamps.
 */
export const saveStatsGameSchema = z
  .strictObject({
    opponent: z.string().trim().min(1, "Name the opponent.").max(statsLimits.opponent, `Keep the opponent under ${statsLimits.opponent} characters.`),
    date: isoDate,
    gameTo: z.number().int().min(1).max(statsLimits.gameToMax),
    tournamentId: refId.nullable().default(null),
    eventId: refId.nullable().default(null),
    points: z.array(statPointSchema).max(statsLimits.points, `A game holds at most ${statsLimits.points} points.`).default([]),
    finished: z.boolean().default(false),
    lines: linesSchema.default([]),
    timeoutsPerHalf: z.number().int().min(0).max(statsLimits.timeoutsPerHalfMax).default(2),
    timeouts: z.array(gameTimeoutSchema).max(statsLimits.timeouts).default([]),
  })
  .refine(
    (g) => JSON.stringify([g.points, g.lines, g.timeouts]).length <= statsLimits.gameBytes,
    "This game is too big to save.",
  );
export type SaveStatsGameRequest = z.input<typeof saveStatsGameSchema>;
export type SaveStatsGameInput = z.output<typeof saveStatsGameSchema>;

/** `POST /v1/teams/:teamId/stats-tournaments` and `PUT .../:tournamentId` (StatsTournament.toMap). */
export const saveStatsTournamentSchema = z.strictObject({
  name: z.string().trim().min(1, "Name the tournament.").max(statsLimits.tournamentName, `Keep the name under ${statsLimits.tournamentName} characters.`),
  startDate: isoDate,
  location: z.string().max(statsLimits.location).default(""),
  eventId: refId.nullable().default(null),
  roster: z.array(id).max(statsLimits.tournamentRoster).default([]),
  lines: linesSchema.default([]),
});
export type SaveStatsTournamentRequest = z.input<typeof saveStatsTournamentSchema>;
export type SaveStatsTournamentInput = z.output<typeof saveStatsTournamentSchema>;

/**
 * `POST /v1/teams/:teamId/roster-players` and `PUT .../:playerId`, for
 * admins (RosterPlayer.toMap, and toStatusMap's paid when given).
 */
export const saveRosterPlayerSchema = z.strictObject({
  /** New spots only (a replay of the same id is a 409); the server mints one when absent. Refused on an edit that names another. */
  id: z
    .string()
    .regex(/^[A-Za-z0-9]{1,40}$/, "Invalid id.")
    .optional(),
  name: z.string().trim().min(1, "Enter a name.").max(statsLimits.playerName, `Keep the name under ${statsLimits.playerName} characters.`),
  number: z.number().int().min(0).max(99_999).nullable().default(null),
  position: z.enum(["handler", "cutter", "hybrid"]).default("hybrid"),
  userId: id.nullable().default(null),
  paid: z.boolean().optional(),
});
export type SaveRosterPlayerRequest = z.input<typeof saveRosterPlayerSchema>;

/** `PUT /v1/teams/:teamId/roster-players/:playerId/link`: claim a spot (your uid) or let go of yours (null). */
export const linkRosterPlayerSchema = z.strictObject({ userId: id.nullable() });

export interface CreatedId {
  id: string;
}

/** The PUT/POST body for [g] (everything but the id). */
export function statsGameBody(g: StatsGame): SaveStatsGameRequest {
  return {
    opponent: g.opponent,
    date: g.date,
    gameTo: g.gameTo,
    tournamentId: g.tournamentId,
    eventId: g.eventId,
    points: g.points.map((p) => ({ line: p.line, startedOn: p.startedOn, actions: p.actions, result: p.result })),
    finished: g.finished,
    lines: g.lines,
    timeoutsPerHalf: g.timeoutsPerHalf,
    timeouts: g.timeouts,
  };
}

export function statsTournamentBody(t: StatsTournament): SaveStatsTournamentRequest {
  return { name: t.name, startDate: t.startDate, location: t.location, eventId: t.eventId, roster: t.roster, lines: t.lines };
}

// ---- Point and game calculations ----------------------------------------------

/** Whether [a] hands possession to the other team. */
export const turnsOver = (a: StatAction) =>
  a.kind === "throwaway" || a.kind === "drop" || a.kind === "handBlock" || a.kind === "breakup" || a.kind === "theirTurnover";

/** Who's on the field now, after substitutions. */
export function onField(p: StatPoint): string[] {
  const field = [...p.line];
  for (const a of p.actions) {
    if (a.kind !== "sub") continue;
    const i = field.indexOf(a.subOutId ?? "");
    if (i >= 0 && a.playerId) field[i] = a.playerId;
  }
  return field;
}

/** Everyone who played any part of the point. */
export function played(p: StatPoint): Set<string> {
  const s = new Set(p.line);
  for (const a of p.actions) if (a.kind === "sub" && a.playerId) s.add(a.playerId);
  return s;
}

/** The side we're on after replaying the point's actions. */
export function pointSide(p: StatPoint): StatSide {
  let s = p.startedOn;
  for (const a of p.actions) if (turnsOver(a)) s = flipSide(s);
  return s;
}

/** Who holds the disc, if we're on O and someone has it. */
export function holder(p: StatPoint): string | null {
  let h: string | null = null;
  for (const a of p.actions) {
    if (a.kind === "pickup" || a.kind === "catch_" || a.kind === "goal") h = a.playerId ?? null;
    // An injured holder subs out; the sub takes the disc, no catch.
    else if (a.kind === "sub" && h !== null && a.subOutId === h) h = a.playerId ?? null;
    else if (turnsOver(a)) h = null;
  }
  return h;
}

export const hasPull = (p: StatPoint) => p.actions.some((a) => a.kind === "pull");

export const ourScore = (g: Pick<StatsGame, "points">) => g.points.filter((p) => p.result === "weScored").length;
export const theirScore = (g: Pick<StatsGame, "points">) => g.points.filter((p) => p.result === "theyScored").length;
export const reachedGamePoint = (g: StatsGame) => ourScore(g) >= g.gameTo || theirScore(g) >= g.gameTo;
/** No more stats can be recorded. */
export const gameOver = (g: StatsGame) => g.finished || reachedGamePoint(g);
/** Halftime comes when either team reaches this, e.g. 8 in a game to 15. */
export const halfAt = (g: Pick<StatsGame, "gameTo">) => Math.floor((g.gameTo + 1) / 2);

/** Index of the point that took the game to halftime, if played. */
export function halftimePoint(g: StatsGame): number | null {
  let us = 0;
  let them = 0;
  const at = halfAt(g);
  for (let i = 0; i < g.points.length; i++) {
    if (g.points[i].result === "weScored") us++;
    if (g.points[i].result === "theyScored") them++;
    if (us >= at || them >= at) return i;
  }
  return null;
}

export const currentHalf = (g: StatsGame) => (halftimePoint(g) === null ? 1 : 2);

export function timeoutsLeft(g: StatsGame, ours: boolean): number {
  const half = currentHalf(g);
  const used = g.timeouts.filter((t) => t.ours === ours && t.half === half).length;
  return Math.min(Math.max(g.timeoutsPerHalf - used, 0), g.timeoutsPerHalf);
}

/** Null while in play or tied. */
export function gameWon(g: StatsGame): boolean | null {
  const us = ourScore(g);
  const them = theirScore(g);
  return !gameOver(g) || us === them ? null : us > them;
}

/** Same name, side and players, in any order (StatLine.key). */
export const lineKey = (l: StatLine) => `${l.name}|${l.side ?? "null"}|${[...l.players].sort().join(",")}`;

/** Where saved lines can be imported from: a tournament or a game. */
export interface LineSource {
  id: string;
  name: string;
  lines: StatLine[];
  eventId: string | null;
}

/** Every tournament and standalone game with lines, newest first (LineSource.from). */
export function lineSources(tournaments: StatsTournament[], games: StatsGame[]): LineSource[] {
  const dated: Array<[string, LineSource]> = [
    ...tournaments
      .filter((t) => t.lines.length > 0)
      .map((t): [string, LineSource] => [t.startDate, { id: t.id, name: t.name, lines: t.lines, eventId: t.eventId }]),
    ...games
      .filter((g) => g.tournamentId === null && g.lines.length > 0)
      .map((g): [string, LineSource] => [g.date, { id: g.id, name: `vs ${g.opponent}`, lines: g.lines, eventId: g.eventId }]),
  ];
  // Stable, as Dart's List.sort is not guaranteed to be; newest first.
  return dated.sort((a, b) => Date.parse(b[0]) - Date.parse(a[0])).map(([, s]) => s);
}

/** Lines already built for [eventId], without duplicates (LineSource.forEvent). */
export function linesForEvent(eventId: string | null | undefined, sources: LineSource[]): StatLine[] {
  if (!eventId) return [];
  const seen = new Set<string>();
  const out: StatLine[] = [];
  for (const s of sources) {
    if (s.eventId !== eventId) continue;
    for (const l of s.lines) {
      const k = lineKey(l);
      if (!seen.has(k)) {
        seen.add(k);
        out.push(l);
      }
    }
  }
  return out;
}

// ---- Stat sheet ---------------------------------------------------------------------------

/** What one player did in one point, for the O and D ratings (Involvement). */
export class Involvement {
  goals = 0;
  assists = 0;
  touches = 0;
  handBlocks = 0;
  breakups = 0;
  throwaways = 0;
  drops = 0;

  static readonly scoredCredit = 1.0;
  static readonly goalBonus = 0.5;
  static readonly assistBonus = 0.5;
  static readonly touchBonus = 0.1;
  static readonly handBlockBonus = 1.0;
  static readonly breakupBonus = 0.5;
  static readonly turnoverPenalty = 0.75;

  /** 1 plus bonuses if we scored, else nothing; each throwaway or drop costs 0.75 either way. */
  credit(scored: boolean): number {
    const penalty = (this.throwaways + this.drops) * Involvement.turnoverPenalty;
    if (!scored) return -penalty;
    return (
      Involvement.scoredCredit +
      this.goals * Involvement.goalBonus +
      this.assists * Involvement.assistBonus +
      this.touches * Involvement.touchBonus +
      this.handBlocks * Involvement.handBlockBonus +
      this.breakups * Involvement.breakupBonus -
      penalty
    );
  }
}

/** Running totals for one player (PlayerStats). */
export class PlayerStats {
  pointsO = 0;
  pointsD = 0;
  pickups = 0;
  catches = 0;
  goals = 0;
  assists = 0;
  completions = 0;
  throwaways = 0;
  drops = 0;
  handBlocks = 0;
  breakups = 0;
  beats = 0;
  pulls = 0;
  pullsOutOfBounds = 0;
  timedPulls = 0;
  hangTimeMs = 0;
  finishedO = 0;
  holds = 0;
  finishedD = 0;
  breaks = 0;
  oCredit = 0;
  dCredit = 0;

  constructor(readonly playerId: string) {}

  get pointsPlayed() {
    return this.pointsO + this.pointsD;
  }
  get oEfficiency(): number | null {
    return this.finishedO === 0 ? null : this.holds / this.finishedO;
  }
  get dEfficiency(): number | null {
    return this.finishedD === 0 ? null : this.breaks / this.finishedD;
  }
  get oRating(): number | null {
    return this.finishedO === 0 ? null : this.oCredit / this.finishedO;
  }
  get dRating(): number | null {
    return this.finishedD === 0 ? null : this.dCredit / this.finishedD;
  }
  get touches() {
    return this.pickups + this.catches + this.goals;
  }
  get throws() {
    return this.completions + this.throwaways;
  }
  get catchPct(): number | null {
    const caught = this.catches + this.goals;
    const targets = caught + this.drops;
    return targets === 0 ? null : caught / targets;
  }
  get completionPct(): number | null {
    return this.throws === 0 ? null : this.completions / this.throws;
  }
  /** Seconds. */
  get avgHangTime(): number | null {
    return this.timedPulls === 0 ? null : this.hangTimeMs / this.timedPulls / 1000;
  }
  /** Goal and assist +1, hand block +2, breakup +1; −1 per throwaway, drop or getting beat. */
  get plusMinus() {
    return this.goals + this.assists + 2 * this.handBlocks + this.breakups - this.throwaways - this.drops - this.beats;
  }
}

export class TeamEfficiency {
  oPoints = 0;
  holds = 0;
  dPoints = 0;
  breaks = 0;
  get oEfficiency(): number | null {
    return this.oPoints === 0 ? null : this.holds / this.oPoints;
  }
  get breakRate(): number | null {
    return this.dPoints === 0 ? null : this.breaks / this.dPoints;
  }
}

export interface StatSheet {
  /** Player id → stats, for everyone who played or recorded a stat, in first-seen order. */
  players: Map<string, PlayerStats>;
  team: TeamEfficiency;
}

/** Per-player stats from tracked points (StatSheet.fromPoints). */
export function statSheet(points: Iterable<StatPoint>): StatSheet {
  const m = new Map<string, PlayerStats>();
  const team = new TeamEfficiency();
  const p = (id: string) => {
    let s = m.get(id);
    if (!s) m.set(id, (s = new PlayerStats(id)));
    return s;
  };
  for (const point of points) {
    const onO = point.startedOn === "offense";
    const who = played(point);
    for (const id of who) onO ? p(id).pointsO++ : p(id).pointsD++;
    const inv = new Map<string, Involvement>();
    const i = (id: string) => {
      let x = inv.get(id);
      if (!x) inv.set(id, (x = new Involvement()));
      return x;
    };
    for (const a of point.actions) {
      const id = a.playerId;
      if (id === undefined) continue;
      switch (a.kind) {
        case "pickup":
        case "catch_":
          i(id).touches++;
          break;
        case "goal":
          i(id).touches += 1;
          i(id).goals += 1;
          if (a.throwerId !== undefined) i(a.throwerId).assists++;
          break;
        case "handBlock":
          i(id).handBlocks++;
          break;
        case "breakup":
          i(id).breakups++;
          break;
        case "throwaway":
          i(id).throwaways++;
          break;
        case "drop":
          i(id).drops++;
          break;
        default:
          break;
      }
    }
    if (point.result !== null) {
      const scored = point.result === "weScored";
      if (onO) {
        team.oPoints++;
        if (scored) team.holds++;
      } else {
        team.dPoints++;
        if (scored) team.breaks++;
      }
      for (const id of who) {
        const s = p(id);
        const credit = (inv.get(id) ?? new Involvement()).credit(scored);
        if (onO) {
          s.finishedO++;
          if (scored) s.holds++;
          s.oCredit += credit;
        } else {
          s.finishedD++;
          if (scored) s.breaks++;
          s.dCredit += credit;
        }
      }
    }
    for (const a of point.actions) {
      const id = a.playerId;
      const thrower = a.throwerId;
      switch (a.kind) {
        case "pull": {
          if (id === undefined) break;
          const s = p(id);
          s.pulls++;
          if (a.outOfBounds) s.pullsOutOfBounds++;
          if (a.hangTimeMs !== undefined) {
            s.timedPulls++;
            s.hangTimeMs += a.hangTimeMs;
          }
          break;
        }
        case "pickup":
          if (id !== undefined) p(id).pickups++;
          break;
        case "catch_":
          if (id !== undefined) p(id).catches++;
          if (thrower !== undefined) p(thrower).completions++;
          break;
        case "goal":
          if (id !== undefined) p(id).goals++;
          if (thrower !== undefined) {
            const t = p(thrower);
            t.assists++;
            t.completions++;
          }
          break;
        case "throwaway":
          if (id !== undefined) p(id).throwaways++;
          break;
        case "drop":
          // The throw was on target, so the thrower isn't charged.
          if (id !== undefined) p(id).drops++;
          if (thrower !== undefined) p(thrower).completions++;
          break;
        case "handBlock":
          if (id !== undefined) p(id).handBlocks++;
          break;
        case "breakup":
          if (id !== undefined) p(id).breakups++;
          break;
        case "beat":
          if (id !== undefined) p(id).beats++;
          break;
        default:
          break;
      }
    }
  }
  return { players: m, team };
}

export const statSheetOfGames = (games: StatsGame[]) => statSheet(games.flatMap((g) => g.points));

/** Highest +/- first (StatSheet.ranked; stable). */
export const ranked = (s: StatSheet) => [...s.players.values()].sort((a, b) => b.plusMinus - a.plusMinus);

/** A column of the stat table (StatSheetTable._columns). */
export interface StatColumn {
  label: string;
  tooltip: string;
  value: (p: PlayerStats) => number | null;
  pct: boolean;
}

const rating = (r: number | null) => (r === null ? null : Math.round(r * 100));

export const statColumns: StatColumn[] = [
  { label: "+/-", tooltip: "Score", value: (p) => p.plusMinus, pct: false },
  { label: "O%", tooltip: "O efficiency: share of their O points we scored", value: (p) => p.oEfficiency, pct: true },
  {
    label: "ORTG",
    tooltip: "O rating: O efficiency scaled for involvement in scores, minus turnovers (100 = held every point)",
    value: (p) => rating(p.oRating),
    pct: false,
  },
  { label: "BRK%", tooltip: "D efficiency: share of their D points we broke", value: (p) => p.dEfficiency, pct: true },
  {
    label: "DRTG",
    tooltip: "D rating: break rate scaled for involvement in breaks, minus turnovers (100 = broke every point)",
    value: (p) => rating(p.dRating),
    pct: false,
  },
  { label: "PTS", tooltip: "Points played", value: (p) => p.pointsPlayed, pct: false },
  { label: "O", tooltip: "O points", value: (p) => p.pointsO, pct: false },
  { label: "D", tooltip: "D points", value: (p) => p.pointsD, pct: false },
  { label: "TCH", tooltip: "Touches", value: (p) => p.touches, pct: false },
  { label: "G", tooltip: "Goals", value: (p) => p.goals, pct: false },
  { label: "A", tooltip: "Assists", value: (p) => p.assists, pct: false },
  { label: "CMP%", tooltip: "Completion %", value: (p) => p.completionPct, pct: true },
  { label: "CTH%", tooltip: "Catch %", value: (p) => p.catchPct, pct: true },
  { label: "TA", tooltip: "Throwaways", value: (p) => p.throwaways, pct: false },
  { label: "DRP", tooltip: "Drops", value: (p) => p.drops, pct: false },
  { label: "HB", tooltip: "Hand blocks", value: (p) => p.handBlocks, pct: false },
  { label: "BU", tooltip: "Pass breakups", value: (p) => p.breakups, pct: false },
  { label: "BEAT", tooltip: "Got beat", value: (p) => p.beats, pct: false },
  { label: "PUL", tooltip: "Pulls", value: (p) => p.pulls, pct: false },
  { label: "OB", tooltip: "Pulls out of bounds", value: (p) => p.pullsOutOfBounds, pct: false },
  { label: "HANG", tooltip: "Average pull hang time (s)", value: (p) => p.avgHangTime, pct: false },
];

/** A cell as the app shows it: "–" for none, whole percents, one decimal for fractions. */
export function formatStat(c: StatColumn, p: PlayerStats): string {
  const v = c.value(p);
  if (v === null) return "–";
  if (c.pct) return `${Math.round(v * 100)}%`;
  return Number.isInteger(v) && c.label !== "HANG" ? `${v}` : v.toFixed(1);
}

// ---- Saving: what can wait (GameTrackerViewModel._isMilestone) -----------------------------

const restKey = (g: StatsGame) => JSON.stringify({ ...statsGameBody(g), points: [] });

/**
 * Changes worth saving at once: a point starting or ending, the game
 * ending, anything that isn't a play added to the current point (undo,
 * settings, lines). Only a longer action list on the same last point waits.
 */
export function isMilestone(before: StatsGame, after: StatsGame): boolean {
  if (before.finished !== after.finished) return true;
  const a = before.points;
  const b = after.points;
  if (a.length !== b.length) return true;
  if (b.length === 0) return a !== b;
  if (a[a.length - 1].result !== b[b.length - 1].result) return true;
  if (b[b.length - 1].actions.length <= a[a.length - 1].actions.length) return true;
  return restKey(before) !== restKey(after);
}

/** Timers, injectable for tests. */
export interface Clock {
  now(): number;
  setTimeout(fn: () => void, ms: number): unknown;
  clearTimeout(handle: unknown): void;
}

/** The host's timers (browser or Node); shared builds without DOM or Node types. */
const timers = globalThis as unknown as { setTimeout(fn: () => void, ms: number): unknown; clearTimeout(h: unknown): void };
export const realClock: Clock = {
  now: () => Date.now(),
  setTimeout: (fn, ms) => timers.setTimeout(fn, ms),
  clearTimeout: (h) => timers.clearTimeout(h),
};

export interface SaveTimings {
  /** How long plays within a point wait to be saved together (the app's saveDelay). */
  delayMs: number;
  /** Least time between two saves' starts, whatever they are: the hard cap on the write rate. */
  minGapMs: number;
  /** First wait after a failed save; doubles up to [maxBackoffMs]. */
  backoffMs: number;
  maxBackoffMs: number;
}

/** 3 s like the app; at most one save a second; retries from 2 s to 30 s. */
export const trackerSaveTimings: SaveTimings = { delayMs: 3000, minGapMs: 1000, backoffMs: 2000, maxBackoffMs: 30_000 };

/**
 * Sends the latest state of one document, in order, one request at a time.
 * [schedule] with urgent=true is a milestone (sent as soon as the gap
 * allows); urgent=false waits up to delayMs, and the wait isn't reset by
 * later changes, as the app's timer isn't. Whatever is newest when a send
 * starts is what goes; a failure keeps it pending and retries with backoff.
 */
export class SaveQueue<T> {
  private pending: T | null = null;
  private inFlight = false;
  private timer: unknown = null;
  private dueAt = Infinity;
  private lastStart = -Infinity;
  private failures = 0;
  private stopped = false;

  constructor(
    private readonly send: (value: T) => Promise<void>,
    private readonly onResult: (error: unknown | null) => void = () => undefined,
    private readonly timings: SaveTimings = trackerSaveTimings,
    private readonly clock: Clock = realClock,
  ) {}

  get dirty() {
    return this.pending !== null || this.inFlight;
  }

  schedule(value: T, urgent: boolean) {
    if (this.stopped) return;
    this.pending = value;
    const now = this.clock.now();
    const due = urgent ? now : this.timer === null && this.dueAt === Infinity ? now + this.timings.delayMs : this.dueAt;
    this.arm(Math.min(due, this.dueAt));
  }

  /** Sends what's pending now, gap permitting (the app's flush on dispose). */
  flush() {
    if (this.pending !== null) this.arm(this.clock.now());
  }

  /** Stops sending (after the page is gone). */
  stop() {
    this.stopped = true;
    if (this.timer !== null) this.clock.clearTimeout(this.timer);
    this.timer = null;
  }

  private arm(due: number) {
    if (this.inFlight) {
      // Sent when the request in flight answers.
      this.dueAt = Math.min(this.dueAt, due);
      return;
    }
    const at = Math.max(due, this.lastStart + this.timings.minGapMs);
    if (this.timer !== null) {
      if (at >= this.dueAt) return;
      this.clock.clearTimeout(this.timer);
    }
    this.dueAt = at;
    this.timer = this.clock.setTimeout(() => this.fire(), Math.max(0, at - this.clock.now()));
  }

  private async fire() {
    this.timer = null;
    this.dueAt = Infinity;
    const value = this.pending;
    if (value === null || this.stopped) return;
    this.pending = null;
    this.inFlight = true;
    this.lastStart = this.clock.now();
    let error: unknown = null;
    try {
      await this.send(value);
      this.failures = 0;
    } catch (e) {
      error = e;
      this.failures++;
      // Keep it unless something newer came in meanwhile.
      if (this.pending === null) this.pending = value;
    }
    this.inFlight = false;
    this.onResult(error);
    if (this.stopped || this.pending === null) {
      this.dueAt = Infinity;
      return;
    }
    const wait = error
      ? Math.min(this.timings.backoffMs * 2 ** (this.failures - 1), this.timings.maxBackoffMs)
      : 0;
    const due = this.dueAt === Infinity ? this.clock.now() : this.dueAt;
    this.dueAt = Infinity;
    this.arm(Math.max(due, this.clock.now() + wait));
  }
}
