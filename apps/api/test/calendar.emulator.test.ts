// Shared calendars against the Firestore emulator (pnpm test:emulator):
// the real array-contains and date-range queries, over events saved the
// way the app saves them (Timestamps) and the way the API does.
import { deleteApp, initializeApp } from "firebase-admin/app";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { FirestoreCalendarRepository } from "../src/calendar/repository.js";
import { FirestoreDocStore } from "../src/firestore_store.js";
import { FakeTeamRepository, FakeUsers, FakeVerifier } from "./fakes.js";

const projectId = "demo-stall10";
if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error("Run with `pnpm test:emulator`.");

const firebase = initializeApp({ projectId }, "calendar-emulator-test");
const db = getFirestore(firebase);
const app = buildApp({
  verifier: new FakeVerifier(),
  users: new FakeUsers(),
  teams: new FakeTeamRepository(),
  store: new FirestoreDocStore(db),
  calendar: new FirestoreCalendarRepository(db),
});
const call = (method: "GET" | "POST" | "PUT", url: string, uid: string, body?: object) =>
  app.inject({ method, url, ...(body && { payload: body }), headers: { authorization: `Bearer token:${uid}` } });

beforeAll(async () => {
  await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${projectId}/databases/(default)/documents`, {
    method: "DELETE",
  });
  const batch = db.batch();
  batch.set(db.doc("profiles/owner"), { name: "Olive Owner" });
  batch.set(db.doc("profiles/viewer"), { name: "Vic Viewer" });
  // As the app writes one (saveMyEvent).
  batch.set(db.doc("users/owner/events/fromApp"), {
    title: "Gym",
    type: "workout",
    startsAt: Timestamp.fromDate(new Date("2026-11-16T15:00:00Z")),
    endsAt: null,
    location: "",
    notes: "private",
    poll: null,
  });
  batch.set(db.doc("users/owner/events/later"), {
    title: "Later",
    type: "other",
    startsAt: Timestamp.fromDate(new Date("2027-02-01T15:00:00Z")),
    endsAt: null,
    location: "",
    notes: "",
    poll: null,
  });
  await batch.commit();
});

afterAll(async () => {
  await app.close();
  await deleteApp(firebase);
});

describe("shared calendars (emulator)", () => {
  it("finds calendars shared with the caller and their events in the window", async () => {
    const created = await call("POST", "/v1/me/events", "owner", {
      title: "Track",
      type: "practice",
      startsAt: "2026-11-15T17:00:00.000Z",
      notes: "also private",
    });
    expect(created.statusCode).toBe(201);
    const stored = (await db.doc(`users/owner/events/${created.json().id}`).get()).data()!;
    expect(stored.startsAt).toBeInstanceOf(Timestamp);
    expect(stored.poll).toBeNull();

    expect((await call("PUT", "/v1/me/calendar/viewers", "owner", { viewers: ["viewer"] })).statusCode).toBe(200);
    const res = await call(
      "GET",
      "/v1/me/calendar/shared?from=2026-11-13T00:00:00Z&to=2026-11-20T00:00:00Z",
      "viewer",
    );
    expect(res.statusCode).toBe(200);
    const [calendar] = res.json().calendars;
    expect(calendar.owner.name).toBe("Olive Owner");
    expect(calendar.events.map((e: { title: string }) => e.title)).toEqual(["Track", "Gym"]);
    expect(calendar.events[1].startsAt).toBe("2026-11-16T15:00:00.000Z");
    expect(JSON.stringify(res.json())).not.toContain("private");
  });
});
