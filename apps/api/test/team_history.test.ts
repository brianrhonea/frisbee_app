// GET /v1/players/:uid/team-history against FakeStore: the person sees every
// team they're linked to (left ones too), others only what their profile
// shows, and youth teams, closed pages and groups stay with members.
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { buildApp } from "../src/app.js";
import { type DocQueries, listDocQueries } from "../src/queries.js";
import { TeamHistoryService } from "../src/teams/history.js";
import { readLimits } from "../src/limits/reads.js";
import { teamHistoryGameBudget } from "@stall10/shared";
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
  // What the history reads from statsGames: documents and their bytes.
  const reads = { docs: 0, bytes: 0, calls: 0, delay: undefined as undefined | Promise<void> };
  const queries: DocQueries = {
    ...base,
    async fields(collection, fields, limit, where, after) {
      reads.calls++;
      const hold = reads.delay;
      reads.delay = undefined; // holds only the first read
      if (hold) await hold;
      const out = await base.fields(collection, fields, limit, where, after);
      reads.docs += out.length;
      reads.bytes += out.reduce((n, d) => n + JSON.stringify(d.data).length, 0);
      return out;
    },
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
  return { store, users, get, reads };
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
    s.store.put("teams/youth", team("Youth Team", { level: "youth", memberIds: ["o", "member"], members: { o: "owner", member: "player" } }));
    s.store.put("teams/closed", team("Closed Page", { publicPage: false, memberIds: ["o", "member"], members: { o: "owner", member: "player" } }));
    // (A different caller: the first one's answer is kept for a minute.)
    expect(names(await s.get("pat", "member")).sort()).toEqual(["Closed Page", "Current Club", "Old College", "Youth Team"]);
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

describe("blocks", () => {
  // A block writes both sides' documents (PUT /v1/me/blocks/:uid).
  it("gives the blocker an empty history of the person they blocked", async () => {
    s.store.put("users/viewer/blocks/pat", { mine: true });
    s.store.put("users/pat/blocks/viewer", { mine: false });
    expect((await s.get("pat")).json()).toEqual({ teams: [] });
  });

  it("gives the blocked person an empty history of whoever blocked them", async () => {
    s.store.put("users/pat/blocks/viewer", { mine: true });
    s.store.put("users/viewer/blocks/pat", { mine: false });
    const res = await s.get("pat");
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ teams: [] });
  });

  it("does not hide a person's own history", async () => {
    s.store.put("users/pat/blocks/viewer", { mine: true });
    expect((await s.get("pat", "pat")).json().teams).toHaveLength(2);
  });
});

describe("teams without a public roster level", () => {
  it("hides a team with no level from strangers, but not from members or the person", async () => {
    const { level: _level, ...noLevel } = team("No Level");
    s.store.put("teams/nolevel", noLevel);
    s.store.put("teams/nolevel/roster/n1", { name: "Pat N", userId: "pat" });
    expect(names(await s.get("pat"))).not.toContain("No Level");
    expect(names(await s.get("pat", "pat"))).toContain("No Level");
    s.store.put("teams/nolevel", { ...noLevel, memberIds: ["o", "member"], members: { o: "owner", member: "player" } });
    expect(names(await s.get("pat", "member"))).toContain("No Level");
  });

  it("hides a team with an unknown level from strangers", async () => {
    s.store.put("teams/odd", team("Odd Level", { level: "mystery" }));
    s.store.put("teams/odd/roster/n1", { name: "Pat N", userId: "pat" });
    expect(names(await s.get("pat"))).not.toContain("Odd Level");
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

  it("pages through a team's games past one page, with no partial flag when all fit the budget", async () => {
    seedGames(299); // plus g1 = 300; Current Club's 3 games come first
    const old = await oldTeam();
    expect(old.seasons["2023"].games + old.seasons["2024"].games).toBe(300);
    expect(old).not.toHaveProperty("partial");
    expect(s.reads.docs).toBe(3 + 300);
  });

  it("stops at the request's game budget and flags the team partial", async () => {
    seedGames(1000); // plus g1 = 1001
    const old = await oldTeam();
    const counted = teamHistoryGameBudget - 3; // Current Club's games are read first
    expect(old.seasons["2024"].games).toBe(1); // g1 sorts before h0000
    expect(old.seasons["2023"].games).toBe(counted - 1);
    expect(old.partial).toBe(true);
    expect(s.reads.docs).toBeLessThanOrEqual(teamHistoryGameBudget + 1);
  });

  it("flags a team with exactly the remaining budget as complete, and the next team as not reached", async () => {
    seedGames(teamHistoryGameBudget - 3 - 1); // plus g1: exactly the budget left after Current Club
    s.store.put("teams/zzz", team("Zzz Last"));
    s.store.put("teams/zzz/roster/z1", { name: "Pat Z", userId: "pat" });
    s.store.put("teams/zzz/statsGames/g1", game("z1", "2022-01-01T12:00:00Z"));
    const { teams } = (await s.get("pat", "pat")).json();
    const by = (id: string) => teams.find((t: { teamId: string }) => t.teamId === id);
    expect(by("cur")).not.toHaveProperty("partial");
    expect(by("old")).not.toHaveProperty("partial");
    expect(by("zzz").partial).toBe(true);
    expect(by("zzz").seasons).toEqual({});
  });

  describe("heavy history", () => {
    afterEach(() => vi.useRealTimers());

    it("reads at most the game budget for 50 teams of 1001 large games each", { timeout: 120_000 }, async () => {
      const bigPoints = Array.from({ length: 30 }, () => point("r", false));
      for (let t = 0; t < 50; t++) {
        const id = `big${String(t).padStart(2, "0")}`;
        s.store.put(`teams/${id}`, team(`Big ${id}`));
        s.store.put(`teams/${id}/roster/r`, { name: "Pat", userId: "pat" });
        for (let g = 0; g < 1001; g++) {
          s.store.put(`teams/${id}/statsGames/g${String(g).padStart(4, "0")}`, {
            opponent: "Them",
            date: new Date("2026-01-01T12:00:00Z"),
            gameTo: 15,
            points: bigPoints,
          });
        }
      }
      const res = await s.get("pat", "pat");
      expect(res.statusCode).toBe(200);
      const { teams } = res.json();
      expect(teams).toHaveLength(50);
      // The 3-game and 1-game teams of the fixtures come first and fit; every Big team is partial.
      expect(teams.filter((t: { teamId: string }) => t.teamId.startsWith("big")).every((t: { partial?: boolean }) => t.partial === true)).toBe(true);
      expect(s.reads.docs).toBeLessThanOrEqual(teamHistoryGameBudget + 1);
      const perDoc = s.reads.bytes / s.reads.docs;
      expect(s.reads.bytes).toBeLessThanOrEqual((teamHistoryGameBudget + 1) * Math.ceil(perDoc));
      // 20 games a page, never the old 100.
      expect(s.reads.calls).toBeGreaterThanOrEqual(Math.ceil(teamHistoryGameBudget / 20));
    });

    it("answers a second request of the same caller made while one runs with 429, and lets others through", async () => {
      let release!: () => void;
      s.reads.delay = new Promise<void>((r) => (release = r));
      const first = s.get("pat", "pat");
      await vi.waitFor(() => expect(s.reads.calls).toBeGreaterThan(0));
      const second = await s.get("pat", "pat");
      expect(second.statusCode).toBe(429);
      expect(second.json().error?.code ?? second.json().code).toBe("resource_exhausted");
      // Another caller isn't held up by it.
      expect((await s.get("pat", "someoneelse")).statusCode).toBe(200);
      release();
      expect((await first).statusCode).toBe(200);
      // Free again once it ends.
      expect((await s.get("pat", "pat")).statusCode).toBe(200);
    });

    it("serves a repeat within 60 seconds from memory, then reads again", async () => {
      vi.useFakeTimers({ toFake: ["Date"] });
      vi.setSystemTime(new Date("2026-06-01T12:00:00Z"));
      const first = await s.get("pat", "pat");
      const docs = s.reads.docs;
      expect(docs).toBeGreaterThan(0);
      vi.setSystemTime(new Date("2026-06-01T12:00:59Z"));
      const again = await s.get("pat", "pat");
      expect(again.json()).toEqual(first.json());
      expect(again.headers["cache-control"]).toBe("private, no-store");
      expect(s.reads.docs).toBe(docs);
      vi.setSystemTime(new Date("2026-06-01T12:01:01Z"));
      await s.get("pat", "pat");
      expect(s.reads.docs).toBe(docs * 2);
    });

    it("keeps at most 500 cached answers, dropping the oldest", async () => {
      // The service directly (the route's rate limit would stop 500 requests).
      const queries = listDocQueries(s.store);
      let docs = 0;
      const counted: DocQueries = {
        ...queries,
        async fields(c, f, l, w, a) {
          const out = await queries.fields(c, f, l, w, a);
          docs += out.length;
          return out;
        },
        group: async (collectionId, limit, where) =>
          [...s.store.docs.entries()]
            .filter(([path]) => path.split("/").slice(-2, -1)[0] === collectionId)
            .filter(([, d]) => Object.entries(where).every(([k, v]) => d[k] === v))
            .slice(0, limit)
            .map(([path, data]) => ({ path, data: structuredClone(data) })),
      };
      const svc = new TeamHistoryService(s.store, counted, { inYouthLeague: async () => false } as never);
      for (const who of ["a", "b"]) {
        s.store.put(`profiles/${who}`, { name: who });
        s.store.put(`teams/t${who}`, team(`T ${who}`));
        s.store.put(`teams/t${who}/roster/r`, { name: who, userId: who });
        s.store.put(`teams/t${who}/statsGames/g1`, game("r", "2026-01-01T12:00:00Z"));
        await svc.history({ uid: "viewer" } as never, who);
      }
      for (let i = 0; i < 499; i++) {
        s.store.put(`profiles/f${i}`, { name: "F" });
        await svc.history({ uid: "viewer" } as never, `f${i}`);
      }
      const before = docs;
      await svc.history({ uid: "viewer" } as never, "b"); // still cached
      expect(docs).toBe(before);
      await svc.history({ uid: "viewer" } as never, "a"); // the oldest was dropped
      expect(docs).toBeGreaterThan(before);
    });
  });

  it("is rate limited per member", async () => {
    for (let i = 0; i < readLimits.teamHistory.max; i++) expect((await s.get("pat", "pat")).statusCode).toBe(200);
    expect((await s.get("pat", "pat")).statusCode).toBe(429);
  });
});
