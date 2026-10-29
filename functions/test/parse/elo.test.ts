import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import { expectedScore, movMultiplier, rateTeams } from "../../src/elo/teamElo";
import { buildDivisionElo, fetchTeamGames } from "../../src/usau/eloSync";
import { parseTeamPage, parseTeamTabs, resolveGameDate } from "../../src/usau/team";

const fixture = (name: string) =>
  readFileSync(join(__dirname, "..", "fixtures", name), "utf8");

const TEAM_URL = "https://play.usaultimate.org/teams/events/Eventteam/?TeamId=abc";
const team = (id: string) => `https://play.usaultimate.org/teams/events/Eventteam/?TeamId=${id}`;

describe("team Elo engine", () => {
  it("gives equal ratings an even chance", () => {
    expect(expectedScore(1500, 1500)).toBeCloseTo(0.5);
    expect(expectedScore(1900, 1500)).toBeCloseTo(0.909, 3);
  });

  it("scales margin logarithmically, reaching 1 at 7 points", () => {
    expect(movMultiplier(7)).toBeCloseTo(1);
    expect(movMultiplier(1)).toBeLessThan(movMultiplier(10));
    expect(movMultiplier(10)).toBeLessThan(10 / 7);
  });

  it("is zero-sum, ordered by date, and counts records", () => {
    const ratings = rateTeams([
      { playedOn: "2026-08-04", a: "B", b: "C", scoreA: 15, scoreB: 5 },
      { playedOn: "2026-08-03", a: "A", b: "B", scoreA: 15, scoreB: 13 },
    ]);
    expect(ratings.reduce((s, r) => s + r.elo, 0)).toBeCloseTo(1500 * 3);
    const byTeam = Object.fromEntries(ratings.map((r) => [r.team, r]));
    expect(byTeam.A.wins).toBe(1);
    expect(byTeam.B).toMatchObject({ wins: 1, losses: 1, games: 2 });
    expect(byTeam.C.elo).toBeLessThan(1500);
  });

  it("rewards an upset more than an expected win", () => {
    const upset = rateTeams([
      { playedOn: "1", a: "Fav", b: "Dog", scoreA: 15, scoreB: 3 },
      { playedOn: "1", a: "Fav", b: "Dog", scoreA: 15, scoreB: 3 },
      { playedOn: "2", a: "Fav", b: "Dog", scoreA: 13, scoreB: 15 },
    ]);
    const plain = rateTeams([{ playedOn: "1", a: "X", b: "Y", scoreA: 13, scoreB: 15 }]);
    const dogGain = (r: typeof upset) => r.find((t) => t.team === "Dog" || t.team === "Y")!;
    expect(dogGain(upset).elo - 1500).toBeLessThan(0); // still down after two routs
    expect(dogGain(plain).elo).toBeGreaterThan(1500);
  });
});

describe("team page parsing (synthetic fixtures)", () => {
  it("reads played and unplayed games plus events", () => {
    const page = parseTeamPage(fixture("team_schedule_synthetic.html"));
    expect(page.events.map((e) => e.name)).toEqual(["Fall Classic", "Pro Championships", "Regionals"]);
    expect(page.games.map((g) => [g.opponent, g.scoreFor, g.scoreAgainst])).toEqual([
      ["Zeta", null, null],
      ["Eta", null, null],
      ["Beta", 13, 9],
    ]);
    expect(page.games[2].opponentUrl).toBe(team("def"));
  });

  it("finds only the postback events tab", () => {
    const tabs = parseTeamTabs(fixture("team_synthetic.html"), TEAM_URL);
    expect(tabs).toEqual([
      {
        url: TEAM_URL,
        fields: {
          __EVENTTARGET: "CT_Main_0$lnkEvents",
          __EVENTARGUMENT: "",
          __VIEWSTATE: "vs-team",
        },
      },
    ]);
  });

  it("resolves schedule dates using the event's year", () => {
    const ev = { name: "x", startDate: new Date(Date.UTC(2025, 7, 2, 12)), endDate: null };
    expect(resolveGameDate("Aug 3", ev, 2026)).toBe("2025-08-03");
    expect(resolveGameDate("Sat 8/3", undefined, 2026)).toBe("2026-08-03");
    expect(resolveGameDate("Nov 07, 2024", undefined, 2026)).toBe("2024-11-07");
    expect(resolveGameDate("", ev, 2026)).toBe("2025-08-02");
    expect(resolveGameDate("TBD", undefined, 2026)).toBeNull();
  });
});

describe("fetchTeamGames", () => {
  it("merges the schedule tab and keeps only played games", async () => {
    const fetchFn = (async (_url: string, init: RequestInit) =>
      new Response(
        fixture(init.method === "POST" ? "team_schedule_synthetic.html" : "team_synthetic.html"),
      )) as unknown as typeof fetch;
    const games = await fetchTeamGames(TEAM_URL, { fetchFn, delayMs: 0, year: 2026 });
    // Beta is on both pages; W-L and unplayed games have no numeric score.
    expect(games.map((g) => [g.playedOn, g.opponent, g.scoreFor, g.scoreAgainst])).toEqual([
      ["2026-08-03", "Beta", 13, 9],
      ["2026-08-04", "Gamma", 10, 15],
    ]);
  });
});

describe("buildDivisionElo", () => {
  const game = (opponent: string, opponentUrl: string, f: number, a: number, playedOn = "2026-08-03") => ({
    playedOn,
    tournament: "Pro Championships",
    opponent,
    opponentUrl,
    scoreFor: f,
    scoreAgainst: a,
  });

  it("counts a game listed on both teams' pages once", () => {
    const ranked = [
      { teamName: "Alpha", teamUrl: team("a") },
      { teamName: "Beta", teamUrl: team("b") },
      { teamName: "Gamma", teamUrl: team("c") },
    ];
    const entries = buildDivisionElo(ranked, [
      {
        ...ranked[0],
        games: [
          game("Beta", team("b"), 15, 10),
          game("Gamma", "", 15, 12, "2026-08-04"),
          game("Beta", team("b"), 15, 11, "2026-08-05"),
        ],
      },
      // Beta's page repeats the first game from its side.
      { ...ranked[1], games: [game("Alpha", team("a"), 10, 15), game("Gamma", team("c"), 15, 9, "2026-08-04")] },
      { ...ranked[2], games: [game("Beta", team("b"), 9, 15, "2026-08-04")] },
    ]);
    expect(entries.map((e) => [e.rank, e.teamName, e.games, e.wins, e.losses])).toEqual([
      [1, "Alpha", 3, 3, 0],
      [2, "Beta", 3, 1, 2],
    ]);
    // Gamma (matched by name for Alpha's link-less row) has only 2 games.
    expect(entries.find((e) => e.teamName === "Gamma")).toBeUndefined();
    expect(entries[0].teamUrl).toBe(team("a"));
  });
});
