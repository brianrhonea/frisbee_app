// Account deletion's share of calendars (leaveCalendars) against the
// Firestore emulator (npm run test:server).

import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { beforeAll, describe, expect, it } from "vitest";

import { leaveCalendars } from "../../src/account/functions";

initializeApp({ projectId: "demo-frisbee" });
const db = getFirestore();

beforeAll(async () => {
  const batch = db.batch();
  // Gone's own calendar, with an event and an outstanding invite to Ann.
  batch.set(db.doc("calendars/goneCal"), {
    ownerId: "gone",
    members: { gone: "owner", bo: "view" },
    memberIds: ["gone", "bo"],
    pending: { ann: "edit" },
  });
  batch.set(db.doc("calendars/goneCal/events/e1"), { title: "Track" });
  batch.set(db.doc("users/ann/calendarInvites/goneCal"), { calendarId: "goneCal", role: "edit", fromId: "gone" });
  // Ann's calendars: Gone is on one, and invited to the other.
  batch.set(db.doc("calendars/annCal"), {
    ownerId: "ann",
    members: { ann: "owner", gone: "edit", bo: "view" },
    memberIds: ["ann", "gone", "bo"],
    pending: {},
  });
  batch.set(db.doc("calendars/annCal2"), {
    ownerId: "ann",
    members: { ann: "owner" },
    memberIds: ["ann"],
    pending: { gone: "view", bo: "view" },
  });
  batch.set(db.doc("users/gone/calendarInvites/annCal2"), { calendarId: "annCal2", role: "view", fromId: "ann" });
  batch.set(db.doc("calendarFeeds/goneHash"), { uid: "gone" });
  batch.set(db.doc("calendarFeedOwners/gone"), { token: "t", hash: "goneHash" });
  await batch.commit();
});

describe("leaveCalendars", () => {
  it("deletes their calendars, takes them off others', and turns their link off", async () => {
    await leaveCalendars(db, "gone");
    expect((await db.doc("calendars/goneCal").get()).exists).toBe(false);
    expect((await db.doc("calendars/goneCal/events/e1").get()).exists).toBe(false);
    expect((await db.doc("users/ann/calendarInvites/goneCal").get()).exists).toBe(false);

    const ann = (await db.doc("calendars/annCal").get()).data()!;
    expect(ann.members).toEqual({ ann: "owner", bo: "view" });
    expect(ann.memberIds).toEqual(["ann", "bo"]);
    expect((await db.doc("calendars/annCal2").get()).data()!.pending).toEqual({ bo: "view" });

    expect((await db.doc("calendarFeeds/goneHash").get()).exists).toBe(false);
    expect((await db.doc("calendarFeedOwners/gone").get()).exists).toBe(false);
  });
});
