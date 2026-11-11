import { beforeEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import type { Data, Doc } from "../src/browse/repository.js";
import type { MeRepository } from "../src/me/repository.js";
import { seesEvent } from "../src/me/service.js";
import { FakeTeamRepository, FakeUsers, FakeVerifier } from "./fakes.js";

const now = Date.parse("2026-11-11T12:00:00Z");
const iso = (ms: number) => new Date(ms).toISOString();
const day = 86_400_000;

class FakeMe implements MeRepository {
  profiles = new Map<string, Data>();
  hidden = new Map<string, Data>();
  teams: Doc[] = [];
  events = new Map<string, Doc[]>();
  follows = new Map<string, string[]>();
  posts: Doc[] = [];
  asked: { authors: string[]; before: number | null }[] = [];

  async profile(uid: string) {
    return this.profiles.get(uid) ?? null;
  }
  async privateDetails(uid: string) {
    return this.hidden.get(uid) ?? null;
  }
  async teamsOf(uid: string, limit: number) {
    return this.teams.filter((t) => (t.data.memberIds as string[]).includes(uid)).slice(0, limit);
  }
  async upcomingEvents(teamId: string, at: number, limit: number) {
    return (this.events.get(teamId) ?? []).filter((e) => Date.parse(String(e.data.startsAt)) >= at).slice(0, limit);
  }
  async followedUsers(uid: string) {
    return this.follows.get(uid) ?? [];
  }
  async postsBy(authors: string[], before: number | null, limit: number) {
    this.asked.push({ authors, before });
    return this.posts
      .filter((p) => authors.includes(String(p.data.authorId)) && (!before || Date.parse(String(p.data.createdAt)) < before))
      .slice(0, limit);
  }
}

function setup() {
  const repo = new FakeMe();
  const app = buildApp({
    verifier: new FakeVerifier(),
    users: new FakeUsers(),
    teams: new FakeTeamRepository(),
    now: () => now,
    me: { repo, imageUrl: (p) => `https://img.test/${p}` },
  });
  const get = (url: string, uid?: string) =>
    app.inject({ method: "GET", url, headers: uid ? { authorization: `Bearer token:${uid}:Pat Lee` } : {} });
  return { repo, get };
}

const team = (id: string, data: Data): Doc => ({ id, data: { name: id, kind: "team", ...data } });
const event = (id: string, inDays: number, extra: Data = {}): Doc => ({
  id,
  data: { title: id, startsAt: iso(now + inDays * day), notes: "n", rsvps: { me: "going", x: "maybe" }, ...extra },
});

describe("GET /v1/me/home", () => {
  let t: ReturnType<typeof setup>;
  beforeEach(() => {
    t = setup();
  });

  it("needs a signed-in caller", async () => {
    expect((await t.get("/v1/me/home")).statusCode).toBe(401);
  });

  it("a new web account: no profile yet, so it asks for a username and names them from the token", async () => {
    const res = await t.get("/v1/me/home", "me");
    expect(res.statusCode).toBe(200);
    expect(res.headers["cache-control"]).toBe("private, no-store");
    expect(res.json()).toEqual({
      profile: { id: "me", name: "Pat Lee", private: false, needsUsername: true, visibility: { stats: true, teams: true, games: true } },
      teams: [],
      events: [],
      feed: { posts: [], next: null },
    });
  });

  it("shows their own private profile in full, with the private details", async () => {
    t.repo.profiles.set("me", { name: "Pat", username: "pat", private: true, keywords: ["pat"] });
    t.repo.hidden.set("me", { bio: "secret bio", hometown: "Austin" });
    const { profile } = (await t.get("/v1/me/home", "me")).json();
    expect(profile).toMatchObject({ id: "me", name: "Pat", username: "pat", private: true, bio: "secret bio", hometown: "Austin", needsUsername: false });
    expect(profile).not.toHaveProperty("keywords");
  });

  it("lists only their teams, with their role", async () => {
    t.repo.teams = [
      team("Zeta", { memberIds: ["me"], members: { me: "owner" }, division: "open", level: "club", city: "Austin" }),
      team("Alpha", { memberIds: ["me", "x"], members: { me: "stats" }, kind: "community" }),
      team("Other", { memberIds: ["x"], members: { x: "owner" } }),
    ];
    const { teams } = (await t.get("/v1/me/home", "me")).json();
    expect(teams).toEqual([
      { id: "Alpha", name: "Alpha", kind: "community", role: "stats" },
      { id: "Zeta", name: "Zeta", kind: "team", role: "owner", division: "open", level: "club", city: "Austin" },
    ]);
  });

  it("upcoming events across their teams, soonest first, with their RSVP and no one else's", async () => {
    t.repo.teams = [team("A", { memberIds: ["me"], members: { me: "player" } }), team("B", { memberIds: ["me"], members: { me: "player" } })];
    t.repo.events.set("A", [event("past", -1), event("a2", 2)]);
    t.repo.events.set("B", [event("b1", 1, { rsvps: {} })]);
    const { events } = (await t.get("/v1/me/home", "me")).json();
    expect(events).toEqual([
      { id: "b1", teamId: "B", teamName: "B", title: "b1", startsAt: iso(now + day), notes: "n" },
      { id: "a2", teamId: "A", teamName: "A", title: "a2", startsAt: iso(now + 2 * day), notes: "n", rsvp: "going" },
    ]);
  });

  it("feed: their own posts and those of people they follow, paged with a cursor", async () => {
    t.repo.follows.set("me", ["f1"]);
    t.repo.posts = Array.from({ length: 25 }, (_, i) => ({
      id: `p${i}`,
      data: { authorId: i % 2 ? "f1" : "me", body: "hi", likedBy: ["z"], createdAt: iso(now - (i + 1) * 1000), images: [{ path: "users/f1/posts/p/u/a.jpg" }] },
    }));
    const first = (await t.get("/v1/me/home", "me")).json().feed;
    expect(first.posts).toHaveLength(20);
    expect(first.posts[0]).toMatchObject({ id: "p0", likeCount: 1, images: [{ path: "users/f1/posts/p/u/a.jpg", url: "https://img.test/users/f1/posts/p/u/a.jpg" }] });
    expect(first.posts[0]).not.toHaveProperty("likedBy");
    expect(t.repo.asked[0]).toEqual({ authors: ["me", "f1"], before: null });
    expect(first.next).toBe(now - 20_000);
    const second = (await t.get(`/v1/me/home?before=${first.next}`, "me")).json().feed;
    expect(second.posts.map((p: { id: string }) => p.id)).toEqual(["p20", "p21", "p22", "p23", "p24"]);
    expect(second.next).toBeNull();
  });
});

describe("seesEvent (firestore.rules sees(e))", () => {
  const org = (extra: Data = {}): Data => ({
    kind: "organization",
    memberIds: ["me"],
    members: { me: "player" },
    ...extra,
  });

  it("members of a team or group see every event; non-members none", () => {
    expect(seesEvent({ kind: "team", memberIds: ["me"] }, "me", { audience: ["coach"] })).toBe(true);
    expect(seesEvent({ kind: "community", memberIds: ["me"] }, "me", {})).toBe(true);
    expect(seesEvent({ kind: "team", memberIds: ["x"] }, "me", {})).toBe(false);
  });

  it("a community event goes to its audience", () => {
    expect(seesEvent(org(), "me", { audience: ["everyone"] })).toBe(true);
    expect(seesEvent(org(), "me", { audience: ["player"] })).toBe(true);
    expect(seesEvent(org({ members: { me: "stats" } }), "me", { audience: ["player"] })).toBe(true);
    expect(seesEvent(org(), "me", { audience: ["coach"] })).toBe(false);
    expect(seesEvent(org({ memberRoles: { me: ["r1"] } }), "me", { audience: ["r1"] })).toBe(true);
  });

  it("only a member's first 10 custom roles count, as in the rules", () => {
    const roles = Array.from({ length: 11 }, (_, i) => `r${i}`);
    expect(seesEvent(org({ memberRoles: { me: roles } }), "me", { audience: ["r10"] })).toBe(false);
    expect(seesEvent(org({ memberRoles: { me: roles } }), "me", { audience: ["r9"] })).toBe(true);
  });

  it("event managers see them all", () => {
    expect(seesEvent(org({ members: { me: "owner" } }), "me", { audience: ["coach"] })).toBe(true);
    expect(seesEvent(org({ memberPerms: { me: ["manageEvents"] } }), "me", { audience: ["coach"] })).toBe(true);
  });
});
