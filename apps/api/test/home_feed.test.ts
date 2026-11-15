// The home feed's players' posts, as the app's HomeFeed gathers them: the
// caller's and followed people's, posts tagged with followed tournaments,
// and events shared from the caller's teams (not reposts of them), with
// strangers' posts only from public profiles.
import { describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import type { Data, Doc } from "../src/browse/repository.js";
import type { MeRepository } from "../src/me/repository.js";
import { FakeTeamRepository, FakeUsers, FakeVerifier } from "./fakes.js";

const now = Date.UTC(2026, 10, 14, 12);
const iso = (ms: number) => new Date(ms).toISOString();

class Repo implements MeRepository {
  people = new Map<string, Data>();
  teams: Doc[] = [];
  follows: string[] = [];
  tournaments: string[] = [];
  posts: Doc[] = [];
  async profile() {
    return null;
  }
  async privateDetails() {
    return null;
  }
  async teamsOf(uid: string) {
    return this.teams.filter((t) => (t.data.memberIds as string[]).includes(uid));
  }
  async upcomingEvents() {
    return [];
  }
  async followedUsers() {
    return this.follows;
  }
  async followedTournaments() {
    return this.tournaments;
  }
  private page(match: (d: Data) => boolean, before: number | null, limit: number) {
    return this.posts
      .filter((p) => match(p.data) && (!before || Date.parse(String(p.data.createdAt)) < before))
      .sort((a, b) => String(b.data.createdAt).localeCompare(String(a.data.createdAt)))
      .slice(0, limit);
  }
  async postsBy(authors: string[], before: number | null, limit: number) {
    return this.page((d) => authors.includes(String(d.authorId)), before, limit);
  }
  async postsWhereIn(field: "tournamentKey" | "event.teamId", values: string[], before: number | null, limit: number) {
    const value = (d: Data) => (field === "tournamentKey" ? d.tournamentKey : (d.event as Data | undefined)?.teamId);
    return this.page((d) => values.includes(String(value(d))), before, limit);
  }
  async post(id: string) {
    return this.posts.find((p) => p.id === id) ?? null;
  }
  async profiles(ids: string[]) {
    return new Map(ids.filter((id) => this.people.has(id)).map((id) => [id, this.people.get(id)!] as const));
  }
}

function setup() {
  const repo = new Repo();
  const app = buildApp({ verifier: new FakeVerifier(), users: new FakeUsers(), teams: new FakeTeamRepository(), now: () => now, me: { repo, imageUrl: (p) => `https://img.test/${p}` } });
  const home = async (before?: number) =>
    (await app.inject({ method: "GET", url: `/v1/me/home${before ? `?before=${before}` : ""}`, headers: { authorization: "Bearer token:me:Pat" } })).json();
  return { repo, home };
}

const post = (id: string, ago: number, data: Data): Doc => ({ id, data: { body: id, createdAt: iso(now - ago * 1000), ...data } });

describe("home feed sources (HomeFeed)", () => {
  it("adds posts tagged with followed tournaments and events shared from my teams", async () => {
    const t = setup();
    t.repo.teams = [{ id: "t1", data: { name: "T1", memberIds: ["me"] } }];
    t.repo.tournaments = ["tournament_host_x"];
    t.repo.people.set("pub", { name: "Pub" });
    t.repo.posts = [
      post("mine", 1, { authorId: "me" }),
      post("tag", 2, { authorId: "pub", tournamentKey: "tournament_host_x" }),
      post("evt", 3, { authorId: "pub", kind: "event", event: { teamId: "t1", eventId: "e", title: "Practice" } }),
      post("evtRepost", 4, { authorId: "pub", kind: "repost", event: { teamId: "t1" }, repostOf: { postId: "evt", authorId: "pub" } }),
      post("otherTag", 5, { authorId: "pub", tournamentKey: "tournament_host_y" }),
    ];
    const feed = (await t.home()).feed;
    expect(feed.posts.map((p: { id: string }) => p.id)).toEqual(["mine", "tag", "evt"]);
    expect(feed.next).toBeNull();
  });

  it("hides strangers' posts from private profiles, but not followed people's", async () => {
    const t = setup();
    t.repo.tournaments = ["tournament_host_x"];
    t.repo.follows = ["friend"];
    t.repo.people.set("secret", { name: "S", private: true });
    t.repo.people.set("friend", { name: "F", private: true });
    t.repo.posts = [
      post("hidden", 1, { authorId: "secret", tournamentKey: "tournament_host_x" }),
      post("friendTag", 2, { authorId: "friend", tournamentKey: "tournament_host_x" }),
    ];
    expect((await t.home()).feed.posts.map((p: { id: string }) => p.id)).toEqual(["friendTag"]);
  });

  it("pages across every source with one cursor and no repeats", async () => {
    const t = setup();
    t.repo.tournaments = ["tournament_host_x"];
    t.repo.people.set("pub", { name: "Pub" });
    for (let i = 0; i < 25; i++) t.repo.posts.push(post(`m${i}`, i * 2, { authorId: "me" }));
    for (let i = 0; i < 25; i++) t.repo.posts.push(post(`t${i}`, i * 2 + 1, { authorId: "pub", tournamentKey: "tournament_host_x" }));
    const first = (await t.home()).feed;
    expect(first.posts).toHaveLength(20);
    expect(first.next).not.toBeNull();
    const second = (await t.home(first.next)).feed;
    const ids = [...first.posts, ...second.posts].map((p: { id: string }) => p.id);
    expect(new Set(ids).size).toBe(ids.length);
    expect(ids.slice(0, 4)).toEqual(["m0", "t0", "m1", "t1"]);
  });
});

describe("home feed paging when every source is short", () => {
  it("three short sources merging past a page still give a cursor, and nothing is lost", async () => {
    const t = setup();
    t.repo.teams = [{ id: "t1", data: { name: "T1", memberIds: ["me"] } }];
    t.repo.tournaments = ["tournament_host_x"];
    t.repo.people.set("pub", { name: "Pub" });
    for (let i = 0; i < 9; i++) {
      t.repo.posts.push(post(`m${i}`, i * 3, { authorId: "me" }));
      t.repo.posts.push(post(`t${i}`, i * 3 + 1, { authorId: "pub", tournamentKey: "tournament_host_x" }));
      t.repo.posts.push(post(`e${i}`, i * 3 + 2, { authorId: "pub", kind: "event", event: { teamId: "t1", eventId: `e${i}` } }));
    }
    const first = (await t.home()).feed;
    expect(first.posts).toHaveLength(20);
    expect(first.next).not.toBeNull();
    const second = (await t.home(first.next)).feed;
    expect(second.posts).toHaveLength(7);
    expect(second.next).toBeNull();
    const ids = [...first.posts, ...second.posts].map((p: { id: string }) => p.id);
    expect(new Set(ids).size).toBe(27);
  });
});

describe("home feed privacy and limits", () => {
  it("hides a followed person's repost of a private stranger's post", async () => {
    const { repo, home } = setup();
    repo.follows = ["friend"];
    repo.people.set("friend", { name: "Friend" });
    repo.people.set("hidden", { name: "Hidden", private: true });
    repo.posts = [post("orig", 60, { authorId: "hidden" }), post("rp", 10, { authorId: "friend", kind: "repost", repostOf: { postId: "orig", authorId: "hidden" } })];
    const { feed } = await home();
    const ids = feed.posts.map((p: Data) => p.id);
    expect(ids).not.toContain("orig");
    for (const p of feed.posts) expect(JSON.stringify(p)).not.toContain('"body":"orig"');
  });

  it("caps home reads per member", async () => {
    const { home } = setup();
    for (let i = 0; i < 60; i++) expect((await home()).error).toBeUndefined();
    expect((await home()).error?.code).toBe("resource_exhausted");
  });
});
