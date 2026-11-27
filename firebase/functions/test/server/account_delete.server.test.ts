// Account deletion end to end against the Firestore emulator
// (npm run test:server): the cascade, what it keeps, and a second run.
// Storage and Auth are stood in for with DeleteDeps.

import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { beforeAll, describe, expect, it } from "vitest";

import { type DeleteDeps, deleteAccountFully } from "../../src/account/functions";
import { applyFollowCounts } from "../../src/follows/functions";

initializeApp({ projectId: "demo-frisbee" });
const db = getFirestore();

const gone = "delGone";
const other = "delOther";
const folders: string[] = [];
const authDeleted: string[] = [];
const deps: DeleteDeps = {
  deleteFolder: async (p) => void folders.push(p),
  deleteAuthUser: async (u) => void authDeleted.push(u),
};

beforeAll(async () => {
  const b = db.batch();
  b.set(db.doc(`users/${gone}`), { agreedTerms: 1 });
  b.set(db.doc(`users/${gone}/follows/team_t1`), { key: "team_t1" });
  b.set(db.doc(`users/${gone}/devices/fidA`), { token: "x" });
  b.set(db.doc(`fidOwners/fidA`), { uid: gone });
  b.set(db.doc(`fidOwners/fidB`), { uid: other });
  b.set(db.doc(`profiles/${gone}`), { name: "Gone", private: true });
  b.set(db.doc(`profiles/${gone}/followRequests/${other}`), { name: "Other" });
  b.set(db.doc(`profiles/${other}`), { name: "Other", private: true });
  b.set(db.doc(`profiles/${other}/followRequests/${gone}`), { name: "Gone" });
  b.set(db.doc(`profiles/${other}/followRequests/someoneElse`), { name: "Else" });
  b.set(db.doc(`personalDetails/${gone}`), { ciphertext: "c" });
  b.set(db.doc(`ageRefusals/${gone}`), { ciphertext: "c", refusedAt: new Date() });
  b.set(db.doc(`limits/${gone}`), { exportedAt: new Date() });
  b.set(db.doc(`followCounts/user_${gone}`), { following: 1 });
  b.set(db.doc(`followCounts/user_${other}`), { followers: 3 });
  // Posts by Other that Gone liked and reposted, and Gone's own post.
  b.set(db.doc(`posts/delP1`), { authorId: other, likedBy: [gone, "x"], repostedBy: [gone] });
  b.set(db.doc(`posts/delP2`), { authorId: other, likedBy: ["x"], repostedBy: [] });
  b.set(db.doc(`posts/r_delP1_${gone}`), { authorId: gone, kind: "repost" });
  b.set(db.doc(`posts/delMine`), { authorId: gone });
  // A team Gone is on, with an org-added membership.
  b.set(db.doc(`teams/delTeam`), {
    ownerId: other,
    members: { [other]: "owner", [gone]: "player" },
    memberIds: [other, gone],
    memberNames: { [other]: "O", [gone]: "G" },
    orgMembers: [gone, "z"],
  });
  // A tournament with Gone's sign-up and fee ledger row.
  b.set(db.doc(`tournaments/delT`), { name: "T" });
  b.set(db.doc(`tournaments/delT/signups/${gone}`), { name: "Gone", gender: "mmp", divisionId: "d1", skill: 3, status: "accepted" });
  b.set(db.doc(`tournaments/delT/signups/${other}`), { name: "Other", gender: "wmp", divisionId: "d1", skill: 2, status: "accepted" });
  b.set(db.doc(`tournaments/delT/payments/${gone}`), { paid: true, note: "Paid online through Stall 10" });
  // Moderation and payment records kept for accounting.
  b.set(db.doc(`reports/delR1`), { reporterId: gone, reason: "spam", status: "open" });
  b.set(db.doc(`payerCharges/delT~${gone}`), { payerId: gone });
  b.set(db.doc(`charges/delC1`), { payerId: gone, amountCents: 1000 });
  await b.commit();
});

describe("deleteAccountFully", () => {
  it("deletes the person's own data, fixes counters, anonymises sign-ups and keeps the ledger and reports", async () => {
    await deleteAccountFully(db, gone, deps);

    const exists = async (path: string) => (await db.doc(path).get()).exists;
    // Their own documents.
    for (const path of [
      `users/${gone}`,
      `users/${gone}/follows/team_t1`,
      `users/${gone}/devices/fidA`,
      `fidOwners/fidA`,
      `profiles/${gone}`,
      `profiles/${gone}/followRequests/${other}`,
      `personalDetails/${gone}`,
      `ageRefusals/${gone}`,
      `limits/${gone}`,
      `followCounts/user_${gone}`,
      `posts/delMine`,
      `posts/r_delP1_${gone}`,
    ]) {
      expect(await exists(path), path).toBe(false);
    }
    // Other people's data stays.
    expect(await exists(`fidOwners/fidB`)).toBe(true);
    expect(await exists(`followCounts/user_${other}`)).toBe(true);
    expect(await exists(`profiles/${other}/followRequests/someoneElse`)).toBe(true);
    // Their request to follow someone else's private profile.
    expect(await exists(`profiles/${other}/followRequests/${gone}`)).toBe(false);

    // Likes and reposts come off the posts (the counts are the lists' lengths).
    const p1 = (await db.doc("posts/delP1").get()).data()!;
    expect(p1.likedBy).toEqual(["x"]);
    expect(p1.repostedBy).toEqual([]);
    expect((await db.doc("posts/delP2").get()).data()!.likedBy).toEqual(["x"]);

    // The team lost them everywhere, orgMembers included.
    const team = (await db.doc("teams/delTeam").get()).data()!;
    expect(team.memberIds).toEqual([other]);
    expect(team.members).toEqual({ [other]: "owner" });
    expect(team.orgMembers).toEqual(["z"]);

    // Sign-up: name and gender gone, the rest kept; someone else's untouched.
    const signup = (await db.doc(`tournaments/delT/signups/${gone}`).get()).data()!;
    expect(signup).toMatchObject({ name: "Deleted user", gender: null, divisionId: "d1", skill: 3, status: "accepted" });
    expect((await db.doc(`tournaments/delT/signups/${other}`).get()).data()!.name).toBe("Other");

    // Kept for accounting and moderation.
    expect(await exists(`tournaments/delT/payments/${gone}`)).toBe(true);
    expect(await exists(`payerCharges/delT~${gone}`)).toBe(true);
    expect(await exists("charges/delC1")).toBe(true);
    expect(await exists("reports/delR1")).toBe(true);

    expect(authDeleted).toEqual([gone]);
    expect(folders).toContain(`users/${gone}/`);
  });

  it("can run again after it finished, or part way, without error", async () => {
    await expect(deleteAccountFully(db, gone, deps)).resolves.toBeUndefined();
    expect((await db.doc(`tournaments/delT/signups/${gone}`).get()).data()!.name).toBe("Deleted user");
  });

  it("keeps the age-refusal record until the login is gone", async () => {
    const uid = "delRetry";
    await db.doc(`ageRefusals/${uid}`).set({ refusedAt: new Date() });
    await expect(
      deleteAccountFully(db, uid, { ...deps, deleteAuthUser: async () => Promise.reject(new Error("auth down")) }),
    ).rejects.toThrow("auth down");
    expect((await db.doc(`ageRefusals/${uid}`).get()).exists).toBe(true);
    await deleteAccountFully(db, uid, deps);
    expect((await db.doc(`ageRefusals/${uid}`).get()).exists).toBe(false);
  });
});

describe("applyFollowCounts", () => {
  it("does not write back the counts of a deleted profile on a late decrement", async () => {
    await applyFollowCounts(db, [
      { key: "user_lateGone", field: "followers", by: -1 },
      { key: "user_lateGone", field: "following", by: -1 },
    ]);
    expect((await db.doc("followCounts/user_lateGone").get()).exists).toBe(false);
  });

  it("still counts for a person who exists, and increments for anyone", async () => {
    await db.doc("profiles/lateHere").set({ name: "Here" });
    await applyFollowCounts(db, [
      { key: "user_lateHere", field: "followers", by: 1 },
      { key: "user_lateHere", field: "followers", by: -1 },
      { key: "team_lateT", field: "followers", by: 1 },
    ]);
    expect((await db.doc("followCounts/user_lateHere").get()).data()).toEqual({ followers: 0 });
    expect((await db.doc("followCounts/team_lateT").get()).data()).toEqual({ followers: 1 });
  });
});
