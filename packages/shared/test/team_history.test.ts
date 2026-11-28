import { describe, expect, it } from "vitest";
import { orderTeamHistory, seasonTotalsFor, teamHistorySchema, type TeamHistoryEntry } from "../src/index.js";
import { readFileSync } from "node:fs";

interface Totals {
  games: Array<{ id: string }>;
  cases: Array<{ name: string; spot: string; seasons: Record<string, unknown> }>;
}

// Hand-derived from the Dart code (the app lane makes its side assert the same file).
const totals = JSON.parse(readFileSync(new URL("../fixtures/team_history/totals.json", import.meta.url), "utf8")) as Totals;

describe("season totals match fixtures/team_history/totals.json", () => {
  it.each(totals.cases)("$name", (c) => {
    expect(seasonTotalsFor(c.spot, totals.games)).toEqual(c.seasons);
  });
  it("reads Date and ISO dates alike, and no games means no seasons", () => {
    expect(seasonTotalsFor("a", [])).toEqual({});
    const g = { ...totals.games[1]!, date: new Date("2025-06-01T12:00:00Z") };
    expect(Object.keys(seasonTotalsFor("a", [g]))).toEqual(["2025"]);
  });
});

const entry = (teamName: string, current: boolean, years: string[], id = teamName): TeamHistoryEntry => ({
  teamId: `t-${id}`,
  teamName,
  teamKind: "team",
  current,
  spot: { id, name: "N", number: null },
  seasons: Object.fromEntries(years.map((y) => [y, { games: 1, points: 1, goals: 0, assists: 0, blocks: 0, completions: 0, throwaways: 0, catches: 0, drops: 0 }])),
});

describe("orderTeamHistory", () => {
  it("puts current first, then the latest season, then the name", () => {
    const sorted = orderTeamHistory([
      entry("Zed", false, ["2026"]),
      entry("Bee", true, ["2024"]),
      entry("Aye", false, ["2025"]),
      entry("Cee", true, ["2024"]),
      entry("Dee", false, []),
      entry("Ant", true, ["2026"]),
    ]);
    expect(sorted.map((e) => e.teamName)).toEqual(["Ant", "Bee", "Cee", "Zed", "Aye", "Dee"]);
  });
});

describe("teamHistorySchema", () => {
  it("accepts an entry and rejects unknown fields", () => {
    expect(teamHistorySchema.safeParse({ teams: [entry("A", true, ["2026"])] }).success).toBe(true);
    expect(teamHistorySchema.safeParse({ teams: [{ ...entry("A", true, []), uid: "x" }] }).success).toBe(false);
  });
});
