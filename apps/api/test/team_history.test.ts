// GET /v1/players/:uid/team-history against FakeStore: the person sees every
// team they're linked to (left ones too), others only what their profile
// shows, and youth teams, closed pages and groups stay with members.
import { beforeEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { type DocQueries, listDocQueries } from "../src/queries.js";
import { readLimits } from "../src/limits/reads.js";
import { FakeStore, FakeTeamRepository, FakeUsers, FakeVerifier } from "./fakes.js";

class ClaimUsers extends FakeUsers {
  adults = new Set<string>();
  async ageOkOf(uids: string[]) {
    return new Set(uids.filter((u) => this.adults.has(u)));
  }
}

function setup(mode?: "enforce" | "report") {
  const store = new FakeStore();
  const users = mode ? new ClaimUsers() : new FakeUsers();
  const base = listDocQueries(store);
  const queries: DocQueries = {
    ...base,
    // A collection group query over the in-memory documents.
    async group(collectionId, limit, where) {
      return [...store.docs.entries()]
        .filter(([path]) => {
          const parts = path.split("/");
          return parts.length % 2 === 0 && parts[parts.length - 2] === collectionId;
        })
        .filter(([, data]) => Object.entries(where).every(([k, v]) => data[k] === v))
        .slice(0, limit)
        .map(([path, data]) => ({ path, data: structuredClone(data) }));
    },
  };
  const app = buildApp({ verifier: new FakeVerifier(), users, accountGateMode: mode, teams: new FakeTeamRepository(), store, queries });
  const get = (uid: string, as: string | null = "viewer") =>
    app.inject({ method: "GET", url: `/v1/players/${uid}/team-history`, headers: as ? { authorization: `Bearer token:${as}` } : {} });
  return { store, users, get };
}

const point = (spot: string, goal = true) => ({
  line: [spot, "other"],
  startedOn: "offense",
  result: "weScored",
  actions: goal ? [{ kind: "goal", playerId: spot, throwerId: "other" }] : [],
});
const game = (spot: string, date: string) => ({ opponent: "Them", date: new Date(date), gameTo: 15, points: [point(spot)] });

const team = (name: string, extra: Record<string, unknown> = {}) => ({
  name,
  kind: "team",
  level: "club",
  ownerId: "o",
  memberIds: ["o"],
  members: { o: "owner" },
  ...extra,
});

let s: ReturnType<typeof setup>;
beforeEach(() => {
  s = setup();
  s.store.put("profiles/pat", { name: "Pat", username: "pat" });
  // Current club team, with a game this season and one last season.
  s.store.put("teams/cur", team("Current Club", { memberIds: ["o", "pat"], members: { o: "owner", pat: "player" } }));
  s.store.put("teams/cur/roster/p1", { name: "Pat P", number: 7, userId: "pat" });
  s.store.put("teams/cur/roster/p2", { name: "Someone Else", userId: "zed" });
  s.store.put("teams/cur/statsGames/g1", game("p1", "2026-05-01T12:00:00Z"));
  s.store.put("teams/cur/statsGames/g2", game("p1", "2025-05-01T12:00:00Z"));
  s.store.put("teams/cur/statsGames/g3", game("p2", "2026-05-02T12:00:00Z"));
  // A team Pat left: still linked.
  s.store.put("teams/old", team("Old College", { level: "college" }));
  s.store.put("teams/old/roster/q1", { name: "Pat Q", userId: "pat" });
  s.store.put("teams/old/statsGames/g1", game("q1", "2024-04-01T12:00:00Z"));
});

const names = (res: { json(): { teams: Array<{ teamName: string }> } }) => res.json().teams.map((t) => t.teamName);

describe("the person themselves", () => {
  it("sees current and left teams, current first, with their totals", async () => {
    const res = await s.get("pat", "pat");
    expect(res.statusCode).toBe(200);
    expect(res.headers["cache-control"]).toBe("private, no-store");
    const { teams } = res.json();
    expect(teams.map((t: { teamName: string; current: boolean }) => [t.teamName, t.current])).toEqual([
      ["Current Club", true],
      ["Old College", false],
    ]);
    expect(teams[0]).toEqual({
      teamId: "cur",
      teamName: "Current Club",
      teamKind: "team",
      current: true,
      spot: { id: "p1", name: "Pat P", number: 7 },
      seasons: {
        "2025": { games: 1, points: 1, goals: 1, assists: 0, blocks: 0, completions: 0, throwaways: 0, catches: 1, drops: 0 },
        "2026": { games: 1, points: 1, goals: 1, assists: 0, blocks: 0, completions: 0, throwaways: 0, catches: 1, drops: 0 },
      },
    });
    expect(teams[1].spot).toEqual({ id: "q1", name: "Pat Q", number: null });
    expect(Object.keys(teams[1].seasons)).toEqual(["2024"]);
  });

  it("sees everything even when stats and teams are hidden or the profile is private, and youth teams too", async () => {
    s.store.put("profiles/pat", { name: "Pat", private: true, visibility: { stats: false, teams: false, games: false } });
    s.store.put("teams/youth", team("Youth Team", { level: "youth" }));
    s.store.put("teams/youth/roster/y1", { name: "Pat Y", userId: "pat" });
    const res = await s.get("pat", "pat");
    expect(names(res).sort()).toEqual(["Current Club", "Old College", "Youth Team"]);
  });

  it("leaves communities and groups out, and a deleted team", async () => {
    s.store.put("teams/club", { name: "A Community", kind: "community", memberIds: ["pat"], members: { pat: "player" } });
    s.store.put("teams/club/roster/c1", { name: "Pat C", userId: "pat" });
    s.store.put("teams/gone/roster/x1", { name: "Pat G", userId: "pat" });
    expect(names(await s.get("pat", "pat")).sort()).toEqual(["Current Club", "Old College"]);
  });

  it("returns an empty history for someone with no links, and nothing of another person's spots", async () => {
    s.store.put("profiles/nobody", { name: "No Body" });
    expect((await s.get("nobody", "nobody")).json()).toEqual({ teams: [] });
    expect(JSON.stringify((await s.get("pat", "pat")).json())).not.toContain("zed");
  });

  it("counts a spot's games only for that spot", async () => {
    // g3 belongs to p2 (zed): not in Pat's 2026 totals.
    const t = (await s.get("pat", "pat")).json().teams[0];
    expect(t.seasons["2026"].games).toBe(1);
  });
});

describe("someone else", () => {
  it("sees a public profile's current and left teams with totals", async () => {
    const res = await s.get("pat");
    expect(res.statusCode).toBe(200);
    expect(names(res)).toEqual(["Current Club", "Old College"]);
    expect(res.json().teams[1].seasons["2024"].goals).toBe(1);
    const text = JSON.stringify(res.json());
    expect(text).not.toContain("zed");
    expect(text).not.toContain('"uid"');
    expect(text).not.toContain('"userId"');
  });

  it.each([
    ["a private profile", { private: true }],
    ["stats hidden", { visibility: { stats: false, teams: true, games: true } }],
    ["teams hidden", { visibility: { stats: true, teams: false, games: true } }],
  ])("gets an empty history for %s", async (_n, profile) => {
    s.store.put("profiles/pat", { name: "Pat", ...profile });
    const res = await s.get("pat");
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ teams: [] });
  });

  it("sees a profile that hides only its games", async () => {
    s.store.put("profiles/pat", { name: "Pat", visibility: { stats: true, teams: true, games: false } });
    expect(names(await s.get("pat"))).toEqual(["Current Club", "Old College"]);
  });

  it("gets not_found for an unknown or malformed player, as the profile does", async () => {
    expect((await s.get("ghost")).statusCode).toBe(404);
    expect((await s.get("a%2Fb")).statusCode).toBe(404);
  });

  it("needs a sign-in", async () => {
    expect((await s.get("pat", null)).statusCode).toBe(401);
  });

  it("hides youth teams, closed public pages and drafted league teams from non-members, but not from members", async () => {
    s.store.put("teams/youth", team("Youth Team", { level: "youth" }));
    s.store.put("teams/youth/roster/y1", { name: "Pat Y", userId: "pat" });
    s.store.put("teams/closed", team("Closed Page", { publicPage: false }));
    s.store.put("teams/closed/roster/c1", { name: "Pat C", userId: "pat" });
    s.store.put("teams/league_abc", team("Drafted"));
    s.store.put("teams/league_abc/roster/d1", { name: "Pat D", userId: "pat" });
    expect(names(await s.get("pat")).sort()).toEqual(["Current Club", "Old College"]);
    // A member of the youth and closed teams sees them.
    s.store.put("teams/youth", team("Youth Team", { level: "youth", memberIds: ["o", "viewer"], members: { o: "owner", viewer: "player" } }));
    s.store.put("teams/closed", team("Closed Page", { publicPage: false, memberIds: ["o", "viewer"], members: { o: "owner", viewer: "player" } }));
    expect(names(await s.get("pat")).sort()).toEqual(["Closed Page", "Current Club", "Old College", "Youth Team"]);
  });

  it("hides a team in a youth division of a league", async () => {
    s.store.put("teams/lg", team("League Side", { leagueId: "L1" }));
    s.store.put("teams/lg/roster/l1", { name: "Pat L", userId: "pat" });
    s.store.put("tournaments/L1", { divisions: [{ id: "d1", level: "youth" }] });
    s.store.put("tournaments/L1/entries/lg", { divisionId: "d1" });
    expect(names(await s.get("pat"))).not.toContain("League Side");
    expect(names(await s.get("pat", "pat"))).toContain("League Side");
  });
});

describe("adult claim (D-1317)", () => {
  it("answers not_found for a profile without the claim in enforce mode, but still shows it to the person", async () => {
    const e = setup("enforce");
    e.store.put("profiles/pat", { name: "Pat" });
    e.store.put("teams/cur", team("Current Club", { memberIds: ["pat"], members: { pat: "player" } }));
    e.store.put("teams/cur/roster/p1", { name: "Pat P", userId: "pat" });
    expect((await e.get("pat")).statusCode).toBe(404);
    expect((await e.get("pat", "pat")).json().teams).toHaveLength(1);
  });

  it("shows an adult's history to others in enforce mode", async () => {
    const e = setup("enforce");
    (e.users as ClaimUsers).adults.add("pat");
    e.store.put("profiles/pat", { name: "Pat" });
    e.store.put("teams/cur", team("Current Club", { memberIds: ["pat"], members: { pat: "player" } }));
    e.store.put("teams/cur/roster/p1", { name: "Pat P", userId: "pat" });
    expect((await e.get("pat")).json().teams).toHaveLength(1);
  });
});

describe("bounds", () => {
  it("returns at most 50 linked spots", async () => {
    for (let i = 0; i < 60; i++) {
      const id = `bulk${String(i).padStart(2, "0")}`;
      s.store.put(`teams/${id}`, team(`Bulk ${id}`));
      s.store.put(`teams/${id}/roster/r`, { name: "Pat", userId: "pat" });
    }
    const res = await s.get("pat", "pat");
    expect(res.json().teams).toHaveLength(50);
  });

  const seedGames = (n: number) => {
    for (let i = 0; i < n; i++) s.store.put(`teams/old/statsGames/h${String(i).padStart(4, "0")}`, game("q1", "2023-01-01T12:00:00Z"));
  };
  const oldTeam = async () => (await s.get("pat", "pat")).json().teams.find((t: { teamId: string }) => t.teamId === "old");

  it("pages through a team's games past one page, with no partial flag at exactly 1000", async () => {
    seedGames(999); // plus g1 = 1000
    const old = await oldTeam();
    expect(old.seasons["2023"].games + old.seasons["2024"].games).toBe(1000);
    expect(old).not.toHaveProperty("partial");
  });

  it("counts the first 1000 games and flags a team with more as partial", async () => {
    seedGames(1000); // plus g1 = 1001
    const old = await oldTeam();
    expect(old.seasons["2024"].games).toBe(1);
    expect(old.seasons["2023"].games).toBe(999);
    expect(old.partial).toBe(true);
  });

  it("is rate limited per member", async () => {
    for (let i = 0; i < readLimits.teamHistory.max; i++) expect((await s.get("pat", "pat")).statusCode).toBe(200);
    expect((await s.get("pat", "pat")).statusCode).toBe(429);
  });
});
