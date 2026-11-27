// D-1317: accounts without the `ageOk` claim are left out of public
// search, profiles and posts, and can't be messaged, when ACCOUNT_GATE_MODE
// is enforce. In report mode nothing is hidden and the would-be hiding is
// logged.
import { beforeEach, describe, expect, it } from "vitest";
import { AdultVisibility, adultClaimTtlMs } from "../src/account/adult_visibility.js";
import type { AccountGateMode } from "../src/auth.js";
import { buildApp } from "../src/app.js";
import type { BrowseRepository, Data, Doc } from "../src/browse/repository.js";
import { FakeMediaStorage, FakeStore, FakeTeamRepository, FakeUsers, FakeVerifier } from "./fakes.js";

const now = Date.UTC(2026, 10, 14, 12);

/** FakeUsers that can also say who carries `ageOk`, counting the batched calls. */
class ClaimUsers extends FakeUsers {
  adults = new Set<string>();
  calls: string[][] = [];
  async ageOkOf(uids: string[]) {
    this.calls.push(uids);
    return new Set(uids.filter((u) => this.adults.has(u)));
  }
}

class Repo implements BrowseRepository {
  profileMap = new Map<string, Data>();
  postsList: Doc[] = [];
  async posts() {
    return this.postsList;
  }
  async post(id: string) {
    return this.postsList.find((p) => p.id === id) ?? null;
  }
  async profiles(ids: string[]) {
    return new Map(ids.flatMap((id) => (this.profileMap.has(id) ? [[id, this.profileMap.get(id)!] as const] : [])));
  }
  async listing() {
    return null;
  }
  async listings() {
    return new Map();
  }
  async teams() {
    return new Map();
  }
  async publicTeamPosts() {
    return [];
  }
  async upcomingTeamEvents() {
    return [];
  }
  async upcomingEvents() {
    return [];
  }
  async upcomingTournaments() {
    return [];
  }
  async searchProfiles() {
    return [...this.profileMap].map(([id, data]) => ({ id, data }));
  }
  async searchListings() {
    return [];
  }
}

function setup(mode: AccountGateMode) {
  const users = new ClaimUsers();
  const repo = new Repo();
  const store = new FakeStore(() => now);
  const app = buildApp({
    verifier: new FakeVerifier(),
    users,
    teams: new FakeTeamRepository(),
    store,
    media: new FakeMediaStorage(),
    now: () => now,
    writeLimits: false,
    accountGateMode: mode,
    browse: { repo, limiter: { admit: async () => true }, imageUrl: (p) => `https://img.test/${p}`, photoBuckets: ["x"] },
  });
  for (const [uid, name] of [["amy", "Amy"], ["adult", "Ada"], ["legacy", "Lee"]] as const) {
    repo.profileMap.set(uid, { name, username: uid, private: false });
    store.put(`profiles/${uid}`, { name });
    users.records.set(uid, { name, email: `${uid}@x.test` });
  }
  users.adults.add("amy").add("adult");
  const post = (id: string, authorId: string): Doc => ({ id, data: { authorId, authorName: authorId, body: id, createdAt: new Date(now).toISOString() } });
  repo.postsList = [post("p1", "adult"), post("p2", "legacy")];
  const get = (url: string) => app.inject({ method: "GET", url, headers: { authorization: "Bearer token:amy:Amy" } });
  const call = (method: "POST", url: string, body: object) =>
    app.inject({ method, url, payload: body, headers: { authorization: "Bearer token:amy:Amy" } });
  return { users, repo, store, get, call };
}

describe("enforce mode", () => {
  let s: ReturnType<typeof setup>;
  beforeEach(() => {
    s = setup("enforce");
  });

  it("leaves accounts without ageOk out of search", async () => {
    const res = await s.get("/v1/public/search?q=lee");
    expect(res.statusCode).toBe(200);
    expect((res.json().players as Array<{ id: string }>).map((p) => p.id).sort()).toEqual(["adult", "amy"]);
  });

  it("answers 404 for their public profile, and keeps the adult's", async () => {
    expect((await s.get("/v1/public/players/legacy")).statusCode).toBe(404);
    expect((await s.get("/v1/public/players/adult")).statusCode).toBe(200);
  });

  it("leaves their posts out of the public feed and one-post page", async () => {
    const feed = (await s.get("/v1/public/feed")).json() as { posts: Array<{ id: string }> };
    expect(feed.posts.map((p) => p.id)).toEqual(["p1"]);
    expect((await s.get("/v1/public/posts/p2")).statusCode).toBe(404);
    expect((await s.get("/v1/public/posts/p1")).statusCode).toBe(200);
  });

  it("refuses to start a conversation with them, and nothing is created", async () => {
    const res = await s.call("POST", "/v1/conversations", { with: "legacy" });
    expect(res.statusCode).toBe(403);
    expect(s.store.doc("conversations/amy_legacy")).toBeUndefined();
    expect((await s.call("POST", "/v1/conversations", { with: "adult" })).statusCode).toBe(200);
  });

  it("refuses to send to an existing one-to-one conversation with them", async () => {
    s.store.put("conversations/amy_legacy", { participants: ["amy", "legacy"], names: { amy: "Amy", legacy: "Lee" }, status: "accepted" });
    const res = await s.call("POST", "/v1/conversations/amy_legacy/messages", { text: "hi" });
    expect(res.statusCode).toBe(403);
    expect(s.store.docs.has("conversations/amy_legacy/messages/x")).toBe(false);
  });

  it("does not add them to a group", async () => {
    s.store.put("users/legacy/follows/user_amy", { at: new Date(now) });
    s.store.put("users/adult/follows/user_amy", { at: new Date(now) });
    const res = await s.call("POST", "/v1/conversations/groups", { name: "Crew", members: ["legacy", "adult"] });
    expect(res.statusCode).toBe(201);
    expect(res.json().notAdded).toEqual(["Lee"]);
  });
});

describe("report mode", () => {
  it("hides nothing and logs who it would", async () => {
    const logged: Record<string, unknown>[] = [];
    const s = setup("report");
    const adults = new AdultVisibility(s.users, "report", () => now, (e) => logged.push(e));
    expect([...(await adults.hidden(["legacy", "adult"]))]).toEqual([]);
    expect(logged).toMatchObject([{ event: "adult_visibility_report", wouldHide: 1, uids: ["legacy"] }]);
    // Through the app too: everything still shows, DMs allowed.
    expect((await s.get("/v1/public/players/legacy")).statusCode).toBe(200);
    expect((await s.get("/v1/public/search?q=lee")).json().players).toHaveLength(3);
    expect((await s.call("POST", "/v1/conversations", { with: "legacy" })).statusCode).toBe(200);
  });
});

describe("AdultVisibility", () => {
  it("asks for claims in one batch and caches them for a few minutes", async () => {
    const users = new ClaimUsers();
    users.adults.add("a");
    let t = now;
    const v = new AdultVisibility(users, "enforce", () => t, () => {});
    expect([...(await v.hidden(["a", "b", "b", "c"]))].sort()).toEqual(["b", "c"]);
    expect(users.calls).toEqual([["a", "b", "c"]]);
    await v.hidden(["a", "b"]);
    expect(users.calls).toHaveLength(1);
    // The claim arrives later: seen once the cache lapses.
    users.adults.add("b");
    t += adultClaimTtlMs + 1;
    expect([...(await v.hidden(["a", "b"]))]).toEqual([]);
    expect(users.calls).toHaveLength(2);
  });

  it("hides nothing without a claim lookup", async () => {
    const v = new AdultVisibility(new FakeUsers(), "enforce", () => now, () => {});
    expect([...(await v.hidden(["x"]))]).toEqual([]);
  });
});
