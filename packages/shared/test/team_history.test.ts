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

describe("season years are bounded to 1900-2100 (UTC)", () => {
  const base = totals.games[1]!;
  const years = (date: unknown) => Object.keys(seasonTotalsFor("a", [{ ...base, date }]));
  it("keeps the edges and drops games outside them", () => {
    expect(years("1900-01-01T00:00:00Z")).toEqual(["1900"]);
    expect(years("2100-12-31T23:59:59Z")).toEqual(["2100"]);
    expect(years("1899-12-31T23:59:59Z")).toEqual([]);
    expect(years("2101-01-01T00:00:00Z")).toEqual([]);
    expect(years("0001-06-01T00:00:00Z")).toEqual([]);
    expect(years("+275000-01-01T00:00:00Z")).toEqual([]);
    expect(years("not a date")).toEqual([`${new Date().getUTCFullYear()}`]); // an unreadable date means now, as before
  });
  it("only ever yields four-digit season keys", () => {
    const all = seasonTotalsFor("a", [{ ...base, date: "2025-06-01T00:00:00Z" }, { ...base, date: "0099-01-01T00:00:00Z" }]);
    for (const k of Object.keys(all)) expect(k).toMatch(/^\d{4}$/);
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
