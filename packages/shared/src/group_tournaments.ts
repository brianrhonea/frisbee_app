// A community's own tournaments (teams/{groupId}/groupTournaments/{id} and
// its games), GroupTournament and GroupGame in the app's
// lib/domain/models/group_tournament.dart, with the app's tournament
// engine (lib/domain/tournament_engine: generator, progress, standings,
// team_builder) ported for the group tournament slice. Dates are ISO
// strings here; the API stores them as timestamps.
//
// The engine is tournament_engine.ts's; its functions are gathered in one
// object (groupEngine), with scheduleFor adapted to ISO-string dates.
import { z } from "zod";
import { clean } from "./word_filter.js";
import {
  awaitingSeeds,
  bracketSeeds,
  championOf,
  type EngineGameOf,
  scheduleFor as engineScheduleFor,
  fillsAfter,
  type GameStage,
  gameStages,
  gameStatuses,
  gamesPerDay,
  gamesToPlay,
  hasTeams,
  isBracketStage,
  isDone,
  laterGamesPlayed,
  loserOf,
  ordinal,
  pendingFills,
  placementsOf,
  poolComplete,
  poolName,
  poolTeams,
  roundRobin,
  ScheduleError,
  type ScoreReport,
  scoreError,
  scoringModes,
  seedOrder,
  skippedGame,
  type SlotFill,
  type SlotSource,
  type Standing,
  standings,
  suggestedPools,
  tournamentFormatLabels,
  tournamentFormats,
  winnerOf,
} from "./tournament_engine.js";

// ---- Model -------------------------------------------------------------------

export const groupTournamentFormats = tournamentFormats;
export type GroupTournamentFormat = (typeof groupTournamentFormats)[number];

/** TournamentFormat's label and summary. */
export const groupTournamentFormatInfo = tournamentFormatLabels;
export const groupFormatHasPools = (f: GroupTournamentFormat) => f === "roundRobin" || f === "poolsSingleElim" || f === "poolsPlacement";
export const groupFormatHasBracket = (f: GroupTournamentFormat) => f !== "roundRobin";

export const groupTournamentStatuses = ["setup", "scheduled", "done"] as const;
export type GroupTournamentStatus = (typeof groupTournamentStatuses)[number];
export const groupTournamentStatusLabels: Record<GroupTournamentStatus, string> = {
  setup: "Setting up",
  scheduled: "Scheduled",
  done: "Finished",
};

export const groupScoringModes = scoringModes;
export type GroupScoringMode = (typeof groupScoringModes)[number];

export const groupGameStages = gameStages;
export type GroupGameStage = GameStage;
export const groupGameStageLabels: Record<GroupGameStage, string> = {
  pool: "Pool",
  winners: "Bracket",
  losers: "Losers' bracket",
  grandFinal: "Final",
  reset: "Final (if needed)",
  crossover: "Crossover",
  placement: "Placement",
};
export const groupGameStatuses = gameStatuses;
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

export type GroupSlotSource = SlotSource;
export type GroupScoreReport = ScoreReport;

/** GroupGame.toMap (with its id), dates as ISO strings. */
export type GroupGame = EngineGameOf<string>;

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
  name: clean(z.string().trim().min(1, "Give every team a name.").max(groupTournamentLimits.teamName, "Keep team names under 40 characters.")),
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
    name: clean(z.string().trim().min(1, "Give the tournament a name.").max(groupTournamentLimits.name, "Keep the name under 100 characters.")),
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

// ---- Engine (tournament_engine.ts) ---------------------------------------
//
// The same engine as hosted tournaments; only scheduling needs an adapter,
// since group games hold their dates as ISO strings.

export type GroupStanding = Standing;
export const GroupScheduleError = ScheduleError;
export type GroupScheduleError = ScheduleError;

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

const minute = 60_000;
const iso = (d: Date) => d.toISOString();

/** Every game for [teams] in seed order under [s], scheduled (scheduleFor). */
function scheduleFor(teams: string[], s: GroupTournamentSettings): GroupSchedulePlan {
  const plan = engineScheduleFor(teams, {
    ...s,
    startsAt: new Date(s.startsAt),
    idealEndsAt: s.idealEndsAt === null ? null : new Date(s.idealEndsAt),
    laterDays: s.laterDays.map((d) => new Date(d)),
  });
  const days = plan.days.map((d) => ({ startsAt: iso(d.startsAt), endsAt: iso(d.endsAt), games: d.games }));
  return {
    games: plan.games.map((g) => ({ ...g, startsAt: g.startsAt === null ? null : iso(g.startsAt), place: g.place ?? null })),
    days,
    endsAt: days[days.length - 1]!.endsAt,
  };
}

/** Minutes the plan runs past [idealEndsAt]; 0 if it fits or has none. */
const overrunMinutes = (plan: GroupSchedulePlan, idealEndsAt: string | null) =>
  idealEndsAt === null ? 0 : Math.max(0, Math.trunc((Date.parse(plan.endsAt) - Date.parse(idealEndsAt)) / minute));

/** A team to write into a waiting game once it's known. */
export type GroupSlotFill = SlotFill;

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
  isBracket: isBracketStage,
};
