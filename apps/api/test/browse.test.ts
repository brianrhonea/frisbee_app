import { beforeEach, describe, expect, it } from "vitest";
import { type AppDeps, buildApp, trustHops } from "../src/app.js";
import type { BrowseRepository, Data, Doc } from "../src/browse/repository.js";
import { webKeyHeader } from "../src/browse/routes.js";
import type { RateLimiter } from "../src/limits/limiter.js";
import { MemoryRateLimiter } from "../src/limits/memory.js";
import { FakeStore, FakeTeamRepository, FakeUsers, FakeVerifier } from "./fakes.js";

const now = Date.parse("2026-11-11T12:00:00Z");
const iso = (ms: number) => new Date(ms).toISOString();

const pickHost = (d: Data): Data => Object.fromEntries(["kind", "requiresApproval", "level", "publicPage"].filter((k) => d[k] !== undefined).map((k) => [k, d[k]]));

class FakeBrowse implements BrowseRepository {
  postsList: Doc[] = [];
  profileMap = new Map<string, Data>();
  listingMap = new Map<string, Data>();
  /** Team docs, as the repository's field mask reads them. */
  teamMap = new Map<string, Data>();
  teamPosts = new Map<string, Doc[]>();
  teamEvents = new Map<string, Doc[]>();
  events: Array<Doc & { teamId: string }> = [];
  tournaments: Doc[] = [];
  queries: string[] = [];

  async posts(before: number | null, authorId?: string) {
    return this.postsList
      .filter((p) => (!authorId || p.data.authorId === authorId) && (!before || Date.parse(String(p.data.createdAt)) < before))
      .sort((a, b) => Date.parse(String(b.data.createdAt)) - Date.parse(String(a.data.createdAt)))
      .slice(0, 20);
  }
  async post(id: string) {
    return this.postsList.find((p) => p.id === id) ?? null;
  }
  async profiles(ids: string[]) {
    return new Map(ids.flatMap((id) => (this.profileMap.has(id) ? [[id, this.profileMap.get(id)!] as const] : [])));
  }
  async listing(id: string) {
    return this.listingMap.get(id) ?? null;
  }
  async listings(ids: string[]) {
    return new Map(ids.flatMap((id) => (this.listingMap.has(id) ? [[id, this.listingMap.get(id)!] as const] : [])));
  }
  async teams(ids: string[]) {
    return new Map(ids.flatMap((id) => (this.teamMap.has(id) ? [[id, this.teamMap.get(id)!] as const] : [])));
  }
  /** A team (or group) with its listing, the two in step as the rules keep them. */
  listed(id: string, listing: Data, team: Data = pickHost(listing)) {
    this.listingMap.set(id, listing);
    this.teamMap.set(id, team);
  }
  async publicTeamPosts(id: string) {
    return this.teamPosts.get(id) ?? [];
  }
  async upcomingTeamEvents(id: string) {
    return this.teamEvents.get(id) ?? [];
  }
  async upcomingEvents() {
    return this.events;
  }
  async upcomingTournaments() {
    return this.tournaments;
  }
  async searchProfiles(key: string) {
    this.queries.push(`profiles:${key}`);
    return [...this.profileMap].map(([id, data]) => ({ id, data }));
  }
  async searchListings(key: string) {
    this.queries.push(`listings:${key}`);
    return [...this.listingMap].map(([id, data]) => ({ id, data }));
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

function setup(opts: { enforceAppCheck?: boolean; webServerKey?: string; trustProxy?: AppDeps["trustProxy"]; limiter?: RateLimiter } = {}) {
  const repo = new FakeBrowse();
  const fake = new FakeLimiter();
  const limiter = opts.limiter ?? fake;
  const store = new FakeStore();
  const app = buildApp({
    verifier: new FakeVerifier(),
    users: new FakeUsers(),
    teams: new FakeTeamRepository(),
    now: () => now,
    store,
    writeLimits: false,
    enforceAppCheck: opts.enforceAppCheck,
    trustProxy: opts.trustProxy,
    browse: { repo, limiter, imageUrl: (p) => `https://img.test/${p}`, webServerKey: opts.webServerKey, photoBuckets: ["x"] },
  });
  const get = (url: string, headers: Record<string, string> = {}, remoteAddress?: string) =>
    app.inject({ method: "GET", url, headers, ...(remoteAddress && { remoteAddress }) });
  return { app, repo, limiter: fake, store, get };
}

const member = { authorization: "Bearer token:m1" };

const post = (id: string, authorId: string, extra: Data = {}): Doc => ({
  id,
  data: {
    authorId,
    authorName: authorId,
    body: `post ${id}`,
    likedBy: ["a", "b"],
    repostedBy: ["c"],
    createdAt: iso(now - Number(id.replace(/\D/g, "") || 0) * 1000),
    ...extra,
  },
});

describe("public reads", () => {
  let t: ReturnType<typeof setup>;
  beforeEach(() => {
    t = setup();
    t.repo.profileMap.set("pub", { name: "Pat", username: "pat", bio: "hi", private: false, keywords: ["pat"], email: "x" });
    t.repo.profileMap.set("priv", { name: "Sam", username: "sam", bio: "secret", private: true });
  });

  it("shows the community feed without private authors or reposts of them", async () => {
    t.repo.postsList = [
      post("p1", "pub", { images: [{ path: "users/pub/posts/p1/a/x.jpg", name: "x.jpg" }] }),
      post("p2", "priv"),
      post("p3", "pub", { repostOf: { postId: "p2", authorId: "priv", authorName: "Sam" } }),
      post("p4", "ghost"),
    ];
    const res = await t.get("/v1/public/feed");
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.posts.map((p: { id: string }) => p.id)).toEqual(["p1"]);
    expect(body.posts[0]).toMatchObject({
      likeCount: 2,
      repostCount: 1,
      images: [{ path: "users/pub/posts/p1/a/x.jpg", url: "https://img.test/users/pub/posts/p1/a/x.jpg" }],
    });
    expect(body.posts[0]).not.toHaveProperty("likedBy");
    expect(body.next).toBeNull();
  });

  it("leaves a workout's route out", async () => {
    t.repo.postsList = [post("p1", "pub", { kind: "workout", workout: { activity: "run", route: { points: [1, 2] } } })];
    const [p] = (await t.get("/v1/public/feed")).json().posts;
    expect(p.workout).toEqual({ activity: "run" });
  });

  it("gives visitors one page: no cursor, and a cursor is ignored", async () => {
    t.repo.postsList = Array.from({ length: 25 }, (_, i) => post(`p${i + 1}`, "pub"));
    const first = (await t.get("/v1/public/feed")).json();
    expect(first.posts).toHaveLength(20);
    expect(first.next).toBeNull();
    const asked = (await t.get(`/v1/public/feed?before=${now - 20_000}`)).json();
    expect(asked.posts.map((p: { id: string }) => p.id)).toEqual(first.posts.map((p: { id: string }) => p.id));
  });

  it("shows a repost with its original as it is now, or null once deleted", async () => {
    t.repo.profileMap.set("pub2", { name: "Lee", private: false });
    t.repo.postsList = [
      post("p1", "pub2"),
      post("p2", "pub", { kind: "repost", body: "note", repostOf: { postId: "p1", authorId: "pub2", authorName: "Lee" } }),
      post("p3", "pub", { kind: "repost", repostOf: { postId: "gone", authorId: "pub2", authorName: "Lee" } }),
    ];
    const posts = (await t.get("/v1/public/feed")).json().posts;
    const byId = Object.fromEntries(posts.map((p: { id: string }) => [p.id, p]));
    expect(byId.p2.original).toMatchObject({ id: "p1", body: "post p1", likeCount: 2 });
    expect(byId.p2.original).not.toHaveProperty("likedBy");
    expect(byId.p3.original).toBeNull();
    expect(byId.p1).not.toHaveProperty("original");
  });

  it("pages the community feed for members only (GET /v1/feed)", async () => {
    t.repo.postsList = Array.from({ length: 25 }, (_, i) => post(`p${i + 1}`, "pub"));
    expect((await t.get("/v1/feed")).statusCode).toBe(401);
    const auth = { authorization: "Bearer token:m1" };
    const first = await t.get("/v1/feed", auth);
    expect(first.headers["cache-control"]).toBe("private, no-store");
    const body = first.json();
    expect(body.posts).toHaveLength(20);
    expect(body.next).toBe(now - 20_000);
    const second = (await t.get(`/v1/feed?before=${body.next}`, auth)).json();
    expect(second.posts.map((p: { id: string }) => p.id)).toEqual(["p21", "p22", "p23", "p24", "p25"]);
    expect(second.next).toBeNull();
  });

  it("refuses a private author's post", async () => {
    t.repo.postsList = [post("p2", "priv")];
    expect((await t.get("/v1/public/posts/p2")).statusCode).toBe(404);
    expect((await t.get("/v1/public/posts/..%2Fsecret")).statusCode).toBe(404);
  });

  it("shows a public profile with its posts, and only the card of a private one", async () => {
    t.repo.postsList = [post("p1", "pub"), post("p2", "priv")];
    const pub = (await t.get("/v1/public/players/pub", member)).json();
    expect(pub.profile).toMatchObject({ id: "pub", name: "Pat", bio: "hi" });
    expect(pub.profile).not.toHaveProperty("keywords");
    expect(pub.profile).not.toHaveProperty("email");
    expect(pub.posts.map((p: { id: string }) => p.id)).toEqual(["p1"]);

    const priv = (await t.get("/v1/public/players/priv", member)).json();
    expect(priv).toEqual({ profile: { id: "priv", name: "Sam", username: "sam", private: true }, posts: [], next: null });
    expect((await t.get("/v1/public/players/nobody", member)).statusCode).toBe(404);
  });

  it("treats a team whose doc is missing or disagrees with its listing as private", async () => {
    t.repo.listed("gone", { name: "Gone", level: "club" });
    t.repo.teamMap.delete("gone");
    t.repo.listed("stale", { name: "Stale", kind: "community" }, { kind: "community", requiresApproval: true });
    t.repo.listed("kind", { name: "Kind", kind: "team" }, { kind: "community" });
    for (const id of ["gone", "stale", "kind"]) {
      t.repo.teamPosts.set(id, [{ id: "tp", data: { title: "hi", public: true } }]);
      t.repo.teamEvents.set(id, [{ id: "e", data: { title: "practice" } }]);
      const body = (await t.get(`/v1/public/teams/${id}`)).json();
      expect(body.posts, id).toEqual([]);
      expect(body.events, id).toEqual([]);
    }
    t.repo.events = ["gone", "stale", "kind"].map((id) => ({ id: `e_${id}`, teamId: id, data: { title: "x" } }));
    t.repo.tournaments = [{ id: "s_1", data: { groupId: "stale", name: "Cup" } }];
    const events = (await t.get("/v1/public/events")).json();
    expect(events).toEqual({ events: [], tournaments: [] });
  });

  it("shows a team whose public page is off as its card only, by either document", async () => {
    t.repo.listed("off", { name: "Off", level: "club", publicPage: false, keywords: ["off"] });
    // The listing is stale: the team doc says off.
    t.repo.listed("stale", { name: "Stale", level: "club", keywords: ["off"] }, { level: "club", publicPage: false });
    for (const id of ["off", "stale"]) {
      t.repo.teamPosts.set(id, [{ id: "tp", data: { title: "hi", public: true } }]);
      t.repo.teamEvents.set(id, [{ id: "e", data: { title: "practice" } }]);
      const body = (await t.get(`/v1/public/teams/${id}`)).json();
      expect(body.posts, id).toEqual([]);
      expect(body.events, id).toEqual([]);
      expect(body.team, id).toMatchObject({ id, level: "club", publicPage: false });
    }
    t.repo.events = ["off", "stale"].map((id) => ({ id: `e_${id}`, teamId: id, data: { title: "x" } }));
    expect((await t.get("/v1/public/events")).json().events).toEqual([]);
    // Still found by name, as its card.
    const found = (await t.get("/v1/public/teams?q=off")).json().teams;
    expect(found.map((x: Data) => [x.id, x.publicPage])).toEqual([
      ["off", false],
      ["stale", false],
    ]);
  });

  it("shows visitors a youth team's card only: no posts, events or location", async () => {
    const location = { address: "1 Field Rd", lat: 1, lng: 2 };
    t.repo.listed("y", { name: "Juniors", division: "mixed", level: "youth", city: "Austin", description: "U17", location, keywords: ["juniors"] });
    // Youth by the team doc alone counts too.
    t.repo.listed("y2", { name: "Juniors 2", level: "club", location, keywords: ["juniors"] }, { level: "youth" });
    for (const id of ["y", "y2"]) {
      t.repo.teamPosts.set(id, [{ id: "tp", data: { title: "Practice moved", public: true } }]);
      t.repo.teamEvents.set(id, [{ id: "e", data: { title: "Game", location: "Field 3" } }]);
      const body = (await t.get(`/v1/public/teams/${id}`)).json();
      expect(body.posts, id).toEqual([]);
      expect(body.events, id).toEqual([]);
      expect(body.team, id).not.toHaveProperty("location");
      expect(body.team.level, id).toBe("youth");
    }
    expect((await t.get("/v1/public/teams/y")).json().team).toEqual({ id: "y", name: "Juniors", division: "mixed", level: "youth", city: "Austin", description: "U17" });
    t.repo.events = [
      { id: "e1", teamId: "y", data: { title: "Game" } },
      { id: "e2", teamId: "y2", data: { title: "Game" } },
    ];
    expect((await t.get("/v1/public/events")).json().events).toEqual([]);
    const found = (await t.get("/v1/public/teams?q=juniors")).json().teams;
    expect(found.map((x: Data) => x.id)).toEqual(["y", "y2"]);
    for (const x of found) expect(x).not.toHaveProperty("location");
  });

  it("names a team post's author only when their profile is public, and never by uid", async () => {
    t.repo.listed("t", { name: "Haze", level: "club" });
    t.repo.teamPosts.set("t", [
      { id: "a", data: { title: "A", public: true, authorId: "pub", authorName: "Pat" } },
      { id: "b", data: { title: "B", public: true, authorId: "priv", authorName: "Sam" } },
      { id: "c", data: { title: "C", public: true, authorId: "ghost", authorName: "Gus" } },
    ]);
    const res = await t.get("/v1/public/teams/t");
    expect(res.json().posts).toEqual([
      { id: "a", title: "A", authorName: "Pat" },
      { id: "b", title: "B" },
      { id: "c", title: "C" },
    ]);
    for (const leak of ["authorId", "Sam", "Gus", "\"pub\"", "priv"]) expect(res.body).not.toContain(leak);
  });

  it("keeps a league's drafted teams out of the finder and their names off their pages and events", async () => {
    t.repo.listed("league_l1_d1", { name: "Team Alex - Thursday Night", level: "league", keywords: ["team"] });
    t.repo.listed("t", { name: "Team Haze", level: "club", keywords: ["team"] });
    expect((await t.get("/v1/public/teams?q=team")).json().teams.map((x: Data) => x.id)).toEqual(["t"]);
    const page = await t.get("/v1/public/teams/league_l1_d1");
    expect(page.json().team.name).toBe("League team");
    expect(page.body).not.toContain("Alex");
    t.repo.events = [{ id: "e1", teamId: "league_l1_d1", data: { title: "Game" } }];
    const events = await t.get("/v1/public/events");
    expect(events.json().events[0].teamName).toBe("League team");
    expect(events.body).not.toContain("Alex");
  });

  it("hides a private group's posts and events but shows its listing", async () => {
    t.repo.listed("g", { name: "Secret Club", kind: "community", requiresApproval: true, keywords: ["s"] });
    t.repo.teamPosts.set("g", [{ id: "tp", data: { title: "hi", public: true } }]);
    t.repo.teamEvents.set("g", [{ id: "e", data: { title: "practice" } }]);
    const body = (await t.get("/v1/public/teams/g")).json();
    expect(body).toEqual({ team: { id: "g", name: "Secret Club", kind: "community", requiresApproval: true }, posts: [], events: [] });
  });

  it("shows a team's public posts and events", async () => {
    t.repo.listed("t", { name: "Haze", division: "open", level: "club" });
    t.repo.teamPosts.set("t", [
      { id: "a", data: { title: "Win!", public: true, reactions: { u: "🔥" } } },
      { id: "b", data: { title: "Members only", public: false } },
    ]);
    t.repo.teamEvents.set("t", [{ id: "e", data: { title: "Game", startsAt: iso(now + 1000), rsvps: { u: "yes" } } }]);
    const body = (await t.get("/v1/public/teams/t")).json();
    expect(body.posts).toEqual([{ id: "a", title: "Win!" }]);
    expect(body.events).toEqual([{ id: "e", title: "Game", startsAt: iso(now + 1000) }]);
  });

  it("puts a team's pinned public posts first, without who pinned them (F24)", async () => {
    t.repo.listed("t", { name: "Haze", level: "club" });
    t.repo.teamPosts.set("t", [
      { id: "new", data: { title: "New", public: true, createdAt: iso(now) } },
      { id: "old", data: { title: "Old", public: true, createdAt: iso(now - 9000), pinnedAt: iso(now - 10), pinnedBy: "coach" } },
      { id: "mid", data: { title: "Mid", public: true, createdAt: iso(now - 5000) } },
    ]);
    const res = await t.get("/v1/public/teams/t");
    expect(res.json().posts.map((x: Data) => x.id)).toEqual(["old", "new", "mid"]);
    expect(res.json().posts[0].pinnedAt).toBe(iso(now - 10));
    expect(res.body).not.toContain("pinnedBy");
  });

  it("lists events and tournaments, without private groups'", async () => {
    t.repo.listed("t", { name: "Haze" });
    t.repo.listed("g", { name: "Secret", kind: "community", requiresApproval: true });
    t.repo.events = [
      { id: "e1", teamId: "t", data: { title: "Open game" } },
      { id: "e2", teamId: "g", data: { title: "Secret practice" } },
    ];
    t.repo.tournaments = [
      { id: "t_1", data: { groupId: "t", name: "Cup" } },
      { id: "g_1", data: { groupId: "g", name: "Secret Cup" } },
    ];
    const body = (await t.get("/v1/public/events")).json();
    expect(body.events).toEqual([{ id: "e1", teamId: "t", teamName: "Haze", title: "Open game" }]);
    expect(body.tournaments.map((x: { name: string }) => x.name)).toEqual(["Cup"]);
  });

  it("searches by the query's longest word, showing private players as cards", async () => {
    const body = (await t.get("/v1/public/search?q=Pat%20Smithson", member)).json();
    expect(t.repo.queries).toEqual(["profiles:smithson", "listings:smithson"]);
    expect(body.players).toContainEqual({ id: "priv", name: "Sam", username: "sam", private: true });
    expect(body.players.find((p: { id: string }) => p.id === "pub")).not.toHaveProperty("bio");
  });

  it("answers an empty search without querying", async () => {
    expect((await t.get("/v1/public/search?q=%20%20", member)).json()).toEqual({ players: [], teams: [] });
    expect(t.repo.queries).toEqual([]);
  });

  it("is cacheable by anyone", async () => {
    const res = await t.get("/v1/public/feed");
    expect(res.headers["cache-control"]).toContain("public");
    expect(res.headers["cache-control"]).toContain("s-maxage=60");
  });

  it("keeps members-only reads out of shared caches", async () => {
    const res = await t.get("/v1/public/search?q=pat", member);
    expect(res.headers["cache-control"]).toBe("private, no-store");
  });

  it("shows visitors the feed, team pages, the team finder and events, but not players or search", async () => {
    t.repo.listed("t", { name: "Haze" });
    for (const url of ["/v1/public/feed", "/v1/public/teams/t", "/v1/public/teams?q=haze", "/v1/public/events"]) {
      expect((await t.get(url)).statusCode).toBe(200);
    }
    for (const url of ["/v1/public/search?q=pat", "/v1/public/players/pub"]) {
      expect((await t.get(url)).statusCode).toBe(401);
      expect((await t.get(url, { authorization: "Bearer junk" })).statusCode).toBe(401);
    }
  });
});

describe("public route access", () => {
  it("needs no App Check even when it's enforced", async () => {
    const { get, app } = setup({ enforceAppCheck: true });
    expect((await get("/v1/public/feed")).statusCode).toBe(200);
    // Other routes still need it.
    const res = await app.inject({ method: "POST", url: "/v1/teams", payload: {}, headers: { authorization: "Bearer token:u1" } });
    expect(res.statusCode).toBe(401);
  });

  it("treats a bad token as a visitor", async () => {
    const { get } = setup();
    expect((await get("/v1/public/feed", { authorization: "Bearer junk" })).statusCode).toBe(200);
  });

  it("keys visitors on the address the proxy saw, not a spoofed X-Forwarded-For", async () => {
    // Off (local runs): the socket's address, whatever the header says.
    const off = setup();
    await off.get("/v1/public/feed", { "x-forwarded-for": "6.6.6.6" }, "203.0.113.7");
    await off.get("/v1/public/feed", { "x-forwarded-for": "7.7.7.7" }, "203.0.113.7");
    await off.get("/v1/public/feed", {}, "6.6.6.6");
    expect(off.limiter.keys[0]).toBe(off.limiter.keys[1]);
    expect(off.limiter.keys[0]).not.toBe(off.limiter.keys[2]);
    // On Cloud Run (one trusted hop): the address its front end appended.
    const run = setup({ trustProxy: trustHops(1) });
    await run.get("/v1/public/feed", { "x-forwarded-for": "6.6.6.6, 203.0.113.7" }, "169.254.1.1");
    await run.get("/v1/public/feed", { "x-forwarded-for": "8.8.8.8, 203.0.113.7" }, "169.254.1.1");
    await run.get("/v1/public/feed", { "x-forwarded-for": "6.6.6.6" }, "169.254.1.1");
    expect(run.limiter.keys[0]).toBe(run.limiter.keys[1]);
    expect(run.limiter.keys[0]).not.toBe(run.limiter.keys[2]);
  });

  it("gives a spoofing visitor no fresh bucket, and can't spend another address's", async () => {
    const shared = new MemoryRateLimiter(() => now);
    const { get } = setup({ trustProxy: trustHops(1), limiter: { admit: async (k, l) => shared.admit(k, l) } });
    let last = 0;
    for (let i = 0; i < 200 && last !== 429; i++) {
      last = (await get("/v1/public/feed", { "x-forwarded-for": `10.0.0.${i % 250}, 203.0.113.7` }, "169.254.1.1")).statusCode;
    }
    expect(last).toBe(429);
    // The address the attacker named in its first hops still gets in.
    expect((await get("/v1/public/feed", { "x-forwarded-for": "10.0.0.5" }, "169.254.1.1")).statusCode).toBe(200);
    expect((await get("/v1/public/feed", { "x-forwarded-for": "198.51.100.1, 10.0.0.5" }, "169.254.1.1")).statusCode).toBe(200);
  });

  it("limits visitors by hashed IP, and members in memory (never the shared mute)", async () => {
    const { get, limiter } = setup();
    await get("/v1/public/feed", { "x-forwarded-for": "203.0.113.9, 10.0.0.1" });
    await get("/v1/public/feed", { authorization: "Bearer token:u1" });
    await get("/v1/public/search?q=pat", { authorization: "Bearer token:u2", "x-forwarded-for": "203.0.113.9" });
    expect(limiter.keys).toHaveLength(1);
    expect(limiter.keys[0]).toMatch(/^ip_[0-9a-f]{32}$/);
    expect(limiter.keys[0]).not.toContain("203");
    let last = 0;
    for (let i = 0; i < 121; i++) last = (await get("/v1/public/search?q=pat", { authorization: "Bearer token:u3" })).statusCode;
    expect(last).toBe(429);
  });

  it("needs App Check for members-only reads when it's enforced", async () => {
    const { get } = setup({ enforceAppCheck: true });
    expect((await get("/v1/public/search?q=pat", { authorization: "Bearer token:u1" })).statusCode).toBe(401);
  });

  it("turns away someone over the limit", async () => {
    const { get, limiter } = setup();
    limiter.allow = false;
    const res = await get("/v1/public/feed");
    expect(res.statusCode).toBe(429);
    expect(res.json().error.code).toBe("resource_exhausted");
  });

  it("lets the website's server through with its key, and only the right key", async () => {
    const { get, limiter } = setup({ webServerKey: "s3cret-key" });
    limiter.allow = false;
    expect((await get("/v1/public/feed", { [webKeyHeader]: "s3cret-key" })).statusCode).toBe(200);
    expect((await get("/v1/public/feed", { [webKeyHeader]: "wrong" })).statusCode).toBe(429);
    // The key doesn't open members-only reads.
    expect((await get("/v1/public/search?q=pat", { [webKeyHeader]: "s3cret-key" })).statusCode).toBe(401);
  });

  it("isn't served when the app is built without browse", async () => {
    const app = buildApp({ verifier: new FakeVerifier(), users: new FakeUsers(), teams: new FakeTeamRepository() });
    expect((await app.inject({ url: "/v1/public/feed" })).statusCode).toBe(404);
  });
});

describe("visitor access to events, the team finder and rosters", () => {
  let t: ReturnType<typeof setup>;
  beforeEach(() => {
    t = setup();
  });

  it("serves events without a token, cacheable, limited by IP, with only public event and tournament fields", async () => {
    t.repo.listed("t", { name: "Haze" });
    t.repo.events = [
      { id: "e1", teamId: "t", data: { title: "Open game", location: "Field 3", notes: "Bring both", rsvps: { u: "yes" }, createdBy: "u" } },
    ];
    t.repo.tournaments = [
      { id: "t_1", data: { groupId: "t", tournamentId: "1", name: "Cup", status: "scheduled", format: "pools", organizerIds: ["u"], secret: "x" } },
    ];
    const res = await t.get("/v1/public/events", { "x-forwarded-for": "198.51.100.7" });
    expect(res.statusCode).toBe(200);
    expect(res.headers["cache-control"]).toContain("public");
    expect(t.limiter.keys).toHaveLength(1);
    const body = res.json();
    expect(body.events).toEqual([
      { id: "e1", teamId: "t", teamName: "Haze", title: "Open game", location: "Field 3", notes: "Bring both" },
    ]);
    expect(body.tournaments).toEqual([
      { id: "t_1", groupId: "t", tournamentId: "1", name: "Cup", status: "scheduled", format: "pools" },
    ]);
  });

  it("turns away a visitor over the limit on every new public route", async () => {
    t.limiter.allow = false;
    for (const url of ["/v1/public/events", "/v1/public/teams?q=haze", "/v1/public/teams/t/roster"]) {
      expect((await t.get(url)).statusCode).toBe(429);
    }
  });

  it("finds teams and groups by name without players or search keywords", async () => {
    t.repo.profileMap.set("pub", { name: "Haze Fan", username: "hazefan", keywords: ["haze"] });
    t.repo.listed("t", { name: "Haze", division: "open", level: "club", keywords: ["haze"], ownerId: "o", memberIds: ["o"] });
    t.repo.listed("g", {
      name: "Haze Secret",
      kind: "community",
      requiresApproval: true,
      keywords: ["haze"],
    });
    const res = await t.get("/v1/public/teams?q=The%20Haze");
    expect(res.statusCode).toBe(200);
    expect(res.headers["cache-control"]).toContain("public");
    expect(t.repo.queries).toEqual(["listings:haze"]);
    const body = res.json();
    expect(Object.keys(body)).toEqual(["teams"]);
    expect(body.teams).toEqual([
      { id: "t", name: "Haze", division: "open", level: "club" },
      // A private group's listing, as its own public page shows it: nothing more.
      { id: "g", name: "Haze Secret", kind: "community", requiresApproval: true },
    ]);
    const page = (await t.get("/v1/public/teams/g")).json();
    expect(body.teams[1]).toEqual(page.team);
  });

  it("answers an empty or junk team search without querying, and refuses a huge one", async () => {
    expect((await t.get("/v1/public/teams")).json()).toEqual({ teams: [] });
    expect((await t.get("/v1/public/teams?q=%20-%20")).json()).toEqual({ teams: [] });
    expect(t.repo.queries).toEqual([]);
    const res = await t.get(`/v1/public/teams?q=${"a".repeat(101)}`);
    expect(res.statusCode).toBe(400);
    expect((await t.get("/v1/public/teams?q=a&q=b")).statusCode).toBe(400);
  });

  function seedTeam(id: string, team: Data, listing: Data = team) {
    t.store.put(`teams/${id}`, {
      ownerId: "o",
      memberIds: ["o", "pat", "sam"],
      members: { o: "owner", pat: "player", sam: "player" },
      memberNames: { o: "Olive" },
      memberPerms: { pat: ["keepStats"] },
      paid: { pat: true },
      ...team,
    });
    t.store.put(`teamDirectory/${id}`, listing);
    t.store.put(`teams/${id}/roster/a`, { name: "Pat Public", number: 7, position: "handler", userId: "pat", email: "pat@x.test", paid: true });
    t.store.put(`teams/${id}/roster/b`, { name: "Sam Private", number: 3, position: "cutter", userId: "sam", birthDate: "2001-01-01" });
    t.store.put(`teams/${id}/roster/c`, { name: "Una Unlinked", phone: "555", position: "goalie" });
  }

  it("shows an adult club team's roster without a token: names, numbers and positions only", async () => {
    t.store.put("profiles/pat", {
      name: "Pat P",
      username: "pat",
      photoUrl: "https://lh3.googleusercontent.com/a/pat",
      email: "pat@x.test",
    });
    t.store.put("profiles/sam", { name: "Sam S", username: "sam", photoUrl: "https://firebasestorage.googleapis.com/s.jpg", private: true });
    seedTeam("t", { name: "Haze", division: "open", level: "club" });
    const res = await t.get("/v1/public/teams/t/roster");
    expect(res.statusCode).toBe(200);
    expect(res.headers["cache-control"]).toContain("public");
    expect(res.json()).toEqual({
      players: [
        // Linked to a private profile: not named at all.
        { name: "Player", number: 3, position: "cutter" },
        { name: "Pat Public", number: 7, position: "handler", username: "pat", photoUrl: "https://lh3.googleusercontent.com/a/pat" },
        { name: "Una Unlinked" },
      ],
    });
    const text = res.body;
    for (const leak of ["Sam", "pat@x.test", "2001", "555", "keepStats", "Olive", "\"o\"", "userId", "uid", "\"id\""]) {
      expect(text).not.toContain(leak);
    }
  });

  it("doesn't name or tie a profile that hides its teams (or is gone) to the roster", async () => {
    t.store.put("profiles/pat", { name: "Pat", username: "pat", photoUrl: "https://firebasestorage.googleapis.com/v0/b/x/o/p.jpg", visibility: { teams: false } });
    seedTeam("t", { name: "Haze", level: "league" });
    const players = (await t.get("/v1/public/teams/t/roster")).json().players;
    expect(players).toEqual([
      { name: "Player", number: 3, position: "cutter" },
      { name: "Player", number: 7, position: "handler" },
      { name: "Una Unlinked" },
    ]);
  });

  it("drops a picture from any other host or bucket", async () => {
    seedTeam("t", { name: "Haze", level: "college" });
    for (const url of [
      "https://tracker.example/p.jpg",
      "https://firebasestorage.googleapis.com/v0/b/someone-elses-bucket/o/p.jpg",
      "https://storage.googleapis.com/someone-elses-bucket/p.jpg",
      // A bucket picture that isn't their own profile folder's is dropped too.
      "https://storage.googleapis.com/x/p.jpg",
      "https://firebasestorage.googleapis.com/v0/b/x/o/p.jpg",
      "https://evil.googleusercontent.com/p.jpg",
      "http://lh3.googleusercontent.com/p.jpg",
    ]) {
      t.store.put("profiles/pat", { name: "Pat", photoUrl: url });
      const [, pat] = (await t.get("/v1/public/teams/t/roster")).json().players;
      expect(pat, url).toEqual({ name: "Pat Public", number: 7, position: "handler" });
    }
    for (const url of ["https://lh3.googleusercontent.com/a/p"]) {
      t.store.put("profiles/pat", { name: "Pat", photoUrl: url });
      const [, pat] = (await t.get("/v1/public/teams/t/roster")).json().players;
      expect(pat.photoUrl, url).toBe(url);
    }
  });

  it("refuses a league's drafted team, and a team in a youth division of a league", async () => {
    seedTeam("league_l1_d1", { name: "Team Alex - Thursday", level: "league", leagueId: "l1" });
    t.store.put("tournaments/l1", { kind: "league", divisions: [{ id: "u17", division: "mixed", level: "youth" }, { id: "open", division: "open", level: "club" }] });
    seedTeam("entered", { name: "Juniors", level: "club", leagueId: "l1" });
    t.store.put("tournaments/l1/entries/entered", { divisionId: "u17", status: "accepted" });
    seedTeam("noentry", { name: "Maybe", level: "club", leagueId: "l1" });
    seedTeam("adult", { name: "Adults", level: "club", leagueId: "l1" });
    t.store.put("tournaments/l1/entries/adult", { divisionId: "open", status: "accepted" });
    for (const id of ["league_l1_d1", "entered", "noentry"]) expect((await t.get(`/v1/public/teams/${id}/roster`)).statusCode, id).toBe(404);
    expect((await t.get("/v1/public/teams/adult/roster")).statusCode).toBe(200);
  });

  it("refuses youth teams, teams without a level, groups and private groups", async () => {
    seedTeam("youth", { name: "Juniors", level: "youth" });
    seedTeam("nolevel", { name: "Old team" });
    seedTeam("community", { name: "Pickup", kind: "community", level: "pickup" });
    seedTeam("org", { name: "School", kind: "organization", level: "college" });
    seedTeam("private", { name: "Secret", kind: "community", level: "club", requiresApproval: true });
    for (const id of ["youth", "nolevel", "community", "org", "private", "missing", "..%2Fx"]) {
      const res = await t.get(`/v1/public/teams/${id}/roster`);
      expect(res.statusCode, id).toBe(404);
      expect(res.body).not.toContain("Pat Public");
    }
  });

  it("refuses a team whose public page is off, by its doc or its listing", async () => {
    seedTeam("off", { name: "Off", level: "club", publicPage: false });
    seedTeam("doc", { name: "Doc", level: "club", publicPage: false }, { name: "Doc", level: "club" });
    seedTeam("listing", { name: "Listing", level: "club" }, { name: "Listing", level: "club", publicPage: false });
    for (const id of ["off", "doc", "listing"]) expect((await t.get(`/v1/public/teams/${id}/roster`)).statusCode, id).toBe(404);
  });

  it("refuses when the team doc and its listing disagree", async () => {
    seedTeam("a", { name: "A", level: "youth" }, { name: "A", level: "club" });
    seedTeam("b", { name: "B", level: "club" }, { name: "B", level: "youth" });
    seedTeam("c", { name: "C", level: "club" });
    t.store.docs.delete("teamDirectory/c");
    for (const id of ["a", "b", "c"]) expect((await t.get(`/v1/public/teams/${id}/roster`)).statusCode, id).toBe(404);
  });
});
