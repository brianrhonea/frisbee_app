// The app's game stats (apps/mobile/lib/domain/models/stats.dart) against
// stats.ts, on the vectors in fixtures/stats (written by
// apps/mobile/test/shared_fixtures/stats_fixtures_test.dart).
import { describe, expect, it } from "vitest";
import {
  currentHalf,
  gameOver,
  gameWon,
  halfAt,
  halftimePoint,
  hasPull,
  holder,
  lineKey,
  lineSources,
  linesForEvent,
  onField,
  ourScore,
  type PlayerStats,
  played,
  pointSide,
  ranked,
  reachedGamePoint,
  type StatSheet,
  statPointFrom,
  statSheetOfGames,
  statsGameFrom,
  statsTournamentFrom,
  theirScore,
  timeoutsLeft,
} from "../src/index.js";
import { fixture } from "./shared_fixtures.js";

type Json = Record<string, unknown>;

describe("points match the app (fixtures/stats/points.json)", () => {
  it.each(fixture<{ name: string; point: Json } & Json>("stats/points.json").cases)("$name", (c) => {
    const p = statPointFrom(c.point);
    expect({
      onField: onField(p),
      played: [...played(p)],
      side: pointSide(p),
      holder: holder(p),
      hasPull: hasPull(p),
    }).toEqual({ onField: c.onField, played: c.played, side: c.side, holder: c.holder, hasPull: c.hasPull });
  });
});

const playerFields = [
  "playerId",
  "pointsO",
  "pointsD",
  "pickups",
  "catches",
  "goals",
  "assists",
  "completions",
  "throwaways",
  "drops",
  "handBlocks",
  "breakups",
  "beats",
  "pulls",
  "pullsOutOfBounds",
  "finishedO",
  "holds",
  "finishedD",
  "breaks",
  "pointsPlayed",
  "oEfficiency",
  "dEfficiency",
  "oRating",
  "dRating",
  "touches",
  "throws",
  "catchPct",
  "completionPct",
  "avgHangTime",
  "plusMinus",
] as const satisfies ReadonlyArray<keyof PlayerStats>;

function sheetJson(s: StatSheet): Json {
  return {
    players: [...s.players.values()].map((p) => Object.fromEntries(playerFields.map((f) => [f, p[f]]))),
    team: {
      oPoints: s.team.oPoints,
      holds: s.team.holds,
      dPoints: s.team.dPoints,
      breaks: s.team.breaks,
      oEfficiency: s.team.oEfficiency,
      breakRate: s.team.breakRate,
    },
    ranked: ranked(s).map((p) => p.playerId),
  };
}

describe("games and stat sheets match the app (fixtures/stats/games.json)", () => {
  const { cases } = fixture<{ game?: Json; state?: Json; games?: string[]; sheet: Json }>("stats/games.json");
  const byId = new Map(cases.filter((c) => c.game).map((c) => [String(c.game!.id), statsGameFrom(String(c.game!.id), c.game)]));

  it.each(cases.filter((c) => c.game).map((c) => ({ ...c, id: c.game!.id })))("game $id", (c) => {
    const g = byId.get(String(c.id))!;
    expect({
      ourScore: ourScore(g),
      theirScore: theirScore(g),
      reachedGamePoint: reachedGamePoint(g),
      over: gameOver(g),
      halfAt: halfAt(g),
      halftimePoint: halftimePoint(g),
      half: currentHalf(g),
      timeoutsLeftOurs: timeoutsLeft(g, true),
      timeoutsLeftTheirs: timeoutsLeft(g, false),
      won: gameWon(g),
    }).toEqual(c.state);
    expect(sheetJson(statSheetOfGames([g]))).toEqual(c.sheet);
  });

  it("every game together", () => {
    const all = cases.find((c) => c.games)!;
    expect(sheetJson(statSheetOfGames(all.games!.map((id) => byId.get(id)!)))).toEqual(all.sheet);
  });
});

describe("line sources match the app (fixtures/stats/lines.json)", () => {
  it.each(fixture<{ tournaments: Json[]; games: Json[]; sources: Json[]; forEvent: Record<string, Json[]>; keys: string[] }>("stats/lines.json").cases)(
    "LineSource.from and forEvent",
    (c) => {
      const tournaments = c.tournaments.map((t) => statsTournamentFrom(String(t.id), t));
      const games = c.games.map((g) => statsGameFrom(String(g.id), g));
      const sources = lineSources(tournaments, games);
      expect(sources).toEqual(c.sources);
      for (const [event, lines] of Object.entries(c.forEvent)) expect(linesForEvent(event, sources)).toEqual(lines);
      expect(tournaments.flatMap((t) => t.lines.map(lineKey))).toEqual(c.keys);
    },
  );
});
