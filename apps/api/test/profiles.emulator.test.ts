// Profiles and usernames through the API against the emulators: merges,
// field deletes and the username claim on real Firestore. Own uids (p-*).
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

const firebase = initializeApp({ projectId }, "profiles-emulator-test");
const db = getFirestore(firebase);
const auth = getAuth(firebase);
const store = new FirestoreDocStore(db);
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
  store,
});

async function idTokenFor(uid: string, displayName: string): Promise<string> {
  await auth.createUser({ uid, displayName, email: `${uid}@x.test` }).catch(() => undefined);
  const custom = await auth.createCustomToken(uid);
  const res = await fetch(
    `http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=fake`,
    { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ token: custom, returnSecureToken: true }) },
  );
  return ((await res.json()) as { idToken: string }).idToken;
}

let token: string;
const call = (method: "POST" | "PUT", url: string, body: object, t = token) =>
  app.inject({ method, url, payload: body, headers: { authorization: `Bearer ${t}` } });

beforeAll(async () => {
  token = await idTokenFor("p-user", "Pia Profile");
});

afterAll(async () => {
  await app.close();
  await deleteApp(firebase);
});

describe("profiles on the emulators", () => {
  it("claims a username once, with the profile", async () => {
    expect((await call("POST", "/v1/me/username", { username: "Pia_P" })).statusCode).toBe(200);
    expect((await db.doc("usernames/pia_p").get()).get("uid")).toBe("p-user");
    const profile = (await db.doc("profiles/p-user").get()).data()!;
    expect(profile).toMatchObject({ name: "Pia Profile", username: "pia_p" });
    expect(profile.updatedAt).toBeInstanceOf(Timestamp);
    expect((await call("POST", "/v1/me/username", { username: "another" })).statusCode).toBe(412);
    const other = await idTokenFor("p-other", "Other");
    expect((await call("POST", "/v1/me/username", { username: "pia_p" }, other)).statusCode).toBe(409);
  });

  it("moves details to the private doc and back", async () => {
    await call("PUT", "/v1/me/profile/details", { bio: "Cutter", tags: ["ut"] });
    expect((await db.doc("profiles/p-user").get()).get("bio")).toBe("Cutter");
    expect((await call("PUT", "/v1/me/profile/privacy", { private: true })).statusCode).toBe(200);
    const main = (await db.doc("profiles/p-user").get()).data()!;
    expect(main.private).toBe(true);
    expect(main).not.toHaveProperty("bio");
    expect(main.username).toBe("pia_p");
    expect((await db.doc("profiles/p-user/private/details").get()).get("bio")).toBe("Cutter");
    await call("PUT", "/v1/me/profile/privacy", { private: false });
    expect((await db.doc("profiles/p-user").get()).get("bio")).toBe("Cutter");
    expect((await db.doc("profiles/p-user/private/details").get()).exists).toBe(false);
  });
});
