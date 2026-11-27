// Phase-1 contract A1 to A3 and the real Firestore create(): a replayed
// client id (team event, group conversation, roster spot) is a 409
// already_exists through FirestoreDocStore, not a 500, and changes nothing.
// Against the Firestore and Auth emulators (pnpm test:emulator); own uids (p1-*).
import { deleteApp, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { FirestoreDocStore } from "../src/firestore_store.js";
import { FirestoreTeamRepository } from "../src/teams/repository.js";

const projectId = "demo-stall10";
const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
if (!process.env.FIRESTORE_EMULATOR_HOST || !authHost) {
  throw new Error("Run with `pnpm test:emulator` (needs the Firestore and Auth emulators).");
}

const firebase = initializeApp({ projectId }, "phase1-ids-emulator-test");
const db = getFirestore(firebase);
const auth = getAuth(firebase);
const app = buildApp({
  verifier: {
    async verifyIdToken(token) {
      const t = await auth.verifyIdToken(token);
      return { uid: t.uid, name: t.name as string | undefined, email: t.email, emailVerified: t.email_verified === true, ...(t.ageOk === true && { ageOk: true }), ...(typeof t.terms === "number" && { terms: t.terms }) };
    },
    async verifyAppCheck() {},
  },
  users: {
    async lookup(uid) {
      const u = await auth.getUser(uid);
      return { name: u.displayName, email: u.email };
    },
  },
  teams: new FirestoreTeamRepository(db),
  store: new FirestoreDocStore(db),
});

let token = "";
const call = (url: string, body: object) => app.inject({ method: "POST", url, headers: { authorization: `Bearer ${token}` }, payload: body });

beforeAll(async () => {
  await auth.createUser({ uid: "p1-coach", displayName: "Casey", email: "p1-coach@x.test", emailVerified: true }).catch(() => undefined);
  const custom = await auth.createCustomToken("p1-coach", { ageOk: true, terms: 1 });
  const res = await fetch(`http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=fake`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ token: custom, returnSecureToken: true }),
  });
  token = ((await res.json()) as { idToken: string }).idToken;
  await db.doc("teams/p1-team").set({
    name: "Haze",
    kind: "team",
    ownerId: "p1-coach",
    memberIds: ["p1-coach"],
    members: { "p1-coach": "owner" },
    memberNames: { "p1-coach": "Casey" },
  });
  await db.doc("profiles/p1-coach").set({ name: "Casey" });
});

afterAll(async () => {
  await db.recursiveDelete(db.doc("teams/p1-team"));
  await db.recursiveDelete(db.doc("conversations/g-p1replay"));
  await db.doc("profiles/p1-coach").delete();
  await deleteApp(firebase);
});

describe("a replayed client id is a 409 with real Firestore", () => {
  it("team event", async () => {
    const body = { id: "p1ev", title: "Practice", startsAt: "2026-11-18T18:00:00Z" };
    expect((await call("/v1/teams/p1-team/events", body)).statusCode).toBe(201);
    const replay = await call("/v1/teams/p1-team/events", { ...body, title: "Changed" });
    expect(replay.statusCode).toBe(409);
    expect(replay.json().error.code).toBe("already_exists");
    expect((await db.doc("teams/p1-team/events/p1ev").get()).get("title")).toBe("Practice");
  });

  it("group conversation", async () => {
    const body = { id: "g-p1replay", name: "Crew" };
    expect((await call("/v1/conversations/groups", body)).statusCode).toBe(201);
    const replay = await call("/v1/conversations/groups", { ...body, name: "Other" });
    expect(replay.statusCode).toBe(409);
    expect((await db.doc("conversations/g-p1replay").get()).get("name")).toBe("Crew");
  });

  it("roster spot", async () => {
    const body = { id: "p1spot", name: "Pat P" };
    expect((await call("/v1/teams/p1-team/roster-players", body)).statusCode).toBe(201);
    const replay = await call("/v1/teams/p1-team/roster-players", { ...body, name: "Someone Else" });
    expect(replay.statusCode).toBe(409);
    expect((await db.doc("teams/p1-team/roster/p1spot").get()).get("name")).toBe("Pat P");
  });
});
