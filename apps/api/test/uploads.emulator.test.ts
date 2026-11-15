// Uploads against the Firestore, Auth and Storage emulators: the raw file
// is put with the Admin SDK (the emulator can't sign URLs, so signing is
// stubbed and not verified here), then completed and compressed for real.
// Own uids (up-*).
import { deleteApp, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import sharp from "sharp";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { FirestoreDocStore } from "../src/firestore_store.js";
import { FirebaseMediaStorage } from "../src/media/storage.js";
import { FirestoreTeamRepository } from "../src/teams/repository.js";

const projectId = "demo-stall10";
const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
if (!process.env.FIRESTORE_EMULATOR_HOST || !authHost || !process.env.FIREBASE_STORAGE_EMULATOR_HOST) {
  throw new Error("Run with `pnpm test:emulator` (needs the Firestore, Auth and Storage emulators).");
}

const firebase = initializeApp({ projectId }, "uploads-emulator-test");
const db = getFirestore(firebase);
const auth = getAuth(firebase);
const store = new FirestoreDocStore(db);
const bucket = getStorage(firebase).bucket(`${projectId}.appspot.com`);
class EmulatorStorage extends FirebaseMediaStorage {
  override async signedUploadUrl(path: string, contentType: string) {
    return { url: `emulator:${path}`, headers: { "content-type": contentType } };
  }
}
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
  media: new EmulatorStorage(bucket),
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
const call = (url: string, body: object = {}) =>
  app.inject({ method: "POST", url, payload: body, headers: { authorization: `Bearer ${token}` } });

beforeAll(async () => {
  token = await idTokenFor("up-user", "Una Upload");
});

afterAll(async () => {
  await app.close();
  await deleteApp(firebase);
});

describe("uploads on the emulators", () => {
  it("compresses an uploaded photo into Storage and clears the raw file", async () => {
    const photo = await sharp({ create: { width: 3000, height: 2000, channels: 3, background: "#884422" } }).jpeg().toBuffer();
    const res = await call("/v1/uploads", { purpose: "avatar", contentType: "image/jpeg", size: photo.length });
    expect(res.statusCode).toBe(201);
    const { id } = res.json();
    await bucket.file(`uploads/raw/up-user/${id}`).save(photo, { contentType: "image/jpeg", resumable: false });

    const done = await call(`/v1/uploads/${id}/complete`);
    expect(done.json()).toMatchObject({ status: "ready", width: 1920, height: 1280, path: `users/up-user/profile/${id}.jpg` });
    const [saved] = await bucket.file(`users/up-user/profile/${id}.jpg`).download();
    expect((await sharp(saved).metadata()).width).toBe(1920);
    const [meta] = await bucket.file(`users/up-user/profile/${id}.jpg`).getMetadata();
    expect(meta.cacheControl).toBe("public, max-age=31536000, immutable");
    expect((await bucket.file(`uploads/raw/up-user/${id}`).exists())[0]).toBe(false);
    expect((await db.doc(`uploads/${id}`).get()).get("status")).toBe("ready");
  });

  it("copies a chat file into the message's folder as sent, in the bucket", async () => {
    await db.doc("conversations/up-other_up-user").set({ participants: ["up-other", "up-user"], status: "accepted" });
    const pdf = Buffer.from("%PDF-1.7 a small document");
    const res = await call("/v1/uploads", {
      purpose: "chat",
      targetId: "conversations/up-other_up-user",
      itemId: "m1",
      contentType: "application/pdf",
      name: "Line calls.pdf",
      size: pdf.length,
    });
    expect(res.statusCode).toBe(201);
    const { id } = res.json();
    await bucket.file(`uploads/raw/up-user/${id}`).save(pdf, { contentType: "application/pdf", resumable: false });

    const done = await call(`/v1/uploads/${id}/complete`);
    const path = `conversations/up-other_up-user/up-user/m1/${id}-Line calls.pdf`;
    expect(done.json()).toEqual({ id, status: "ready", path, contentType: "application/pdf" });
    const [saved] = await bucket.file(path).download();
    expect(saved.equals(pdf)).toBe(true);
    const [meta] = await bucket.file(path).getMetadata();
    expect(meta.contentType).toBe("application/pdf");
    expect(meta.cacheControl).toBe("public, max-age=31536000, immutable");
    expect((await bucket.file(`uploads/raw/up-user/${id}`).exists())[0]).toBe(false);
  });

  it("copies only the generation it checked, and removes an unsent file", async () => {
    await db.doc("conversations/up-other_up-user").set({ participants: ["up-other", "up-user"], status: "accepted" });
    const pdf = Buffer.from("%PDF-1.7 the checked document");
    const body = { purpose: "chat", targetId: "conversations/up-other_up-user", itemId: "m2", contentType: "application/pdf", name: "a.pdf", size: pdf.length };
    const raw = (id: string) => bucket.file(`uploads/raw/up-user/${id}`);
    const media = new FirebaseMediaStorage(bucket);

    // Writing the raw file again gives it a new generation. (The emulator
    // ignores sourceGeneration on copy, so the pinned copy itself is
    // covered by the fakes; complete also re-checks the copy's size.)
    const first = (await call("/v1/uploads", body)).json().id as string;
    await raw(first).save(pdf, { resumable: false });
    const checked = (await media.stat(`uploads/raw/up-user/${first}`))!;
    expect(checked.size).toBe(pdf.length);
    expect(checked.generation).not.toBe("");
    await raw(first).save(Buffer.from("<html>swapped</html>"), { resumable: false });
    expect((await media.stat(`uploads/raw/up-user/${first}`))!.generation).not.toBe(checked.generation);

    // Completed, then taken out of the composer.
    const second = (await call("/v1/uploads", body)).json().id as string;
    await raw(second).save(pdf, { resumable: false });
    const done = await call(`/v1/uploads/${second}/complete`);
    const path = done.json().path as string;
    expect((await bucket.file(path).exists())[0]).toBe(true);
    const removed = await app.inject({ method: "DELETE", url: `/v1/uploads/${second}`, headers: { authorization: `Bearer ${token}` } });
    expect(removed.statusCode).toBe(204);
    expect((await bucket.file(path).exists())[0]).toBe(false);
    expect((await db.doc(`uploads/${second}`).get()).get("status")).toBe("removed");
  });

  it("rejects a file whose bytes aren't media", async () => {
    const res = await call("/v1/uploads", { purpose: "post", itemId: "i1", contentType: "image/png", size: 20 });
    const { id } = res.json();
    await bucket.file(`uploads/raw/up-user/${id}`).save(Buffer.from("definitely not a png"), { resumable: false });
    const done = await call(`/v1/uploads/${id}/complete`);
    expect(done.statusCode).toBe(400);
    expect((await db.doc(`uploads/${id}`).get()).get("status")).toBe("failed");
  });
});
