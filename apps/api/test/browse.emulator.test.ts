// Public reads against the Firestore emulator (pnpm test:emulator): real
// queries over seeded public and private data, and the real rate limiter.
import { deleteApp, initializeApp } from "firebase-admin/app";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { FirestoreBrowseRepository } from "../src/browse/repository.js";
import { FirestoreDocStore } from "../src/firestore_store.js";
import { FirestoreRateLimiter } from "../src/limits/limiter.js";
import { FakeTeamRepository, FakeUsers, FakeVerifier } from "./fakes.js";

const projectId = "demo-stall10";
if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error("Run with `pnpm test:emulator`.");

const firebase = initializeApp({ projectId }, "browse-emulator-test");
const db = getFirestore(firebase);
const app = buildApp({
  verifier: new FakeVerifier(),
  users: new FakeUsers(),
  teams: new FakeTeamRepository(),
  store: new FirestoreDocStore(db),
  browse: {
    repo: new FirestoreBrowseRepository(db),
    limiter: new FirestoreRateLimiter(db),
    imageUrl: (p) => `https://img.test/${encodeURIComponent(p)}`,
  },
});

const ts = (msFromNow: number) => Timestamp.fromMillis(Date.now() + msFromNow);
// The visitor's address as the socket (or a trusted proxy) gives it; a
// spoofed X-Forwarded-For first hop is ignored.
const get = (url: string, ip = "198.51.100.7") => app.inject({ method: "GET", url, remoteAddress: ip, headers: { "x-forwarded-for": "6.6.6.6" } });
/** Players and search are for signed-in members. */
const memberGet = (url: string) => app.inject({ method: "GET", url, headers: { authorization: "Bearer token:member1" } });

beforeAll(async () => {
  await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${projectId}/databases/(default)/documents`, {
    method: "DELETE",
  });
  const batch = db.batch();
  batch.set(db.doc("profiles/pub"), { name: "Pat Public", username: "pat", bio: "Cutter", private: false, keywords: ["pat"] });
  batch.set(db.doc("profiles/priv"), { name: "Sam Private", username: "sam", bio: "secret bio", private: true, keywords: ["sam"] });
  batch.set(db.doc("posts/pubPost"), {
    authorId: "pub",
    authorName: "Pat Public",
    body: "Public hello",
    images: [{ path: "users/pub/posts/pubPost/u1/a.jpg", name: "a.jpg", contentType: "image/jpeg", size: 10 }],
    likedBy: ["x"],
    createdAt: ts(-60_000),
  });
  batch.set(db.doc("posts/privPost"), { authorId: "priv", authorName: "Sam", body: "Private hello", createdAt: ts(-30_000) });
  batch.set(db.doc("posts/repostOfPriv"), {
    authorId: "pub",
    authorName: "Pat Public",
    repostOf: { postId: "privPost", authorId: "priv", authorName: "Sam" },
    createdAt: ts(-10_000),
  });
  batch.set(db.doc("teamDirectory/haze"), { name: "Haze", division: "open", level: "club", city: "Austin", keywords: ["haze"] });
  batch.set(db.doc("teamDirectory/secret"), {
    name: "Secret Club",
    division: "mixed",
    level: "pickup",
    kind: "community",
    requiresApproval: true,
    keywords: ["secret"],
  });
  batch.set(db.doc("teams/haze/posts/tp1"), { title: "We won", public: true, authorId: "priv", authorName: "Sam Private", createdAt: ts(-5_000) });
  batch.set(db.doc("teams/haze/posts/tp2"), { title: "Members only", public: false, createdAt: ts(-4_000) });
  batch.set(db.doc("teams/haze/publicEvents/e1"), { title: "Open practice", startsAt: ts(86_400_000) });
  batch.set(db.doc("teams/haze/publicEvents/past"), { title: "Old game", startsAt: ts(-86_400_000) });
  batch.set(db.doc("teams/secret/publicEvents/e2"), { title: "Secret practice", startsAt: ts(86_400_000) });
  batch.set(db.doc("teams/secret/posts/sp"), { title: "Secret post", public: true, createdAt: ts(-1_000) });
  batch.set(db.doc("teams/haze"), { name: "Haze", division: "open", level: "club", ownerId: "pub", memberIds: ["pub"], members: { pub: "owner" } });
  batch.set(db.doc("teams/haze/roster/r1"), { name: "Pat Public", number: 4, position: "cutter", userId: "pub" });
  batch.set(db.doc("teams/haze/roster/r2"), { name: "Sam Private", number: 9, userId: "priv" });
  batch.set(db.doc("teamDirectory/juniors"), { name: "Juniors", division: "mixed", level: "youth", keywords: ["juniors"] });
  batch.set(db.doc("teams/juniors"), { name: "Juniors", division: "mixed", level: "youth", ownerId: "pub", memberIds: ["pub"] });
  batch.set(db.doc("teams/juniors/roster/r1"), { name: "Kid Player", number: 1 });
  batch.set(db.doc("teams/juniors/posts/jp"), { title: "Practice at the school", public: true, createdAt: ts(-1_000) });
  batch.set(db.doc("teams/juniors/publicEvents/je"), { title: "Juniors game", startsAt: ts(86_400_000) });
  await batch.commit();
});

afterAll(async () => {
  await app.close();
  await deleteApp(firebase);
});

describe("public reads on the emulator", () => {
  it("feed: public posts only, with readable photo URLs and dates", async () => {
    const res = await get("/v1/public/feed");
    expect(res.statusCode).toBe(200);
    const { posts } = res.json();
    expect(posts.map((p: { id: string }) => p.id)).toEqual(["pubPost"]);
    expect(posts[0].likeCount).toBe(1);
    expect(posts[0].images[0].url).toBe("https://img.test/users%2Fpub%2Fposts%2FpubPost%2Fu1%2Fa.jpg");
    expect(new Date(posts[0].createdAt).toISOString()).toBe(posts[0].createdAt);
    expect(JSON.stringify(res.json())).not.toContain("Private hello");
  });

  it("profiles: a private player is only a card", async () => {
    const priv = (await memberGet("/v1/public/players/priv")).json();
    expect(priv.profile).toEqual({ id: "priv", name: "Sam Private", username: "sam", private: true });
    expect(priv.posts).toEqual([]);
    const pub = (await memberGet("/v1/public/players/pub")).json();
    expect(pub.posts.map((p: { id: string }) => p.id)).toEqual(["pubPost"]);
  });

  it("teams: public posts and upcoming events; nothing from a private group", async () => {
    const res = await get("/v1/public/teams/haze");
    const haze = res.json();
    expect(haze.posts.map((p: { title: string }) => p.title)).toEqual(["We won"]);
    // Its author's profile is private: not named, and never by uid.
    expect(res.body).not.toContain("Sam");
    expect(res.body).not.toContain("authorId");
    expect(haze.events.map((e: { title: string }) => e.title)).toEqual(["Open practice"]);
    const secret = (await get("/v1/public/teams/secret")).json();
    expect(secret.posts).toEqual([]);
    expect(secret.events).toEqual([]);
    expect(secret.team.name).toBe("Secret Club");
  });

  it("teams: a youth team's card only for visitors", async () => {
    const juniors = (await get("/v1/public/teams/juniors")).json();
    expect(juniors).toEqual({ team: { id: "juniors", name: "Juniors", division: "mixed", level: "youth" }, posts: [], events: [] });
  });

  it("events: across teams, without the private group's", async () => {
    const body = (await get("/v1/public/events")).json();
    expect(body.events.map((e: { title: string }) => e.title)).toEqual(["Open practice"]);
  });

  it("search: finds teams and players by keyword", async () => {
    const body = (await memberGet("/v1/public/search?q=Haze")).json();
    expect(body.teams.map((t: { name: string }) => t.name)).toEqual(["Haze"]);
    const people = (await memberGet("/v1/public/search?q=sam")).json();
    expect(people.players).toEqual([{ id: "priv", name: "Sam Private", username: "sam", private: true }]);
  });

  it("team finder: listings only, for visitors", async () => {
    const res = await get("/v1/public/teams?q=Haze");
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ teams: [{ id: "haze", name: "Haze", division: "open", level: "club", city: "Austin" }] });
  });

  it("rosters: an adult team's players for visitors, never a youth team's", async () => {
    const haze = await get("/v1/public/teams/haze/roster");
    expect(haze.statusCode).toBe(200);
    expect(haze.json()).toEqual({
      players: [
        { name: "Pat Public", number: 4, position: "cutter", username: "pat" },
        // Linked to a private profile: not named.
        { name: "Player", number: 9 },
      ],
    });
    expect((await get("/v1/public/teams/juniors/roster")).statusCode).toBe(404);
    expect((await get("/v1/public/teams/secret/roster")).statusCode).toBe(404);
  });

  it("rate-limits a visitor in limits/ by hashed IP, then mutes them", async () => {
    const ip = "192.0.2.55";
    let last = 0;
    for (let i = 0; i < 121; i++) last = (await get("/v1/public/feed", ip)).statusCode;
    expect(last).toBe(429);
    const limits = await db.collection("limits").get();
    const mine = limits.docs.find((d) => d.get("mutedUntil"));
    expect(mine?.id).toMatch(/^ip_[0-9a-f]{32}$/);
    expect(JSON.stringify(limits.docs.map((d) => d.data()))).not.toContain(ip);
    // Someone else is unaffected.
    expect((await get("/v1/public/feed", "192.0.2.56")).statusCode).toBe(200);
  }, 60_000);
});
