// Membership through the API against the Firestore and Auth emulators
// (pnpm test:emulator): real transactions in FirestoreDocStore, server
// timestamps, and the documents as stored. Uses its own uids (m-*); the
// files run one after another (--no-file-parallelism).
import { deleteApp, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { FirestoreDocStore } from "../src/firestore_store.js";
import { AlreadyExists } from "../src/store.js";
import { FirestoreTeamRepository } from "../src/teams/repository.js";

const projectId = "demo-stall10";
const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
if (!process.env.FIRESTORE_EMULATOR_HOST || !authHost) {
  throw new Error("Run with `pnpm test:emulator` (needs the Firestore and Auth emulators).");
}

const firebase = initializeApp({ projectId }, "membership-emulator-test");
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
      return { name: u.displayName, email: u.email };
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

const tokens: Record<string, string> = {};
const call = (method: "POST" | "PUT" | "PATCH" | "DELETE", url: string, uid: string, body?: object) =>
  app.inject({ method, url, headers: { authorization: `Bearer ${tokens[uid]}` }, ...(body && { payload: body }) });

beforeAll(async () => {
  for (const [uid, name] of [["m-owner", "Olive"], ["m-new", "Nia"], ["m-p1", "Pat"]]) {
    tokens[uid] = await idTokenFor(uid, name);
  }
  await db.doc("teams/m-team").set({
    name: "Emulator Haze",
    division: "open",
    level: "club",
    city: "Austin",
    ownerId: "m-owner",
    members: { "m-owner": "owner", "m-p1": "player" },
    memberIds: ["m-owner", "m-p1"],
    memberNames: { "m-owner": "Olive", "m-p1": "Pat" },
  });
});

afterAll(async () => {
  await app.close();
  await deleteApp(firebase);
});

describe("membership on the emulators", () => {
  let code: string;

  it("mints an invite code with the server's time", async () => {
    const res = await call("POST", "/v1/invite-codes", "m-owner", { teamId: "m-team", ttl: 45 });
    expect(res.statusCode).toBe(201);
    code = res.json().code;
    const snap = await db.doc(`inviteCodes/${code}`).get();
    expect(snap.get("createdAt")).toBeInstanceOf(Timestamp);
    expect(snap.get("expiresAt")).toBeInstanceOf(Timestamp);
    expect(snap.get("ttl")).toBe(45);
  });

  it("joins with it, writing the member and the join proof", async () => {
    const res = await call("POST", "/v1/teams/join", "m-new", { code: code.toLowerCase() });
    expect(res.json()).toEqual({ teamId: "m-team" });
    const team = (await db.doc("teams/m-team").get()).data()!;
    expect(team.members["m-new"]).toBe("player");
    expect(team.memberIds).toEqual(["m-owner", "m-p1", "m-new"]);
    expect(team.memberNames["m-new"]).toBe("Nia");
    expect((await db.doc("teams/m-team/joins/m-new").get()).data()).toEqual({ code });
  });

  it("saves roles with memberPerms worked out", async () => {
    const res = await call("PUT", "/v1/teams/m-team/roles", "m-owner", {
      roles: { r: { name: "Stats", perms: ["keepStats"] } },
      memberRoles: { "m-new": ["r"] },
    });
    expect(res.statusCode).toBe(200);
    const team = (await db.doc("teams/m-team").get()).data()!;
    expect(team.memberPerms).toEqual({ "m-new": ["keepStats"] });
  });

  it("removes a member, roles and all", async () => {
    expect((await call("DELETE", "/v1/teams/m-team/members/m-new", "m-owner")).statusCode).toBe(200);
    const team = (await db.doc("teams/m-team").get()).data()!;
    expect(team.memberIds).toEqual(["m-owner", "m-p1"]);
    expect(team.members).not.toHaveProperty("m-new");
    expect(team.memberRoles).toEqual({});
    expect(team.memberPerms).toEqual({});
  });

  it("edits details and the listing together", async () => {
    const res = await call("PATCH", "/v1/teams/m-team", "m-owner", { name: "Emulator Haze", level: "college", city: "Dallas" });
    expect(res.statusCode).toBe(200);
    expect((await db.doc("teams/m-team").get()).get("city")).toBe("Dallas");
    const listing = (await db.doc("teamDirectory/m-team").get()).data()!;
    expect(listing).toMatchObject({ name: "Emulator Haze", level: "college", city: "Dallas" });
    expect(listing.keywords).toContain("dallas");
  });

  it("records a join request with a server timestamp, and refuses a player removing anyone", async () => {
    await db.doc("teams/m-group").set({
      name: "Emulator Group",
      division: "mixed",
      level: "pickup",
      city: "",
      kind: "community",
      requiresApproval: true,
      description: "",
      location: null,
      ownerId: "m-owner",
      members: { "m-owner": "owner" },
      memberIds: ["m-owner"],
      memberNames: { "m-owner": "Olive" },
    });
    expect((await call("POST", "/v1/teams/m-group/join-requests", "m-new", {})).statusCode).toBe(200);
    expect((await db.doc("teams/m-group/joinRequests/m-new").get()).get("createdAt")).toBeInstanceOf(Timestamp);
    expect((await call("POST", "/v1/teams/m-group/join-requests/m-new/approve", "m-owner", {})).statusCode).toBe(200);
    expect((await db.doc("teams/m-group/joinRequests/m-new").get()).exists).toBe(false);
    expect((await call("DELETE", "/v1/teams/m-team/members/m-owner", "m-p1")).statusCode).toBe(412);
  });

  it("reports a create on an existing document as AlreadyExists", async () => {
    await db.doc("inviteCodes/MTAKEN").set({ teamId: "x" });
    await expect(store.transact(async (tx) => tx.create("inviteCodes/MTAKEN", { teamId: "y" }))).rejects.toBeInstanceOf(
      AlreadyExists,
    );
  });
});
