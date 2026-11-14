// Calendars against the Firestore emulator (pnpm test:emulator): the real
// memberIds and date-range queries, over events saved the way the app saves
// them (Timestamps) and the way the API does, and the feed's lookups.
import { deleteApp, initializeApp } from "firebase-admin/app";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import type { BrowseRepository } from "../src/browse/repository.js";
import { FirestoreCalendarRepository } from "../src/calendar/repository.js";
import { FirestoreDocStore } from "../src/firestore_store.js";
import { FirestoreRateLimiter } from "../src/limits/limiter.js";
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
  browse: { repo: {} as BrowseRepository, limiter: new FirestoreRateLimiter(db), imageUrl: (p) => p },
});
const call = (method: "GET" | "POST", url: string, uid: string | null, body?: object) =>
  app.inject({ method, url, ...(body && { payload: body }), headers: uid ? { authorization: `Bearer token:${uid}` } : {} });

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

describe("calendars (emulator)", () => {
  it("shares a calendar once the invite is accepted, with its events in the window", async () => {
    const created = await call("POST", "/v1/calendars/owner/events", "owner", {
      title: "Track",
      type: "practice",
      startsAt: "2026-11-15T17:00:00.000Z",
      notes: "also private",
    });
    expect(created.statusCode).toBe(201);
    const stored = (await db.doc(`users/owner/events/${created.json().id}`).get()).data()!;
    expect(stored.startsAt).toBeInstanceOf(Timestamp);
    expect(stored.poll).toBeNull();

    const window = "from=2026-11-13T00:00:00Z&to=2026-11-20T00:00:00Z";
    expect((await call("POST", "/v1/calendars/owner/invites", "owner", { uid: "viewer" })).statusCode).toBe(204);
    expect((await call("GET", `/v1/me/calendar-events?${window}`, "viewer")).json().events).toEqual([]);
    expect((await call("GET", "/v1/me/calendar-invites", "viewer")).json().invites[0].from.name).toBe("Olive Owner");
    expect((await call("POST", "/v1/me/calendar-invites/owner/accept", "viewer")).statusCode).toBe(204);

    const res = await call("GET", `/v1/me/calendar-events?${window}`, "viewer");
    expect(res.statusCode).toBe(200);
    const events = res.json().events;
    expect(events.map((e: { title: string }) => e.title)).toEqual(["Track", "Gym"]);
    expect(events[1].startsAt).toBe("2026-11-16T15:00:00.000Z");
    expect(JSON.stringify(res.json())).not.toContain("private");
    const calendars = (await call("GET", "/v1/me/calendars", "viewer")).json().calendars;
    expect(calendars.map((c: { id: string; role: string }) => [c.id, c.role])).toEqual([
      ["viewer", "owner"],
      ["owner", "view"],
    ]);
  });

  it("serves the subscription feed from its link", async () => {
    const { url } = (await call("POST", "/v1/me/calendar-feed", "viewer")).json();
    const res = await call("GET", new URL(url).pathname, null);
    expect(res.statusCode).toBe(200);
    expect(res.body).toContain("SUMMARY:Gym\r\n");
    expect(res.body).toContain("DTSTART:20261116T150000Z\r\n");
    expect(res.body).not.toContain("private");
  });
});
