// Visitors' rankings (`GET /v1/public/rankings`) with fakes: open without a
// token, never youth (by key or by team), no private groups, only the
// fields visitors may see, the visitor limit and the caches.
import { publicRankingsSchema } from "@stall10/shared";
import { describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import type { BrowseRepository } from "../src/browse/repository.js";
import { webKeyHeader } from "../src/browse/routes.js";
import type { RateLimiter } from "../src/limits/limiter.js";
import type { Data, Doc, PublicRankingRepository } from "../src/rankings/public_repository.js";
import { publicRankingsCacheMs } from "../src/rankings/public_service.js";
import { FakeTeamRepository, FakeUsers, FakeVerifier } from "./fakes.js";

const now = Date.parse("2026-11-15T18:00:00Z");

class FakeRankings implements PublicRankingRepository {
  docs: Doc[] = [];
  listingMap = new Map<string, Data>();
  teamMap = new Map<string, Data>();
  reads = 0;
  async rankings() {
    this.reads++;
    return this.docs;
  }
  async listings(ids: string[]) {
    return new Map(ids.flatMap((id) => (this.listingMap.has(id) ? [[id, this.listingMap.get(id)!] as const] : [])));
  }
  async teams(ids: string[]) {
    return new Map(ids.flatMap((id) => (this.teamMap.has(id) ? [[id, this.teamMap.get(id)!] as const] : [])));
  }
  /** A team with its listing, the two in step as the rules keep them. */
  listed(id: string, extra: Data = {}) {
    this.listingMap.set(id, { name: id, level: "club", ...extra });
    this.teamMap.set(id, { level: "club", ...extra });
  }
}

class FakeLimiter implements RateLimiter {
  allow = true;
  keys: string[] = [];
  async admit(key: string) {
    this.keys.push(key);
    return this.allow;
  }
}

function setup(opts: { webServerKey?: string; enforceAppCheck?: boolean } = {}) {
  const repo = new FakeRankings();
  const limiter = new FakeLimiter();
  const clock = { now };
  const app = buildApp({
    verifier: new FakeVerifier(),
    users: new FakeUsers(),
    teams: new FakeTeamRepository(),
    now: () => clock.now,
    enforceAppCheck: opts.enforceAppCheck,
    browse: { repo: {} as BrowseRepository, limiter, imageUrl: (p) => p, webServerKey: opts.webServerKey },
    publicRankings: repo,
  });
  const get = (headers: Record<string, string> = {}) => app.inject({ method: "GET", url: "/v1/public/rankings", headers });
  return { app, repo, limiter, get, clock };
}

/** A ranked team as the functions write it (rankingDoc). */
const team = (rank: number, teamId: string, extra: Data = {}): Data => ({ rank, teamId, name: teamId.toUpperCase(), rating: 1300 - rank * 10, wins: 6, losses: rank, ...extra });

/** A ranking doc as the functions write it. */
const ranking = (key: string, teams: Data[], extra: Data = {}): Doc => {
  const [level, division] = key.split("-");
  return { id: key, data: { level, division, teams, minGames: 5, updatedAt: "2026-11-15T09:15:00.000Z", ...extra } };
};

describe("GET /v1/public/rankings", () => {
  it("gives every ranking without a token, by level then division, cached publicly", async () => {
    const { repo, get } = setup();
    for (const id of ["a", "b", "c", "d"]) repo.listed(id);
    repo.docs = [ranking("college-women", [team(1, "c")]), ranking("club-open", [team(1, "d")]), ranking("club-mixed", [team(1, "a"), team(2, "b")])];
    const res = await get();
    expect(res.statusCode).toBe(200);
    expect(res.headers["cache-control"]).toBe("public, max-age=60, s-maxage=300, stale-while-revalidate=300");
    const body = publicRankingsSchema.parse(res.json());
    expect(body.rankings.map((r) => r.key)).toEqual(["club-mixed", "club-open", "college-women"]);
    expect(body.rankings[0]).toEqual({
      key: "club-mixed",
      level: "club",
      division: "mixed",
      minGames: 5,
      updatedAt: "2026-11-15T09:15:00.000Z",
      teams: [
        { rank: 1, teamId: "a", name: "A", rating: 1290, wins: 6, losses: 1 },
        { rank: 2, teamId: "b", name: "B", rating: 1280, wins: 6, losses: 2 },
      ],
    });
  });

  it("never gives a youth ranking, or one whose doc disagrees with its key, or an unknown level", async () => {
    const { repo, get } = setup();
    for (const id of ["a", "y"]) repo.listed(id);
    repo.docs = [
      ranking("youth-mixed", [team(1, "y")]),
      ranking("youth-open", [team(1, "y")]),
      ranking("club-mixed", [team(1, "a")], { level: "youth" }),
      ranking("elite-mixed", [team(1, "a")]),
      ranking("club-open", [team(1, "a")]),
    ];
    const body = (await get()).json();
    expect(body.rankings.map((r: Data) => r.key)).toEqual(["club-open"]);
    expect(JSON.stringify(body)).not.toContain("youth");
  });

  it("leaves out youth teams in adult divisions, by listing or team doc, and numbers the rest again", async () => {
    const { repo, get } = setup();
    repo.listed("a");
    repo.listed("y1", { level: "youth" });
    repo.listed("y2");
    repo.teamMap.set("y2", { level: "youth" });
    repo.listed("y3");
    repo.listingMap.set("y3", { level: "youth" });
    repo.listed("b");
    repo.docs = [ranking("club-mixed", [team(1, "y1"), team(2, "a"), team(3, "y2"), team(4, "y3"), team(5, "b")])];
    const teams = (await get()).json().rankings[0].teams;
    expect(teams.map((t: Data) => [t.rank, t.teamId])).toEqual([
      [1, "a"],
      [2, "b"],
    ]);
  });

  it("leaves out private groups, mismatched or missing listings and drafted league teams; a division left empty goes", async () => {
    const { repo, get } = setup();
    repo.listed("a");
    repo.listed("private", { kind: "community", requiresApproval: true });
    repo.listed("mismatch");
    repo.teamMap.set("mismatch", { kind: "organization", level: "club" });
    repo.teamMap.set("nolisting", { level: "club" });
    repo.listed("league_t1_1");
    repo.docs = [
      ranking("club-mixed", [team(1, "private"), team(2, "a"), team(3, "mismatch"), team(4, "nolisting"), team(5, "league_t1_1"), team(6, "../x")]),
      ranking("club-open", [team(1, "private")]),
    ];
    const body = (await get()).json();
    expect(body.rankings.map((r: Data) => r.key)).toEqual(["club-mixed"]);
    expect(body.rankings[0].teams.map((t: Data) => t.teamId)).toEqual(["a"]);
  });

  it("gives only the visitors' fields, never anything about players", async () => {
    const { repo, get } = setup();
    repo.listed("a");
    repo.docs = [
      ranking("club-mixed", [team(1, "a", { players: [{ uid: "u1", name: "Pat" }], captainUid: "u2", rating: 1234.6, wins: -1 })], {
        createdBy: "u3",
        players: ["Pat"],
      }),
    ];
    const body = publicRankingsSchema.parse((await get()).json());
    expect(body.rankings[0]!.teams[0]).toEqual({ rank: 1, teamId: "a", name: "A", rating: 1235, wins: 0, losses: 1 });
    expect(Object.keys(body.rankings[0]!).sort()).toEqual(["division", "key", "level", "minGames", "teams", "updatedAt"]);
  });

  it("reads Firestore once per five minutes, however many visitors ask", async () => {
    const { repo, get, clock } = setup();
    repo.listed("a");
    repo.docs = [ranking("club-mixed", [team(1, "a")])];
    await Promise.all([get(), get(), get()]);
    await get();
    expect(repo.reads).toBe(1);
    clock.now += publicRankingsCacheMs + 1;
    await get();
    expect(repo.reads).toBe(2);
  });

  it("answers an empty list when nothing is ranked", async () => {
    const { get } = setup();
    expect((await get()).json()).toEqual({ rankings: [] });
  });

  describe("limits", () => {
    it("limits visitors by a hash of their IP, and turns them away when over", async () => {
      const { limiter, get } = setup();
      await get({ "x-forwarded-for": "203.0.113.9" });
      expect(limiter.keys).toHaveLength(1);
      expect(limiter.keys[0]).toMatch(/^ip_[0-9a-f]{32}$/);
      expect(limiter.keys[0]).not.toContain("203.0.113.9");
      limiter.allow = false;
      const res = await get();
      expect(res.statusCode).toBe(429);
    });

    it("lets the website's server past the visitor limit with its key, and counts members by uid", async () => {
      const { limiter, get } = setup({ webServerKey: "server-secret" });
      limiter.allow = false;
      expect((await get({ [webKeyHeader]: "server-secret" })).statusCode).toBe(200);
      expect((await get({ [webKeyHeader]: "wrong" })).statusCode).toBe(429);
      expect((await get({ authorization: "Bearer token:m1" })).statusCode).toBe(200);
      expect(limiter.keys).toHaveLength(1);
    });

    it("needs no App Check, even when it's enforced", async () => {
      const { get } = setup({ enforceAppCheck: true });
      expect((await get()).statusCode).toBe(200);
    });
  });
});
