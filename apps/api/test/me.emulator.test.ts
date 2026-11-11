// The dashboard's real queries against the Firestore emulator (pnpm test:emulator).
import { deleteApp, initializeApp } from "firebase-admin/app";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { FirestoreMeRepository } from "../src/me/repository.js";
import { FakeTeamRepository, FakeUsers, FakeVerifier } from "./fakes.js";

const projectId = "demo-stall10";
if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error("Run with `pnpm test:emulator`.");

const firebase = initializeApp({ projectId }, "me-emulator-test");
const db = getFirestore(firebase);
const app = buildApp({
  verifier: new FakeVerifier(),
  users: new FakeUsers(),
  teams: new FakeTeamRepository(),
  me: { repo: new FirestoreMeRepository(db), imageUrl: (p) => `https://img.test/${p}` },
});
const ts = (msFromNow: number) => Timestamp.fromMillis(Date.now() + msFromNow);
const home = (q = "") => app.inject({ method: "GET", url: `/v1/me/home${q}`, headers: { authorization: "Bearer token:meU:Me" } });

beforeAll(async () => {
  const b = db.batch();
  b.set(db.doc("profiles/meU"), { name: "Me", username: "meu" });
  b.set(db.doc("users/meU/follows/user_friendU"), { key: "user_friendU", type: "user", targetId: "friendU" });
  b.set(db.doc("users/meU/follows/team_t9"), { key: "team_t9", type: "team", targetId: "t9" });
  b.set(db.doc("teams/meT1"), { name: "Mine", kind: "team", memberIds: ["meU"], members: { meU: "captain" } });
  b.set(db.doc("teams/meT2"), { name: "Not mine", kind: "team", memberIds: ["otherU"], members: { otherU: "owner" } });
  b.set(db.doc("teams/meT1/events/soon"), { title: "Practice", startsAt: ts(3_600_000) });
  b.set(db.doc("teams/meT1/events/gone"), { title: "Old", startsAt: ts(-3_600_000) });
  b.set(db.doc("teams/meT2/events/hidden"), { title: "Theirs", startsAt: ts(3_600_000) });
  for (let i = 0; i < 22; i++) {
    b.set(db.doc(`posts/me${i}`), { authorId: i % 2 ? "friendU" : "meU", body: `post ${i}`, createdAt: ts(-(i + 1) * 60_000) });
  }
  b.set(db.doc("posts/strangerPost"), { authorId: "strangerU", body: "not followed", createdAt: ts(-1_000) });
  await b.commit();
});

afterAll(async () => {
  await app.close();
  await deleteApp(firebase);
});

describe("dashboard on the emulator", () => {
  it("their teams, their events, and a feed of follows that pages", async () => {
    const res = await home();
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.profile).toMatchObject({ id: "meU", username: "meu", needsUsername: false });
    expect(body.teams.map((t: { id: string }) => t.id)).toEqual(["meT1"]);
    expect(body.events.map((e: { id: string }) => e.id)).toEqual(["soon"]);
    const ids = body.feed.posts.map((p: { id: string }) => p.id);
    expect(ids).toHaveLength(20);
    expect(ids[0]).toBe("me0");
    expect(ids).not.toContain("strangerPost");
    const more = (await home(`?before=${body.feed.next}`)).json().feed;
    expect(more.posts.map((p: { id: string }) => p.id)).toEqual(["me20", "me21"]);
    expect(more.next).toBeNull();
  });
});
