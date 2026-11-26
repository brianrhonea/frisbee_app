// Device ownership (fidOwners), delivery's check and the backfill against the
// Firestore emulator (npm run test:server).

import { initializeApp } from "firebase-admin/app";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import type { Messaging } from "firebase-admin/messaging";
import { describe, expect, it } from "vitest";

import { runBackfill } from "../../scripts/backfill-fid-owners";
import { claimFid, releaseFid } from "../../src/devices/owners";
import { deliver } from "../../src/notifications/deliver";
import { followRequestNotice } from "../../src/notifications/model";

initializeApp({ projectId: "demo-frisbee" });
const db = getFirestore();

const device = (uid: string, fid: string, at: number) =>
  db.doc(`users/${uid}/devices/${fid}`).set({ platform: "iOS", updatedAt: Timestamp.fromMillis(at) });
const hasDevice = async (uid: string, fid: string) => (await db.doc(`users/${uid}/devices/${fid}`).get()).exists;
const owner = async (fid: string) => (await db.doc(`fidOwners/${fid}`).get()).data()?.uid;

describe("claimFid and releaseFid", () => {
  it("moves a FID to the account that registered it last, deleting the old copy", async () => {
    await device("a1", "f1", 100);
    expect(await claimFid(db, "a1", "f1", 100)).toBe("claimed");
    expect(await owner("f1")).toBe("a1");

    await device("b1", "f1", 200);
    expect(await claimFid(db, "b1", "f1", 200)).toBe("takenOver");
    expect(await owner("f1")).toBe("b1");
    expect(await hasDevice("a1", "f1")).toBe(false);
    expect(await hasDevice("b1", "f1")).toBe(true);
  });

  it("leaves other FIDs alone", async () => {
    await device("a2", "f2a", 100);
    await device("a2", "f2b", 100);
    await claimFid(db, "a2", "f2a", 100);
    await claimFid(db, "a2", "f2b", 100);
    await device("b2", "f2a", 200);
    await claimFid(db, "b2", "f2a", 200);
    expect(await owner("f2a")).toBe("b2");
    expect(await owner("f2b")).toBe("a2");
    expect(await hasDevice("a2", "f2b")).toBe(true);
  });

  it("changes nothing when the owner registers its own FID again", async () => {
    await device("a3", "f3", 100);
    await claimFid(db, "a3", "f3", 100);
    expect(await claimFid(db, "a3", "f3", 100)).toBe("unchanged");
    expect(await claimFid(db, "a3", "f3", 300)).toBe("unchanged");
    expect(await owner("f3")).toBe("a3");
    expect(await hasDevice("a3", "f3")).toBe(true);
  });

  it("doesn't let the old owner's delete remove the new owner's mapping", async () => {
    await device("a4", "f4", 100);
    await claimFid(db, "a4", "f4", 100);
    await device("b4", "f4", 200);
    await claimFid(db, "b4", "f4", 200);
    // The trigger for the delete the takeover caused.
    expect(await releaseFid(db, "a4", "f4")).toBe(false);
    expect(await owner("f4")).toBe("b4");
    // The real owner signing out does clear it.
    expect(await releaseFid(db, "b4", "f4")).toBe(true);
    expect((await db.doc("fidOwners/f4").get()).exists).toBe(false);
  });

  it("ignores a stale event from an older registration", async () => {
    await device("b5", "f5", 200);
    await claimFid(db, "b5", "f5", 200);
    await device("a5", "f5", 100);
    expect(await claimFid(db, "a5", "f5", 100)).toBe("stale");
    expect(await owner("f5")).toBe("b5");
    expect(await hasDevice("b5", "f5")).toBe(true);
  });

  it("ignores a takeover when the old owner has registered again since", async () => {
    await device("a6", "f6", 100);
    await claimFid(db, "a6", "f6", 100);
    await device("a6", "f6", 500); // re-registered; its event isn't processed yet
    await device("b6", "f6", 200);
    expect(await claimFid(db, "b6", "f6", 200)).toBe("stale");
    expect(await hasDevice("a6", "f6")).toBe(true);
    expect(await owner("f6")).toBe("a6");
  });
});

describe("deliver and device ownership", () => {
  const sent: string[] = [];
  const messaging = {
    sendEach: async (m: { fid: string }[]) => {
      m.forEach((x) => sent.push(x.fid));
      return { successCount: m.length, failureCount: 0, responses: m.map(() => ({ success: true })) };
    },
  } as unknown as Messaging;
  const notice = (ownerId: string) => followRequestNotice({ requesterId: "riley", name: "Riley", ownerId });

  it("skips a FID owned by another account and deletes the stale device doc", async () => {
    await db.doc("profiles/o1/followRequests/riley").set({ name: "Riley" });
    await device("o1", "mine", 100);
    await device("o1", "moved", 100);
    await db.doc("fidOwners/mine").set({ uid: "o1", updatedAt: Timestamp.fromMillis(100) });
    await db.doc("fidOwners/moved").set({ uid: "someone-else", updatedAt: Timestamp.fromMillis(200) });
    sent.length = 0;
    await deliver(db, messaging, ["o1"], notice("o1"));
    expect(sent).toEqual(["mine"]);
    expect(await hasDevice("o1", "moved")).toBe(false);
    expect(await hasDevice("o1", "mine")).toBe(true);
    // The mapping for the new owner is untouched.
    expect(await owner("moved")).toBe("someone-else");
  });

  it("sends as before when there is no mapping yet", async () => {
    await db.doc("profiles/o2/followRequests/riley").set({ name: "Riley" });
    await device("o2", "unmapped", 100);
    sent.length = 0;
    await deliver(db, messaging, ["o2"], notice("o2"));
    expect(sent).toEqual(["unmapped"]);
    expect(await hasDevice("o2", "unmapped")).toBe(true);
  });

  it("sends nothing when every device is owned by another account", async () => {
    await db.doc("profiles/o3/followRequests/riley").set({ name: "Riley" });
    await device("o3", "gone", 100);
    await db.doc("fidOwners/gone").set({ uid: "x", updatedAt: Timestamp.fromMillis(200) });
    sent.length = 0;
    await deliver(db, messaging, ["o3"], notice("o3"));
    expect(sent).toEqual([]);
    expect(await hasDevice("o3", "gone")).toBe(false);
  });
});

describe("runBackfill", () => {
  const seed = async () => {
    await device("bf-a", "bf1", 100);
    await device("bf-b", "bf1", 300);
    await device("bf-a", "bf2", 100);
  };

  it("dry run reads only", async () => {
    await seed();
    const logs: string[] = [];
    const r = await runBackfill(db, false, (m) => logs.push(m));
    expect(r.written).toBe(0);
    expect(r.deleted).toBe(0);
    expect((await db.doc("fidOwners/bf1").get()).exists).toBe(false);
    expect(await hasDevice("bf-a", "bf1")).toBe(true);
    expect(logs.some((l) => l.includes("would delete users/bf-a/devices/bf1"))).toBe(true);
  });

  it("apply writes the newest owner per FID and deletes the older copies", async () => {
    await runBackfill(db, true, () => undefined);
    expect(await owner("bf1")).toBe("bf-b");
    expect(await owner("bf2")).toBe("bf-a");
    expect(await hasDevice("bf-a", "bf1")).toBe(false);
    expect(await hasDevice("bf-b", "bf1")).toBe(true);
    expect(await hasDevice("bf-a", "bf2")).toBe(true);
  });
});
