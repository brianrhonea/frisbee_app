// Folding by item and taking items back (deliver / retract) against the
// Firestore emulator (npm run test:server).

import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import type { Messaging } from "firebase-admin/messaging";
import { describe, expect, it } from "vitest";

import { deliver, removeEntry, retract } from "../../src/notifications/deliver";
import { followRequestNotice, likeNotice } from "../../src/notifications/model";

initializeApp({ projectId: "demo-frisbee" });
const db = getFirestore();
// No devices are registered, so nothing is ever sent.
const messaging = { sendEach: async () => ({ successCount: 0, failureCount: 0, responses: [] }) } as unknown as Messaging;
const entry = (uid: string, id: string) => db.doc(`users/${uid}/notifications/${id}`).get();

describe("deliver and retract", () => {
  it("counts a like, unlike, like as one like, and takes it back", async () => {
    await db.doc("posts/p1").set({ authorId: "owner", body: "Good throws", likedBy: ["sam"] });
    const like = () => likeNotice({ postId: "p1", post: { body: "Good throws" }, likerName: "Sam", likerId: "sam" });
    await deliver(db, messaging, ["owner"], like());
    await deliver(db, messaging, ["owner"], like());
    let e = (await entry("owner", "likes_p1")).data();
    expect(e?.count).toBe(1);
    expect(e?.title).toBe("Sam liked your post");

    await db.doc("posts/p1").update({ likedBy: ["sam", "ann"] });
    await deliver(db, messaging, ["owner"], likeNotice({ postId: "p1", post: {}, likerName: "Ann", likerId: "ann" }));
    e = (await entry("owner", "likes_p1")).data();
    expect(e?.count).toBe(2);
    expect(e?.title).toBe("2 new likes on your post");

    await retract(db, "owner", "likes_p1", "ann");
    e = (await entry("owner", "likes_p1")).data();
    expect(e?.count).toBe(1);
    expect(e?.title).toBe("Sam liked your post");
    await retract(db, "owner", "likes_p1", "sam");
    expect((await entry("owner", "likes_p1")).exists).toBe(false);
  });

  it("doesn't bring back a like taken back before the trigger ran", async () => {
    await db.doc("posts/p2").set({ authorId: "owner", likedBy: [] });
    await deliver(db, messaging, ["owner"], likeNotice({ postId: "p2", post: {}, likerName: "Sam", likerId: "sam" }));
    expect((await entry("owner", "likes_p2")).exists).toBe(false);
  });

  it("counts a request asked several times as one person, and drops it when answered", async () => {
    await db.doc("profiles/owner/followRequests/riley").set({ name: "Riley" });
    const ask = () => followRequestNotice({ requesterId: "riley", name: "Riley", ownerId: "owner" });
    for (let i = 0; i < 4; i++) await deliver(db, messaging, ["owner"], ask());
    const e = (await entry("owner", "followRequests")).data();
    expect(e?.count).toBe(1);
    expect(e?.title).toBe("Riley wants to follow you");
    await retract(db, "owner", "followRequests", "riley");
    expect((await entry("owner", "followRequests")).exists).toBe(false);
  });

  it("keeps a request asked again before the take-back trigger ran", async () => {
    await db.doc("profiles/owner2/followRequests/riley").set({ name: "Riley" });
    await deliver(db, messaging, ["owner2"], followRequestNotice({ requesterId: "riley", name: "Riley", ownerId: "owner2" }));
    // Taken back and asked again; the delete's trigger arrives last.
    const unless = { path: "profiles/owner2/followRequests/riley" };
    await retract(db, "owner2", "followRequests", "riley", unless);
    expect((await entry("owner2", "followRequests")).data()?.count).toBe(1);
    // Really taken back: gone.
    await db.doc("profiles/owner2/followRequests/riley").delete();
    await retract(db, "owner2", "followRequests", "riley", unless);
    expect((await entry("owner2", "followRequests")).exists).toBe(false);
  });

  it("keeps a like given again before the unlike's trigger ran", async () => {
    await db.doc("posts/p3").set({ authorId: "owner", likedBy: ["sam"] });
    await deliver(db, messaging, ["owner"], likeNotice({ postId: "p3", post: {}, likerName: "Sam", likerId: "sam" }));
    await retract(db, "owner", "likes_p3", "sam", { path: "posts/p3", holds: (d) => (d.likedBy as string[]).includes("sam") });
    expect((await entry("owner", "likes_p3")).exists).toBe(true);
  });

  it("leaves entries without items alone, and removes one by id", async () => {
    await db.doc("users/owner/notifications/old").set({ title: "Old", count: 5, read: false });
    await retract(db, "owner", "old", "anyone");
    expect((await entry("owner", "old")).data()?.count).toBe(5);
    await removeEntry(db, "owner", "old");
    expect((await entry("owner", "old")).exists).toBe(false);
  });
});
