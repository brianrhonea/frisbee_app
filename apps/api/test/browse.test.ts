import { beforeEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import type { BrowseRepository, Data, Doc } from "../src/browse/repository.js";
import { webKeyHeader } from "../src/browse/routes.js";
import type { RateLimiter } from "../src/limits/limiter.js";
import { FakeTeamRepository, FakeUsers, FakeVerifier } from "./fakes.js";

const now = Date.parse("2026-11-11T12:00:00Z");
const iso = (ms: number) => new Date(ms).toISOString();

class FakeBrowse implements BrowseRepository {
  postsList: Doc[] = [];
  profileMap = new Map<string, Data>();
  listingMap = new Map<string, Data>();
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

function setup(opts: { enforceAppCheck?: boolean; webServerKey?: string } = {}) {
  const repo = new FakeBrowse();
  const limiter = new FakeLimiter();
  const app = buildApp({
    verifier: new FakeVerifier(),
    users: new FakeUsers(),
    teams: new FakeTeamRepository(),
    now: () => now,
    enforceAppCheck: opts.enforceAppCheck,
    browse: { repo, limiter, imageUrl: (p) => `https://img.test/${p}`, webServerKey: opts.webServerKey },
  });
  const get = (url: string, headers: Record<string, string> = {}) => app.inject({ method: "GET", url, headers });
  return { app, repo, limiter, get };
}

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

  it("refuses a private author's post", async () => {
    t.repo.postsList = [post("p2", "priv")];
    expect((await t.get("/v1/public/posts/p2")).statusCode).toBe(404);
    expect((await t.get("/v1/public/posts/..%2Fsecret")).statusCode).toBe(404);
  });

  it("shows a public profile with its posts, and only the card of a private one", async () => {
    t.repo.postsList = [post("p1", "pub"), post("p2", "priv")];
    const pub = (await t.get("/v1/public/players/pub")).json();
    expect(pub.profile).toMatchObject({ id: "pub", name: "Pat", bio: "hi" });
    expect(pub.profile).not.toHaveProperty("keywords");
    expect(pub.profile).not.toHaveProperty("email");
    expect(pub.posts.map((p: { id: string }) => p.id)).toEqual(["p1"]);

    const priv = (await t.get("/v1/public/players/priv")).json();
    expect(priv).toEqual({ profile: { id: "priv", name: "Sam", username: "sam", private: true }, posts: [], next: null });
    expect((await t.get("/v1/public/players/nobody")).statusCode).toBe(404);
  });

  it("hides a private group's posts and events but shows its listing", async () => {
    t.repo.listingMap.set("g", { name: "Secret Club", kind: "community", requiresApproval: true, keywords: ["s"] });
    t.repo.teamPosts.set("g", [{ id: "tp", data: { title: "hi", public: true } }]);
    t.repo.teamEvents.set("g", [{ id: "e", data: { title: "practice" } }]);
    const body = (await t.get("/v1/public/teams/g")).json();
    expect(body).toEqual({ team: { id: "g", name: "Secret Club", kind: "community", requiresApproval: true }, posts: [], events: [] });
  });

  it("shows a team's public posts and events", async () => {
    t.repo.listingMap.set("t", { name: "Haze", division: "open", level: "club" });
    t.repo.teamPosts.set("t", [
      { id: "a", data: { title: "Win!", public: true, reactions: { u: "🔥" } } },
      { id: "b", data: { title: "Members only", public: false } },
    ]);
    t.repo.teamEvents.set("t", [{ id: "e", data: { title: "Game", startsAt: iso(now + 1000), rsvps: { u: "yes" } } }]);
    const body = (await t.get("/v1/public/teams/t")).json();
    expect(body.posts).toEqual([{ id: "a", title: "Win!" }]);
    expect(body.events).toEqual([{ id: "e", title: "Game", startsAt: iso(now + 1000) }]);
  });

  it("lists events and tournaments, without private groups'", async () => {
    t.repo.listingMap.set("t", { name: "Haze" });
    t.repo.listingMap.set("g", { name: "Secret", kind: "community", requiresApproval: true });
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
    const body = (await t.get("/v1/public/search?q=Pat%20Smithson")).json();
    expect(t.repo.queries).toEqual(["profiles:smithson", "listings:smithson"]);
    expect(body.players).toContainEqual({ id: "priv", name: "Sam", username: "sam", private: true });
    expect(body.players.find((p: { id: string }) => p.id === "pub")).not.toHaveProperty("bio");
  });

  it("answers an empty search without querying", async () => {
    expect((await t.get("/v1/public/search?q=%20%20")).json()).toEqual({ players: [], teams: [] });
    expect(t.repo.queries).toEqual([]);
  });

  it("is cacheable by anyone", async () => {
    const res = await t.get("/v1/public/events");
    expect(res.headers["cache-control"]).toContain("public");
    expect(res.headers["cache-control"]).toContain("s-maxage=60");
  });
});

describe("public route access", () => {
  it("needs no App Check even when it's enforced", async () => {
    const { get, app } = setup({ enforceAppCheck: true });
    expect((await get("/v1/public/events")).statusCode).toBe(200);
    // Other routes still need it.
    const res = await app.inject({ method: "POST", url: "/v1/teams", payload: {}, headers: { authorization: "Bearer token:u1" } });
    expect(res.statusCode).toBe(401);
  });

  it("treats a bad token as a visitor", async () => {
    const { get } = setup();
    expect((await get("/v1/public/events", { authorization: "Bearer junk" })).statusCode).toBe(200);
  });

  it("limits visitors by hashed IP and members by uid", async () => {
    const { get, limiter } = setup();
    await get("/v1/public/events", { "x-forwarded-for": "203.0.113.9, 10.0.0.1" });
    await get("/v1/public/events", { authorization: "Bearer token:u1" });
    expect(limiter.keys[0]).toMatch(/^ip_[0-9a-f]{32}$/);
    expect(limiter.keys[0]).not.toContain("203");
    expect(limiter.keys[1]).toBe("u1");
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
  });

  it("isn't served when the app is built without browse", async () => {
    const app = buildApp({ verifier: new FakeVerifier(), users: new FakeUsers(), teams: new FakeTeamRepository() });
    expect((await app.inject({ url: "/v1/public/feed" })).statusCode).toBe(404);
  });
});
