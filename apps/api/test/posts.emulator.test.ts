// Likes and reposts through the API against the emulators: the repost and
// the original's repostedBy in one real transaction. Own ids (po-*).
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

const firebase = initializeApp({ projectId }, "posts-emulator-test");
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
const call = (method: "PUT" | "DELETE", url: string, body?: object) =>
  app.inject({ method, url, ...(body && { payload: body }), headers: { authorization: `Bearer ${token}` } });

beforeAll(async () => {
  token = await idTokenFor("po-user", "Paula Post");
  await db.doc("posts/po-orig").set({
    kind: "text",
    authorId: "po-author",
    authorName: "Ari Author",
    body: "Original",
    likedBy: [],
    repostedBy: [],
    createdAt: Timestamp.now(),
  });
  await db.doc("posts/r_po-orig_po-user").delete();
});

afterAll(async () => {
  await app.close();
  await deleteApp(firebase);
});

describe("posts on Firestore", () => {
  it("likes and unlikes", async () => {
    expect((await call("PUT", "/v1/posts/po-orig/like")).json()).toEqual({ liked: true, likeCount: 1 });
    expect((await db.doc("posts/po-orig").get()).get("likedBy")).toEqual(["po-user"]);
    expect((await call("DELETE", "/v1/posts/po-orig/like")).json()).toEqual({ liked: false, likeCount: 0 });
  });

  it("reposts with a server timestamp and undoes it, together with repostedBy", async () => {
    const res = await call("PUT", "/v1/posts/po-orig/repost", { note: "Nice" });
    expect(res.json()).toEqual({ reposted: true, repostCount: 1 });
    const repost = await db.doc("posts/r_po-orig_po-user").get();
    expect(repost.get("kind")).toBe("repost");
    expect(repost.get("authorName")).toBe("Paula Post");
    expect(repost.get("createdAt")).toBeInstanceOf(Timestamp);
    expect(repost.get("repostOf")).toEqual({ postId: "po-orig", authorId: "po-author", authorName: "Ari Author" });
    expect((await db.doc("posts/po-orig").get()).get("repostedBy")).toEqual(["po-user"]);

    expect((await call("DELETE", "/v1/posts/po-orig/repost")).json()).toEqual({ reposted: false, repostCount: 0 });
    expect((await db.doc("posts/r_po-orig_po-user").get()).exists).toBe(false);
    expect((await db.doc("posts/po-orig").get()).get("repostedBy")).toEqual([]);
  });
});
