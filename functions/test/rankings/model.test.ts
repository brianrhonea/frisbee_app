import { describe, expect, it } from "vitest";

import {
  countsForRankings,
  dateWeight,
  differential,
  divisionResult,
  rankingDoc,
  type RankedGame,
  rate,
  scoreWeight,
  startingRating,
} from "../../src/rankings/model";

const now = new Date("2026-11-09T00:00:00Z");
const day = 86_400_000;
const game = (teamA: string, scoreA: number, teamB: string, scoreB: number, daysAgo = 1): RankedGame => ({
  teamA,
  teamB,
  scoreA,
  scoreB,
  playedAt: new Date(now.getTime() - daysAgo * day),
});

describe("game differential", () => {
  it("is 125 for a one-point win and 600 for a blowout", () => {
    expect(differential(15, 14)).toBeCloseTo(125);
    expect(differential(13, 12)).toBeGreaterThanOrEqual(125);
    expect(differential(15, 7)).toBe(600);
    expect(differential(15, 0)).toBe(600);
    expect(differential(15, 10)).toBeGreaterThan(differential(15, 13));
  });

  it("is zero for a tie or a loss", () => {
    expect(differential(10, 10)).toBe(0);
    expect(differential(8, 10)).toBe(0);
  });
});

describe("weights", () => {
  it("counts short games less", () => {
    expect(scoreWeight(13, 6)).toBe(1);
    expect(scoreWeight(15, 4)).toBe(1);
    expect(scoreWeight(5, 3)).toBeLessThan(1);
  });

  it("counts older games less, down to a quarter a year back", () => {
    expect(dateWeight(now, now)).toBe(1);
    expect(dateWeight(new Date(now.getTime() - 365 * day), now)).toBeCloseTo(0.25);
    expect(dateWeight(new Date(now.getTime() - 30 * day), now)).toBeGreaterThan(
      dateWeight(new Date(now.getTime() - 200 * day), now),
    );
  });
});

describe("rate", () => {
  it("ranks a team that beats everyone first and keeps the average at the start", () => {
    const games = [
      game("a", 15, "b", 10),
      game("a", 15, "c", 8),
      game("b", 15, "c", 12),
      game("a", 15, "b", 13),
      game("b", 15, "c", 11),
      game("a", 15, "c", 9),
    ];
    const ratings = rate(games, now);
    expect(ratings.map((r) => r.teamId)).toEqual(["a", "b", "c"]);
    const mean = ratings.reduce((s, r) => s + r.rating, 0) / ratings.length;
    expect(mean).toBeCloseTo(startingRating);
    expect(ratings[0]).toMatchObject({ wins: 4, losses: 0, games: 4 });
  });

  it("rewards a bigger margin against the same opponent", () => {
    const ratings = rate([game("a", 15, "x", 5), game("b", 15, "x", 14)], now);
    const by = new Map(ratings.map((r) => [r.teamId, r.rating]));
    expect(by.get("a")!).toBeGreaterThan(by.get("b")!);
  });

  it("ignores self-play, bad scores and games outside the window", () => {
    const ratings = rate(
      [game("a", 15, "a", 3), game("a", -1, "b", 3), game("a", 0, "b", 0), game("a", 15, "b", 3, 400)],
      now,
    );
    expect(ratings).toEqual([]);
  });

  it("lets a strong team drop blowouts once it has enough other games", () => {
    // "a" beats peers closely five times, then crushes a weak team.
    const peers = ["b", "c", "d", "e", "f"].flatMap((t) => [game("a", 15, t, 13), game(t, 15, "w", 2)]);
    const withBlowout = rate([...peers, game("a", 15, "w", 1)], now);
    const without = rate(peers, now);
    const a = (r: ReturnType<typeof rate>) => r.find((x) => x.teamId === "a")!.rating;
    // Dropped, so it doesn't drag "a" toward the weak team's rating.
    expect(Math.abs(a(withBlowout) - a(without))).toBeLessThan(30);
  });
});

describe("stored docs", () => {
  it("ranks only teams with enough games, numbered from 1", () => {
    const doc = rankingDoc(
      "club",
      "mixed",
      [
        { teamId: "a", rating: 1200.4, wins: 5, losses: 0, games: 5 },
        { teamId: "b", rating: 1100, wins: 1, losses: 1, games: 2 },
        { teamId: "c", rating: 900.6, wins: 2, losses: 4, games: 6 },
      ],
      new Map([
        ["a", "Seattle Mixtape"],
        ["c", "Cascades"],
      ]),
    );
    expect(doc.teams).toEqual([
      { rank: 1, teamId: "a", name: "Seattle Mixtape", rating: 1200, wins: 5, losses: 0 },
      { rank: 2, teamId: "c", name: "Cascades", rating: 901, wins: 2, losses: 4 },
    ]);
  });

  it("only counts public club-style tournaments that are under way or final", () => {
    expect(countsForRankings({ visibility: "public", entryType: "teams", status: "finished" })).toBe(true);
    expect(countsForRankings({ visibility: "public", status: "live" })).toBe(true);
    expect(countsForRankings({ visibility: "inviteOnly", entryType: "teams", status: "finished" })).toBe(false);
    expect(countsForRankings({ visibility: "public", entryType: "players", status: "finished" })).toBe(false);
    expect(countsForRankings({ visibility: "public", entryType: "teams", status: "scheduled" })).toBe(false);
  });

  it("names each division's champion and runner-up", () => {
    const names = new Map([
      ["a", "Ring"],
      ["b", "Truck Stop"],
    ]);
    expect(divisionResult({ level: "club", division: "open", placements: ["a", "b", "c"] }, names)).toEqual({
      label: "Club Open",
      champion: { teamId: "a", name: "Ring" },
      runnerUp: { teamId: "b", name: "Truck Stop" },
    });
    expect(divisionResult({ level: "college", division: "women" }, names).champion).toBeNull();
  });
});
