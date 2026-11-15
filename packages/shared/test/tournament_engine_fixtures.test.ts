// The app's tournament engine (apps/mobile/lib/domain/tournament_engine)
// against both TypeScript ports, tournament_engine.ts (hosted tournaments
// and leagues) and group_tournaments.ts's groupEngine, on the vectors in
// fixtures/tournament_engine (written by
// apps/mobile/test/shared_fixtures/tournament_engine_fixtures_test.dart).
import { describe, expect, it } from "vitest";
import {
  awaitingSeeds,
  bracketSeeds,
  byesIn,
  championOf,
  type EngineGame,
  engineGame,
  engineSeason,
  engineSettings,
  fillsAfter,
  gamesPerDay,
  gamesToPlay,
  groupEngine,
  laterGamesPlayed,
  ordinal,
  pendingFills,
  placementsOf,
  poolName,
  poolTeams,
  readGroupGame,
  readGroupSettings,
  roundRobin,
  ScheduleError,
  scheduleFor,
  scoreError,
  seasonFor,
  seasonNights,
  seedOrder,
  skippedGame,
  standings,
  suggestedFormat,
  suggestedPools,
  type TournamentFormat,
} from "../src/index.js";
import { fixture, localIso } from "./shared_fixtures.js";

type Json = Record<string, unknown>;
interface Fill {
  gameId: string;
  teamA: string | null;
  teamB: string | null;
}

/** A game as the app's GroupGame.toMap writes it, with its id. */
function gameJson(g: { startsAt: Date | string | null; place?: number | null } & Record<string, unknown>): Json {
  const { place, ...rest } = g;
  return {
    id: g.id,
    order: g.order,
    stage: g.stage,
    round: g.round,
    label: g.label,
    pool: rest.pool,
    field: g.field,
    startsAt: localIso(g.startsAt),
    teamA: g.teamA,
    teamB: g.teamB,
    sourceA: g.sourceA,
    sourceB: g.sourceB,
    status: g.status,
    scoreA: g.scoreA,
    scoreB: g.scoreB,
    report: g.report,
    ifNeeded: g.ifNeeded,
    ...(place != null ? { place } : {}),
  };
}

const planJson = (p: { games: never[] | unknown[]; days: Array<{ startsAt: Date | string; endsAt: Date | string; games: number }> }) => ({
  games: (p.games as Parameters<typeof gameJson>[0][]).map(gameJson),
  days: p.days.map((d) => ({ startsAt: localIso(d.startsAt), endsAt: localIso(d.endsAt), games: d.games })),
});

/** The engine functions the play-through uses; both ports provide them. */
interface Engine<G> {
  fillsAfter(finished: G, games: G[]): Fill[];
  bracketSeeds(games: G[]): Fill[];
  awaitingSeeds(games: G[]): boolean;
  gamesToPlay(games: G[]): G[];
  skippedGame(game: G, games: G[]): boolean;
  laterGamesPlayed(game: G, games: G[]): boolean;
  pendingFills(games: G[]): Fill[];
  championOf(format: TournamentFormat, games: G[]): string | null;
  placementsOf(format: TournamentFormat, seeds: string[], games: G[]): string[];
  poolTeams(games: G[]): Map<string, string[]>;
  standings(teamIds: string[], games: G[]): Array<{ teamId: string }>;
}

type PlayGame = { id: string; order: number; pool: string | null; teamA: string | null; teamB: string | null; status: string; scoreA: number | null; scoreB: number | null };

const hostedEngine: Engine<EngineGame> = {
  fillsAfter: (f, g) => fillsAfter(f, g),
  bracketSeeds,
  awaitingSeeds,
  gamesToPlay,
  skippedGame,
  laterGamesPlayed,
  pendingFills,
  championOf,
  placementsOf,
  poolTeams,
  standings: (t, g) => standings(t, g),
};
const groupPlay = groupEngine as unknown as Engine<ReturnType<typeof readGroupGame>>;

/** The same play-through as the Dart test (see schedules.json's "about"). */
function playThrough<G extends PlayGame>(e: Engine<G>, format: TournamentFormat, seeds: string[], start: G[]): Json {
  let games = [...start];
  const steps: Json[] = [];
  const awaiting = e.awaitingSeeds(games);
  for (let guard = 0; guard < 500; guard++) {
    const playable = e
      .gamesToPlay(games)
      .filter((g) => g.teamA != null && g.teamB != null)
      .sort((a, b) => a.order - b.order);
    if (playable.length === 0) break;
    const g = playable[0]!;
    const upset = g.order % 3 === 2;
    const aWins = seeds.indexOf(g.teamA!) < seeds.indexOf(g.teamB!) !== upset;
    const low = (g.order * 5) % 12;
    const done = { ...g, status: "done", scoreA: aWins ? 13 : low, scoreB: aWins ? low : 13 };
    games = games.map((x) => (x.id === g.id ? done : x));
    const fills = [...e.fillsAfter(done, games), ...e.bracketSeeds(games)];
    steps.push({ game: g.id, scoreA: done.scoreA, scoreB: done.scoreB, fills });
    for (const f of fills) {
      games = games.map((x) => (x.id === f.gameId ? { ...x, teamA: f.teamA ?? x.teamA, teamB: f.teamB ?? x.teamB } : x));
    }
  }
  const pools = e.poolTeams(games);
  return {
    awaitingSeedsAtStart: awaiting,
    steps,
    poolTeams: Object.fromEntries(pools),
    poolStandings: Object.fromEntries(
      [...pools].map(([p, teams]) => [p, e.standings(teams, games.filter((g) => g.pool === p)).map((s) => s.teamId)]),
    ),
    gamesToPlay: e.gamesToPlay(games).map((g) => g.id),
    skipped: games.filter((g) => e.skippedGame(g, games)).map((g) => g.id),
    laterGamesPlayed: games.filter((g) => e.laterGamesPlayed(g, games)).map((g) => g.id),
    pendingFills: e.pendingFills(games),
    champion: e.championOf(format, games),
    placements: e.placementsOf(format, seeds, games),
  };
}

interface TournamentCase {
  name: string;
  teams: string[];
  settings: Json;
  plan: Json;
  playThrough: Json;
}

describe("schedules match the app (fixtures/tournament_engine/schedules.json)", () => {
  const { cases } = fixture<TournamentCase>("tournament_engine/schedules.json");

  it.each(cases)("tournament_engine.ts: $name", (c) => {
    const s = engineSettings(c.settings);
    const plan = scheduleFor(c.teams, s);
    expect(planJson(plan)).toEqual(c.plan);
    expect(playThrough(hostedEngine, s.format, c.teams, plan.games)).toEqual(c.playThrough);
  });

  it.each(cases)("groupEngine: $name", (c) => {
    const s = readGroupSettings(c.settings);
    const plan = groupEngine.scheduleFor(c.teams, s);
    expect(planJson(plan)).toEqual(c.plan);
    expect(playThrough(groupPlay, s.format, c.teams, plan.games)).toEqual(c.playThrough);
  });
});

interface SeasonCase extends TournamentCase {
  season: Json;
  nights: string[];
  byes: string[][];
}

describe("league seasons match the app (fixtures/tournament_engine/seasons.json)", () => {
  it.each(fixture<SeasonCase>("tournament_engine/seasons.json").cases)("$name", (c) => {
    const s = engineSettings(c.settings);
    const season = engineSeason(c.season)!;
    expect(seasonNights(s, season).map(localIso)).toEqual(c.nights);
    const plan = seasonFor(c.teams, s, season);
    expect(planJson(plan)).toEqual(c.plan);
    expect(Array.from({ length: season.weeks }, (_, w) => byesIn(c.teams, plan.games, w + 1))).toEqual(c.byes);
    expect(playThrough(hostedEngine, "singleElim", c.teams, plan.games)).toEqual(c.playThrough);
  });
});

describe("schedule errors match the app (fixtures/tournament_engine/schedule_errors.json)", () => {
  const s = engineSettings({ startsAt: "2026-06-06T09:00:00.000" });
  it.each(fixture<{ name: string; kind: string; teams: string[]; season?: Json; error: string }>("tournament_engine/schedule_errors.json").cases)(
    "$name",
    (c) => {
      const run = () => (c.kind === "season" ? seasonFor(c.teams, s, engineSeason(c.season)!) : scheduleFor(c.teams, s));
      expect(run).toThrow(ScheduleError);
      expect(run).toThrow(c.error);
      if (c.kind === "tournament") expect(() => groupEngine.scheduleFor(c.teams, readGroupSettings({}))).toThrow(c.error);
    },
  );
});

describe("standings match the app (fixtures/tournament_engine/standings.json)", () => {
  type Row = { teamId: string; wins: number; losses: number; pointsFor: number; pointsAgainst: number };
  const row = (r: Row) => ({ teamId: r.teamId, wins: r.wins, losses: r.losses, pointsFor: r.pointsFor, pointsAgainst: r.pointsAgainst });
  it.each(fixture<{ name: string; teamIds: string[]; games: Json[]; expected: Row[] }>("tournament_engine/standings.json").cases)("$name", (c) => {
    expect(standings(c.teamIds, c.games.map((g) => engineGame(String(g.id), g))).map(row)).toEqual(c.expected);
    expect(groupEngine.standings(c.teamIds, c.games.map((g) => readGroupGame(String(g.id), g))).map(row)).toEqual(c.expected);
  });
});

describe("engine helpers match the app (fixtures/tournament_engine/helpers.json)", () => {
  const helpers = Object.fromEntries(
    fixture<{ name: string; cases: Json[] }>("tournament_engine/helpers.json").cases.map((h) => [h.name, h.cases]),
  ) as Record<string, Array<Record<string, never>>>;

  it("roundRobin", () => {
    for (const c of helpers.roundRobin!) {
      expect(roundRobin(c.teams)).toEqual(c.rounds);
      expect(groupEngine.roundRobin(c.teams)).toEqual(c.rounds);
    }
  });
  it("seedOrder", () => {
    for (const c of helpers.seedOrder!) {
      expect(seedOrder(c.size)).toEqual(c.order);
      expect(groupEngine.seedOrder(c.size)).toEqual(c.order);
    }
  });
  it("suggestedPools and suggestedFormat", () => {
    for (const c of helpers["suggestedPools and suggestedFormat"]!) {
      expect([c.teams, suggestedPools(c.teams), suggestedFormat(c.teams)]).toEqual([c.teams, c.pools, c.format]);
      expect(groupEngine.suggestedPools(c.teams)).toBe(c.pools);
    }
  });
  it("ordinal", () => {
    for (const c of helpers.ordinal!) {
      expect(ordinal(c.n)).toBe(c.text);
      expect(groupEngine.ordinal(c.n)).toBe(c.text);
    }
  });
  it("gamesPerDay", () => {
    for (const c of helpers.gamesPerDay!) {
      expect(gamesPerDay(c.total, c.days)).toEqual(c.perDay);
      expect(groupEngine.gamesPerDay(c.total, c.days)).toEqual(c.perDay);
    }
  });
  it("poolName", () => {
    for (const c of helpers.poolName!) {
      expect(poolName(c.index)).toBe(c.name);
      expect(groupEngine.poolName(c.index)).toBe(c.name);
    }
  });
  it("scoreError", () => {
    for (const c of helpers.scoreError!) {
      const max = (c.max as number | null) ?? undefined;
      expect(scoreError(c.a, c.b, max)).toBe(c.error);
      expect(groupEngine.scoreError(c.a, c.b, max)).toBe(c.error);
    }
  });
});
