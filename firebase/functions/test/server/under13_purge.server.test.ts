// The scheduled under-13 purge (D-U13) against the Firestore emulator
// (npm run test:server), with a fake clock and fake Auth and Storage.

import { initializeApp } from "firebase-admin/app";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { beforeAll, describe, expect, it } from "vitest";

import { type PurgeDeps, purgePerRun, purgeUnderThirteen, under13RetentionMs } from "../../src/account/functions";

initializeApp({ projectId: "demo-frisbee" });
const db = getFirestore();

const day = 24 * 3600_000;
const now = Date.UTC(2027, 0, 20);
const at = (daysAgo: number) => Timestamp.fromMillis(now - daysAgo * day);

const auth = new Map<string, "disabled" | "enabled">();
const authDeleted: string[] = [];
const deps: PurgeDeps = {
  deleteFolder: async () => {},
  deleteAuthUser: async (u) => void (authDeleted.push(u), auth.delete(u)),
  authState: async (u) => auth.get(u) ?? "missing",
};

const exists = async (path: string) => (await db.doc(path).get()).exists;

beforeAll(async () => {
  const b = db.batch();
  const person = (uid: string, refusal: Record<string, unknown>, state?: "disabled" | "enabled") => {
    b.set(db.doc(`ageRefusals/${uid}`), { ciphertext: "c", ...refusal });
    b.set(db.doc(`profiles/${uid}`), { name: uid });
    if (state) auth.set(uid, state);
  };
  person("pOld", { under13: true, refusedAt: at(31) }, "disabled");
  person("pExact", { under13: true, refusedAt: at(30) }, "disabled");
  person("pNew", { under13: true, refusedAt: at(29) }, "disabled");
  person("pEnabled", { under13: true, refusedAt: at(40) }, "enabled");
  person("pLegacy", { refusedAt: at(90) }, "disabled"); // no marker: never purged
  person("pAdultOnly", { refusedAt: at(90) }, "enabled");
  person("pHalf", { under13: true, refusedAt: at(35) }); // login already gone, marker left over
  person("pNoDate", { under13: true }, "disabled"); // no usable refusedAt: skipped
  await b.commit();
});

describe("purgeUnderThirteen", () => {
  it("retains for 30 days", () => expect(under13RetentionMs).toBe(30 * day));

  it("deletes only marked refusals at least 30 days old whose login is disabled or gone", async () => {
    const r = await purgeUnderThirteen(db, now, deps);
    expect(r).toEqual({ deleted: 3, skippedEnabled: 1, failed: 0 });
    expect(authDeleted.sort()).toEqual(["pExact", "pHalf", "pOld"]);
    for (const uid of ["pOld", "pExact", "pHalf"]) {
      expect(await exists(`profiles/${uid}`), uid).toBe(false);
      expect(await exists(`ageRefusals/${uid}`), uid).toBe(false);
    }
    // Too new, still enabled, unmarked (older records), or no date: all kept.
    for (const uid of ["pNew", "pEnabled", "pLegacy", "pAdultOnly", "pNoDate"]) {
      expect(await exists(`profiles/${uid}`), uid).toBe(true);
      expect(await exists(`ageRefusals/${uid}`), uid).toBe(true);
    }
  });

  it("is idempotent: a second run does nothing more", async () => {
    const before = authDeleted.length;
    const r = await purgeUnderThirteen(db, now, deps);
    expect(r).toEqual({ deleted: 0, skippedEnabled: 1, failed: 0 });
    expect(authDeleted.length).toBe(before);
  });

  it("takes an account when the clock passes its 30th day", async () => {
    expect(await exists("profiles/pNew")).toBe(true);
    const r = await purgeUnderThirteen(db, now + 2 * day, deps);
    expect(r.deleted).toBe(1);
    expect(await exists("profiles/pNew")).toBe(false);
  });

  it("keeps the marker, and retries next run, when the login can't be deleted", async () => {
    await db.doc("ageRefusals/pRetry").set({ under13: true, refusedAt: at(50) });
    auth.set("pRetry", "disabled");
    const failing: PurgeDeps = { ...deps, deleteAuthUser: async () => Promise.reject(new Error("auth down")) };
    expect(await purgeUnderThirteen(db, now, failing)).toMatchObject({ deleted: 0, failed: 1 });
    expect(await exists("ageRefusals/pRetry")).toBe(true);
    expect(await purgeUnderThirteen(db, now, deps)).toMatchObject({ deleted: 1, failed: 0 });
    expect(await exists("ageRefusals/pRetry")).toBe(false);
  });

  it("deletes at most purgePerRun accounts a run", async () => {
    const b = db.batch();
    for (let i = 0; i < purgePerRun + 5; i++) {
      b.set(db.doc(`ageRefusals/bulk${String(i).padStart(3, "0")}`), { under13: true, refusedAt: at(60) });
      auth.set(`bulk${String(i).padStart(3, "0")}`, "disabled");
    }
    await b.commit();
    expect((await purgeUnderThirteen(db, now, deps)).deleted).toBe(purgePerRun);
    expect((await purgeUnderThirteen(db, now, deps)).deleted).toBe(5);
  }, 240_000);
});
