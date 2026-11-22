// Tournament chats and "At a tournament" against the emulators: the open
// endpoints on real Firestore (transactions, an empty tournament, a second
// open with every name known), and the tag list for someone who follows
// nothing.
import { deleteApp, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { FirestoreDocStore } from "../src/firestore_store.js";
import { FirestoreTeamRepository } from "../src/teams/repository.js";

const projectId = "demo-stall10";
const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
if (!process.env.FIRESTORE_EMULATOR_HOST || !authHost) {
  throw new Error("Run with `pnpm test:emulator` (needs the Firestore and Auth emulators).");
}

const firebase = initializeApp({ projectId }, "tournament-chats-emulator-test");
const db = getFirestore(firebase);
const auth = getAuth(firebase);
const app = buildApp({
  verifier: {
    async verifyIdToken(token) {
      const t = await auth.verifyIdToken(token);
      return { uid: t.uid, name: t.name as string | undefined, email: t.email };
    },
    async verifyAppCheck() {},
  },
  users: {
    async lookup(uid) {
      const u = await auth.getUser(uid);
      return { name: u.displayName, email: u.email, photoUrl: u.photoURL };
    },
  },
  teams: new FirestoreTeamRepository(db),
  store: new FirestoreDocStore(db),
  writeLimits: false,
});

async function idTokenFor(uid: string, displayName: string): Promise<string> {
  await auth.createUser({ uid, displayName, email: `${uid}@x.test` }).catch(() => undefined);
  const custom = await auth.createCustomToken(uid);
  const res = await fetch(`http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=fake`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ token: custom, returnSecureToken: true }),
  });
  return ((await res.json()) as { idToken: string }).idToken;
}

const tokens: Record<string, string> = {};
const call = (method: "GET" | "POST", url: string, uid: string) =>
  app.inject({ method, url, ...(method === "POST" && { payload: {} }), headers: { authorization: `Bearer ${tokens[uid]}` } });

beforeAll(async () => {
  tokens.dir = await idTokenFor("tc-dir", "Dana Director");
  tokens.cap = await idTokenFor("tc-cap", "Cam Captain");
  await db.doc("profiles/tc-dir").set({ name: "Dana Director" });
  await db.doc("profiles/tc-cap").set({ name: "Cam Captain" });
  await db.doc("teams/tc-host").set({ name: "Fling Crew", kind: "community", memberIds: ["tc-dir"], members: { "tc-dir": "owner" } });
  await db.doc("teams/tc-haze").set({ name: "Haze", kind: "team", memberIds: ["tc-cap"], members: { "tc-cap": "owner" } });
  await db.doc("tournaments/tc-t").set({ hostId: "tc-host", name: "Spring Fling", status: "registration", startsOn: Timestamp.now() });
  await db.recursiveDelete(db.collection("tournaments/tc-t/entries"));
  await db.recursiveDelete(db.collection("tournaments/tc-t/chats"));
  await db.recursiveDelete(db.collection("users/tc-dir/follows"));
});

afterAll(async () => {
  await app.close();
  await deleteApp(firebase);
});

describe("tournament chats on Firestore", () => {
  it("opens the Captains' channel before any team has entered, then again with names known", async () => {
    const first = await call("POST", "/v1/tournaments/tc-t/chats/captains", "dir");
    expect(first.statusCode, first.body).toBe(200);
    const id = first.json().id as string;
    expect((await db.doc(`conversations/${id}`).get()).get("participants")).toEqual(["tc-dir"]);
    const again = await call("POST", "/v1/tournaments/tc-t/chats/captains", "dir");
    expect(again.json().id).toBe(id);
  });

  it("adds a team's captains once it applies, and opens its own thread", async () => {
    await db.doc("tournaments/tc-t/entries/tc-haze").set({ teamName: "Haze", status: "applied", captainIds: ["tc-cap"] });
    const captains = await call("POST", "/v1/tournaments/tc-t/chats/captains", "cap");
    expect(captains.statusCode, captains.body).toBe(200);
    const conv = (await db.doc(`conversations/${captains.json().id}`).get()).data()!;
    expect(conv.participants).toEqual(["tc-dir", "tc-cap"]);
    expect(conv.names).toEqual({ "tc-dir": "Dana Director", "tc-cap": "Cam Captain" });
    const team = await call("POST", "/v1/tournaments/tc-t/chats/teams/tc-haze", "cap");
    expect(team.statusCode, team.body).toBe(200);
    expect((await db.doc(`conversations/${team.json().id}`).get()).get("kind")).toBe("tournament");
  });
});

describe("tag tournaments on Firestore", () => {
  it("answers an empty list for someone who follows nothing", async () => {
    const res = await call("GET", "/v1/me/tag-tournaments", "dir");
    expect(res.statusCode, res.body).toBe(200);
    expect(res.json()).toEqual({ tournaments: [] });
  });

  it("lists a followed tournament starting now", async () => {
    await db.doc("users/tc-dir/follows/tournament_tc-host_tc-t").set({ type: "tournament", targetId: "tc-host_tc-t", groupId: "tc-host", name: "Spring Fling" });
    const res = await call("GET", "/v1/me/tag-tournaments", "dir");
    expect(res.json().tournaments.map((t: { key: string }) => t.key)).toEqual(["tournament_tc-host_tc-t"]);
  });
});
