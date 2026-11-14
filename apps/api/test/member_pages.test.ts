// Others' pages as a signed-in member sees them (GET /v1/players/:uid,
// GET /v1/posts/:id), and the website's cached pages expired on changes.
import { beforeEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import type { Data, Doc } from "../src/browse/repository.js";
import type { MeRepository } from "../src/me/repository.js";
import { webRevalidator } from "../src/web/revalidate.js";
import { FakeStore, FakeTeamRepository, FakeUsers, FakeVerifier } from "./fakes.js";

const now = Date.parse("2026-11-13T12:00:00Z");

class Repo implements MeRepository {
  people = new Map<string, Data>();
  hidden = new Map<string, Data>();
  follows = new Map<string, string[]>();
  posts: Doc[] = [];
  async profile(uid: string) {
    return this.people.get(uid) ?? null;
  }
  async privateDetails(uid: string) {
    return this.hidden.get(uid) ?? null;
  }
  async teamsOf() {
    return [];
  }
  async upcomingEvents() {
    return [];
  }
  async followedUsers(uid: string) {
    return this.follows.get(uid) ?? [];
  }
  async postsBy(authors: string[], _before: number | null, limit: number) {
    return this.posts.filter((p) => authors.includes(String(p.data.authorId))).slice(0, limit);
  }
  async post(id: string) {
    return this.posts.find((p) => p.id === id) ?? null;
  }
  async profiles(ids: string[]) {
    return new Map(ids.filter((id) => this.people.has(id)).map((id) => [id, this.people.get(id)!] as const));
  }
}

const post = (id: string, authorId: string, extra: Data = {}): Doc => ({
  id,
  data: { authorId, authorName: authorId, kind: "text", body: `${id} body`, createdAt: "2026-11-13T10:00:00.000Z", ...extra },
});

function setup() {
  const repo = new Repo();
  const app = buildApp({
    verifier: new FakeVerifier(),
    users: new FakeUsers(),
    teams: new FakeTeamRepository(),
    now: () => now,
    me: { repo, imageUrl: (p) => `https://img.test/${p}` },
  });
  const get = (url: string, uid: string | null = "viewer") =>
    app.inject({ method: "GET", url, headers: uid ? { authorization: `Bearer token:${uid}` } : {} });
  // Pat is private, with details in the private doc; Sam is public.
  repo.people.set("pat", { name: "Pat", username: "pat", private: true, visibility: { stats: false } });
  repo.hidden.set("pat", { bio: "Handler", hometown: "Austin" });
  repo.people.set("sam", { name: "Sam", bio: "Cutter" });
  repo.people.set("viewer", { name: "Vee" });
  repo.posts.push(post("p1", "pat"), post("s1", "sam"));
  return { repo, get };
}

describe("GET /v1/players/:uid", () => {
  let t: ReturnType<typeof setup>;
  beforeEach(() => {
    t = setup();
  });

  it("needs a signed-in member and is never cached", async () => {
    expect((await t.get("/v1/players/sam", null)).statusCode).toBe(401);
    const r = await t.get("/v1/players/sam");
    expect(r.headers["cache-control"]).toBe("private, no-store");
    expect(r.json()).toMatchObject({ locked: false, profile: { id: "sam", bio: "Cutter" }, posts: [{ id: "s1" }] });
  });

  it("locks a private profile for someone they haven't approved", async () => {
    const body = (await t.get("/v1/players/pat")).json();
    expect(body.locked).toBe(true);
    expect(body.profile).toEqual({ id: "pat", name: "Pat", username: "pat", private: true });
    expect(body.posts).toEqual([]);
  });

  it("shows a private profile in full, details and posts, to an approved follower", async () => {
    t.repo.follows.set("viewer", ["pat"]);
    const body = (await t.get("/v1/players/pat")).json();
    expect(body.locked).toBe(false);
    expect(body.profile).toMatchObject({ id: "pat", private: true, bio: "Handler", hometown: "Austin" });
    expect(body.profile.visibility.stats).toBe(false);
    expect(body.posts.map((p: Data) => p.id)).toEqual(["p1"]);
  });

  it("shows the owner their own private profile", async () => {
    expect((await t.get("/v1/players/pat", "pat")).json().locked).toBe(false);
  });

  it("404s an unknown player", async () => {
    expect((await t.get("/v1/players/nobody")).statusCode).toBe(404);
  });
});

describe("GET /v1/posts/:id", () => {
  let t: ReturnType<typeof setup>;
  beforeEach(() => {
    t = setup();
  });

  it("serves a public author's post, never cached", async () => {
    const r = await t.get("/v1/posts/s1");
    expect(r.statusCode).toBe(200);
    expect(r.headers["cache-control"]).toBe("private, no-store");
    expect(r.json()).toMatchObject({ id: "s1", body: "s1 body" });
  });

  it("hides a private author's post from someone they haven't approved, not from a follower", async () => {
    expect((await t.get("/v1/posts/p1")).statusCode).toBe(404);
    t.repo.follows.set("viewer", ["pat"]);
    expect((await t.get("/v1/posts/p1")).json()).toMatchObject({ id: "p1" });
    expect((await t.get("/v1/posts/p1", "pat")).statusCode).toBe(200);
  });

  it("hides a repost of a private author's post unless the viewer follows them", async () => {
    t.repo.posts.push(post("r_p1_sam", "sam", { kind: "repost", repostOf: { postId: "p1", authorId: "pat" } }));
    expect((await t.get("/v1/posts/r_p1_sam")).statusCode).toBe(404);
    t.repo.follows.set("viewer", ["pat"]);
    expect((await t.get("/v1/posts/r_p1_sam")).json()).toMatchObject({ id: "r_p1_sam", original: { id: "p1" } });
  });

  it("says a deleted post is gone", async () => {
    const r = await t.get("/v1/posts/gone");
    expect(r.statusCode).toBe(404);
    expect(r.json().error.message).toBe("This post was deleted.");
  });
});

describe("expiring the website's cached pages", () => {
  function withRevalidate() {
    const store = new FakeStore(() => now);
    const users = new FakeUsers();
    const sent: string[][] = [];
    const app = buildApp({
      verifier: new FakeVerifier(),
      users,
      teams: new FakeTeamRepository(),
      store,
      now: () => now,
      revalidate: async (tags) => {
        sent.push(tags);
      },
    });
    users.records.set("me", { name: "Pat Lee" });
    const call = (method: "POST" | "PUT" | "PATCH" | "DELETE", url: string, body?: object) =>
      app.inject({ method, url, ...(body && { payload: body }), headers: { authorization: "Bearer token:me" } });
    return { sent, call, store };
  }

  it("expires the player's page, posts, feed and search when a profile goes private", async () => {
    const t = withRevalidate();
    t.store.put("profiles/me", { name: "Pat Lee", username: "pat" });
    expect((await t.call("PUT", "/v1/me/profile/privacy", { private: true })).statusCode).toBe(200);
    expect(t.sent.at(-1)).toEqual(expect.arrayContaining(["player:me", "posts", "feed", "search"]));
  });

  it("expires the post's page, the author's page and the feed on a post edit and delete", async () => {
    const t = withRevalidate();
    const created = await t.call("POST", "/v1/posts", { body: "Hello" });
    expect(created.statusCode).toBe(201);
    expect(t.sent.at(-1)).toEqual(expect.arrayContaining(["player:me", "feed"]));
    const id = created.json().id as string;
    expect((await t.call("PATCH", `/v1/posts/${id}`, { body: "Hello again" })).statusCode).toBe(200);
    expect(t.sent.at(-1)).toEqual(expect.arrayContaining([`post:${id}`, "player:me", "feed"]));
    expect((await t.call("DELETE", `/v1/posts/${id}`)).statusCode).toBe(204);
    expect(t.sent.at(-1)).toEqual(expect.arrayContaining([`post:${id}`, "player:me", "feed"]));
  });

  it("doesn't fail a write when nothing expires", async () => {
    const t = withRevalidate();
    // A refused write sends nothing.
    expect((await t.call("PUT", "/v1/me/profile/privacy", { private: "yes" })).statusCode).toBe(400);
    expect(t.sent).toEqual([]);
  });
});

describe("webRevalidator", () => {
  it("posts the tags with the shared key, and never throws", async () => {
    const calls: Array<{ url: string; init: RequestInit }> = [];
    const ok = webRevalidator("https://site.test", "k3y", {
      fetch: (async (url: string, init: RequestInit) => {
        calls.push({ url, init });
        return new Response(null, { status: 200 });
      }) as typeof fetch,
    });
    await ok(["player:me", "feed", "feed"]);
    expect(calls[0]!.url).toBe("https://site.test/api/revalidate");
    expect((calls[0]!.init.headers as Record<string, string>)["x-stall10-web-key"]).toBe("k3y");
    expect(JSON.parse(String(calls[0]!.init.body))).toEqual({ tags: ["player:me", "feed"] });

    const down = webRevalidator("https://site.test", "k3y", {
      fetch: (async () => {
        throw new Error("offline");
      }) as typeof fetch,
    });
    await expect(down(["feed"])).resolves.toBeUndefined();
  });
});
