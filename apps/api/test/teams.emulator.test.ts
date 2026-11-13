// Runs against the Firestore and Auth emulators (pnpm test:emulator):
// real ID tokens, real batch writes, documents read back and compared with
// what the app writes (packages/shared/fixtures/team_create.json).
import { readFileSync } from "node:fs";
import { deleteApp, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { FirestoreTeamRepository } from "../src/teams/repository.js";

const projectId = "demo-stall10";
const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
if (!process.env.FIRESTORE_EMULATOR_HOST || !authHost) {
  throw new Error("Run with `pnpm test:emulator` (needs the Firestore and Auth emulators).");
}

const firebase = initializeApp({ projectId }, "emulator-test");
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
      return { name: u.displayName, email: u.email };
    },
  },
  teams: new FirestoreTeamRepository(db),
});

/** A real ID token from the Auth emulator for a new user. */
async function idTokenFor(uid: string, displayName: string): Promise<string> {
  await auth.createUser({ uid, displayName, email: `${uid}@x.test` });
  const custom = await auth.createCustomToken(uid);
  const res = await fetch(
    `http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=fake`,
    { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ token: custom, returnSecureToken: true }) },
  );
  return ((await res.json()) as { idToken: string }).idToken;
}

const fixture = JSON.parse(
  readFileSync(new URL("../../../packages/shared/fixtures/team_create.json", import.meta.url), "utf8"),
)[0] as { request: object; docs: Record<string, Record<string, unknown>> };

let token: string;

beforeAll(async () => {
  await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${projectId}/databases/(default)/documents`, { method: "DELETE" });
  await fetch(`http://${authHost}/emulator/v1/projects/${projectId}/accounts`, { method: "DELETE" });
  token = await idTokenFor("u1", "Pat Lee");
});

afterAll(async () => {
  await app.close();
  await deleteApp(firebase);
});

const post = (body: object, t = token) =>
  app.inject({ method: "POST", url: "/v1/teams", payload: body, headers: { authorization: `Bearer ${t}` } });

describe("POST /v1/teams on the emulators", () => {
  let teamId: string;

  it("writes the same documents the app does", async () => {
    const res = await post(fixture.request);
    expect(res.statusCode).toBe(201);
    teamId = res.json().id;

    for (const [path, expected] of Object.entries(fixture.docs)) {
      const real = path.replace("team1", teamId);
      const snap = await db.doc(real).get();
      expect(snap.exists, real).toBe(true);
      const data = snap.data()!;
      if ("createdAt" in expected) {
        expect(data.createdAt).toBeInstanceOf(Timestamp);
        data.createdAt = "<serverTimestamp>";
      }
      expect(data, real).toEqual(expected);
    }
  });

  // Known gap, shared with the app: listing keywords split "B.Q.Q." into
  // b/q, so the name check's probe "bqq" doesn't find it (ARCHITECTURE.md,
  // known issues). Fails until that's fixed; then drop `.fails`.
  it.fails("refuses a punctuated name that's taken", async () => {
    expect((await post({ ...fixture.request, name: "Texas BQQ" })).statusCode).toBe(409);
  });

  it("refuses an exact repeat of a plain name", async () => {
    expect((await post({ name: "Haze", division: "open", level: "club" })).statusCode).toBe(201);
    const res = await post({ name: "The Haze", division: "open", level: "club" });
    expect(res.statusCode).toBe(409);
  });

  it("checks the league takes teams", async () => {
    expect((await post({ name: "League Team", division: "open", level: "league", leagueId: "nope" })).statusCode).toBe(412);
    await db.doc("tournaments/l1").set({ teamEntry: true });
    const res = await post({ name: "League Team", division: "open", level: "league", leagueId: "l1" });
    expect(res.statusCode).toBe(201);
    expect((await db.doc(`teams/${res.json().id}`).get()).get("leagueId")).toBe("l1");
  });

  it("honours a flood mute", async () => {
    await db.doc("limits/u1").set({ mutedUntil: Timestamp.fromMillis(Date.now() + 10 * 60_000) });
    expect((await post({ name: "Muted Team", division: "open", level: "club" })).statusCode).toBe(429);
    await db.doc("limits/u1").delete();
  });

  it("names the owner as they are now, even with an older token", async () => {
    // Renamed after the token was minted: the token still says "Pat Lee".
    await auth.updateUser("u1", { displayName: "Pat Renamed" });
    const res = await post({ name: "Renamed Team", division: "open", level: "club" });
    expect(res.statusCode).toBe(201);
    const team = await db.doc(`teams/${res.json().id}`).get();
    expect(team.get("memberNames")).toEqual({ u1: "Pat Renamed" });
  });

  it("rejects a forged token", async () => {
    expect((await post({ name: "Forged", division: "open", level: "club" }, "not-a-token")).statusCode).toBe(401);
  });
});
