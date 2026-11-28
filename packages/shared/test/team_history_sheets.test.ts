// seasonTotalsForSpots builds each game's stat sheet once, whatever the number of spots.
import { readFileSync } from "node:fs";
import { describe, expect, it, vi } from "vitest";

vi.mock("../src/stats.js", async (importOriginal) => {
  const orig = await importOriginal<typeof import("../src/stats.js")>();
  return { ...orig, statSheet: vi.fn(orig.statSheet) };
});

import { seasonTotalsFor, seasonTotalsForSpots } from "../src/team_history.js";
import { statSheet } from "../src/stats.js";

const fixture = JSON.parse(readFileSync(new URL("../fixtures/team_history/totals.json", import.meta.url), "utf8")) as {
  games: Array<{ id: string; points?: unknown[] }>;
  cases: Array<{ spot: string }>;
};

describe("seasonTotalsForSpots", () => {
  const spots = [...new Set(fixture.cases.map((c) => c.spot))];
  const withPoints = fixture.games.filter((g) => Array.isArray(g.points) && g.points.length > 0).length;

  it("builds the stat sheet once per game for any number of spots", () => {
    const sheet = vi.mocked(statSheet);
    sheet.mockClear();
    seasonTotalsForSpots(spots, fixture.games);
    expect(spots.length).toBeGreaterThan(1);
    expect(sheet).toHaveBeenCalledTimes(withPoints);
  });

  it("gives each spot the same totals as seasonTotalsFor", () => {
    const all = seasonTotalsForSpots(spots, fixture.games);
    for (const s of spots) expect(all.get(s)).toEqual(seasonTotalsFor(s, fixture.games));
  });
});
