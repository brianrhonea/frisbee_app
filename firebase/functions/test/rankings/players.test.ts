import { describe, expect, it } from "vitest";

import {
  type PlayerInput,
  playerInput,
  playerRankingDoc,
  production,
  ratePlayers,
  recentTotals,
  type SeasonTotals,
  seasonTotals,
} from "../../src/rankings/players";

const now = new Date("2026-11-09T00:00:00Z");

const totals = (t: Partial<SeasonTotals>): SeasonTotals => ({ ...seasonTotals({}), ...t });

const player = (uid: string, season: Partial<SeasonTotals>, last?: Partial<SeasonTotals>): PlayerInput => ({
  uid,
  name: uid.toUpperCase(),
  username: uid,
  photoUrl: null,
  seasons: { "2026": totals(season), ...(last ? { "2025": totals(last) } : {}) },
});

describe("which profiles are rated", () => {
  it("skips private profiles, hidden stats and nameless profiles", () => {
    const stats = { "2026": { games: 12, points: 100 } };
    expect(playerInput("a", { name: "Ann", stats })).toMatchObject({ uid: "a", name: "Ann" });
    expect(playerInput("a", { name: "Ann", private: true, stats })).toBeNull();
    expect(playerInput("a", { name: "Ann", visibility: { stats: false }, stats })).toBeNull();
    expect(playerInput("a", { name: "  ", stats })).toBeNull();
  });

  it("reads bad numbers as zero", () => {
    expect(seasonTotals({ games: -3, points: "9", goals: 2 })).toMatchObject({ games: 0, points: 0, goals: 2 });
  });
});

describe("production", () => {
  it("credits goals, assists and blocks, and charges turnovers", () => {
    expect(production(totals({ goals: 2, assists: 1, blocks: 2 }))).toBe(6);
    expect(production(totals({ throwaways: 2, drops: 4 }))).toBe(-5);
    // A goal's catch isn't counted as a touch too.
    expect(production(totals({ goals: 1, catches: 1 }))).toBe(1);
    expect(production(totals({ completions: 20, catches: 20 }))).toBeCloseTo(2);
  });

  it("adds half of last season", () => {
    const t = recentTotals({ "2026": totals({ games: 6 }), "2025": totals({ games: 8 }), "2024": totals({ games: 50 }) }, now);
    expect(t.games).toBe(10);
  });
});

describe("ratePlayers", () => {
  it("rates only players with 10 recent games", () => {
    const rated = ratePlayers(
      [player("a", { games: 10, points: 80, goals: 5 }), player("b", { games: 9, points: 90, goals: 9 })],
      now,
    );
    expect(rated.map((r) => r.uid)).toEqual(["a"]);
    expect(rated[0].rating).toBe(50);
  });

  it("counts last season at half toward the 10 games", () => {
    expect(ratePlayers([player("a", { games: 6, points: 50 }, { games: 8, points: 60 })], now)).toHaveLength(1);
    expect(ratePlayers([player("a", { games: 6, points: 50 }, { games: 6, points: 60 })], now)).toHaveLength(0);
  });

  it("puts more production per point higher, around an average of 50", () => {
    const rated = ratePlayers(
      [
        player("star", { games: 20, points: 200, goals: 30, assists: 30, blocks: 10 }),
        player("solid", { games: 20, points: 200, goals: 10, assists: 10, blocks: 5, throwaways: 5 }),
        player("shaky", { games: 20, points: 200, goals: 2, throwaways: 25, drops: 10 }),
      ],
      now,
    );
    expect(rated.map((r) => r.uid)).toEqual(["star", "solid", "shaky"]);
    const avg = rated.reduce((s, r) => s + r.rating, 0) / rated.length;
    expect(avg).toBeCloseTo(50);
    expect(rated[2]).toMatchObject({ turnovers: 35 });
  });

  it("trusts a big sample more than a hot start", () => {
    const rated = ratePlayers(
      [
        // Better per point, over very few points.
        player("hot", { games: 10, points: 20, goals: 8 }),
        player("steady", { games: 40, points: 400, goals: 120 }),
        player("avg", { games: 40, points: 400, goals: 40 }),
      ],
      now,
    );
    expect(rated[0].uid).toBe("steady");
  });

  it("stores the top players numbered, with whole ratings", () => {
    const doc = playerRankingDoc([
      { uid: "a", name: "A", username: null, photoUrl: null, rating: 71.6, games: 12, points: 90, goals: 9, assists: 4, blocks: 2, turnovers: 3 },
    ]);
    expect(doc).toMatchObject({ minGames: 10, players: [{ uid: "a", rank: 1, rating: 72 }] });
  });
});
