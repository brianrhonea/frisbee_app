// Personal events and calendar sharing (CalendarService) against FakeStore,
// following firestore.rules' users/{uid}/events (validMine) and D4 in
// docs/requirements.md: viewers see title, type, time and place, never notes.
import { beforeEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import type { CalendarRepository } from "../src/calendar/repository.js";
import { FakeStore, FakeTeamRepository, FakeUsers, FakeVerifier } from "./fakes.js";

const now = Date.UTC(2026, 10, 13, 12);

/** The two queries, answered from FakeStore's documents. */
class FakeCalendar implements CalendarRepository {
  constructor(private readonly store: FakeStore) {}
  async sharersOf(uid: string) {
    return [...this.store.docs.entries()]
      .filter(([path, d]) => /^users\/[^/]+$/.test(path) && Array.isArray(d.calendarViewers) && d.calendarViewers.includes(uid))
      .map(([path]) => path.slice("users/".length));
  }
  async eventsBetween(owner: string, from: number, to: number, limit: number) {
    const prefix = `users/${owner}/events/`;
    return [...this.store.docs.entries()]
      .filter(([path]) => path.startsWith(prefix))
      .map(([path, d]) => ({ id: path.slice(prefix.length), data: d }))
      .filter(({ data }) => {
        const t = (data.startsAt as Date).getTime();
        return t >= from && t < to;
      })
      .sort((a, b) => (a.data.startsAt as Date).getTime() - (b.data.startsAt as Date).getTime())
      .slice(0, limit)
      .map(({ id, data }) => ({
        id,
        data: { ...data, startsAt: (data.startsAt as Date).toISOString(), endsAt: (data.endsAt as Date | null)?.toISOString() ?? null },
      }));
  }
}

function setup() {
  const store = new FakeStore(() => now);
  const app = buildApp({
    verifier: new FakeVerifier(),
    users: new FakeUsers(),
    teams: new FakeTeamRepository(),
    store,
    calendar: new FakeCalendar(store),
    now: () => now,
  });
  const call = (method: "GET" | "POST" | "PATCH" | "PUT" | "DELETE", url: string, body?: object, uid: string | null = "me") =>
    app.inject({
      method,
      url,
      ...(body && { payload: body }),
      headers: uid ? { authorization: `Bearer token:${uid}` } : {},
    });
  return { store, call };
}

const event = {
  title: " Track session ",
  type: "workout",
  startsAt: "2026-11-15T17:00:00.000Z",
  endsAt: "2026-11-15T18:00:00.000Z",
  location: "High school track",
  notes: "Knee still sore — go easy",
};
const week = "from=2026-11-13T00:00:00.000Z&to=2026-11-20T00:00:00.000Z";

let s: ReturnType<typeof setup>;
beforeEach(() => {
  s = setup();
  s.store.put("profiles/me", { name: "Mia Member", username: "mia" });
  s.store.put("profiles/pat", { name: "Pat Player", username: "pat", photoUrl: "https://img/p.jpg" });
  s.store.put("profiles/sam", { name: "Sam Sub" });
});

describe("personal events", () => {
  it("saves one as the app does: real dates, poll null, the caller's own", async () => {
    const res = await s.call("POST", "/v1/me/events", event);
    expect(res.statusCode).toBe(201);
    const saved = s.store.doc(`users/me/events/${res.json().id}`)!;
    expect(saved).toMatchObject({
      title: "Track session",
      type: "workout",
      location: "High school track",
      notes: "Knee still sore — go easy",
      poll: null,
    });
    expect(saved.startsAt).toEqual(new Date(event.startsAt));
    expect(saved.endsAt).toEqual(new Date(event.endsAt));
    expect(saved.createdAt).toEqual(new Date(now));
  });

  it("fills location and notes, and ends null, when left out", async () => {
    const res = await s.call("POST", "/v1/me/events", { title: "Pickup", startsAt: event.startsAt });
    expect(s.store.doc(`users/me/events/${res.json().id}`)).toMatchObject({
      type: "other",
      endsAt: null,
      location: "",
      notes: "",
    });
  });

  it("checks what validMine checks", async () => {
    const bad = [
      { ...event, title: "  " },
      { ...event, title: "x".repeat(101) },
      { ...event, type: "meeting" },
      { ...event, startsAt: "tomorrow" },
      { ...event, endsAt: "2026-11-15T16:00:00.000Z" },
      { ...event, location: "x".repeat(201) },
      { ...event, notes: "x".repeat(5001) },
      { ...event, poll: { question: "?", options: ["a", "b"], multiple: false } },
    ];
    for (const b of bad) expect((await s.call("POST", "/v1/me/events", b)).statusCode, JSON.stringify(b).slice(0, 80)).toBe(400);
    expect((await s.call("POST", "/v1/me/events", event, null)).statusCode).toBe(401);
  });

  it("edits and deletes only the caller's own", async () => {
    const { id } = (await s.call("POST", "/v1/me/events", event)).json();
    expect((await s.call("PATCH", `/v1/me/events/${id}`, { ...event, title: "Tempo run" })).statusCode).toBe(204);
    expect(s.store.doc(`users/me/events/${id}`)).toMatchObject({ title: "Tempo run" });
    // Pat can't name Mia's event: their own path has no such id.
    expect((await s.call("PATCH", `/v1/me/events/${id}`, event, "pat")).statusCode).toBe(404);
    expect((await s.call("DELETE", `/v1/me/events/${id}`, undefined, "pat")).statusCode).toBe(204);
    expect(s.store.doc(`users/me/events/${id}`)).toBeDefined();
    expect((await s.call("DELETE", `/v1/me/events/${id}`)).statusCode).toBe(204);
    expect(s.store.doc(`users/me/events/${id}`)).toBeUndefined();
  });
});

describe("calendar sharing", () => {
  it("sets and lists viewers, refusing themselves and people without a profile", async () => {
    const res = await s.call("PUT", "/v1/me/calendar/viewers", { viewers: ["pat", "sam", "pat"] });
    expect(res.statusCode).toBe(200);
    expect(res.json().viewers.map((v: { uid: string }) => v.uid)).toEqual(["pat", "sam"]);
    expect(s.store.doc("users/me")!.calendarViewers).toEqual(["pat", "sam"]);
    expect((await s.call("GET", "/v1/me/calendar/viewers")).json().viewers[0]).toEqual({
      uid: "pat",
      name: "Pat Player",
      username: "pat",
      photoUrl: "https://img/p.jpg",
    });
    expect((await s.call("PUT", "/v1/me/calendar/viewers", { viewers: ["me"] })).statusCode).toBe(400);
    expect((await s.call("PUT", "/v1/me/calendar/viewers", { viewers: ["ghost"] })).statusCode).toBe(400);
    expect(
      (await s.call("PUT", "/v1/me/calendar/viewers", { viewers: Array.from({ length: 51 }, (_, i) => `u${i}`) }))
        .statusCode,
    ).toBe(400);
  });

  it("shows viewers the shared events without notes", async () => {
    await s.call("POST", "/v1/me/events", event);
    await s.call("POST", "/v1/me/events", { ...event, title: "Next month", startsAt: "2026-12-20T17:00:00.000Z", endsAt: null });
    await s.call("PUT", "/v1/me/calendar/viewers", { viewers: ["pat"] });
    const res = await s.call("GET", `/v1/me/calendar/shared?${week}`, undefined, "pat");
    expect(res.statusCode).toBe(200);
    expect(res.headers["cache-control"]).toBe("private, no-store");
    const { calendars } = res.json();
    expect(calendars).toHaveLength(1);
    expect(calendars[0].owner).toMatchObject({ uid: "me", name: "Mia Member" });
    expect(calendars[0].events).toEqual([
      {
        id: expect.any(String),
        title: "Track session",
        type: "workout",
        startsAt: event.startsAt,
        endsAt: event.endsAt,
        location: "High school track",
      },
    ]);
    expect(JSON.stringify(res.json())).not.toContain("Knee");
  });

  it("shows nothing to people not on the list, and stops when they're taken off", async () => {
    await s.call("POST", "/v1/me/events", event);
    await s.call("PUT", "/v1/me/calendar/viewers", { viewers: ["pat"] });
    expect((await s.call("GET", `/v1/me/calendar/shared?${week}`, undefined, "sam")).json().calendars).toEqual([]);
    await s.call("PUT", "/v1/me/calendar/viewers", { viewers: [] });
    expect((await s.call("GET", `/v1/me/calendar/shared?${week}`, undefined, "pat")).json().calendars).toEqual([]);
  });

  it("goes by the owner's list, not by who asks", async () => {
    // Sam lists Mia on Sam's own doc; that shares Sam's calendar, not Mia's.
    await s.call("POST", "/v1/me/events", event);
    await s.call("PUT", "/v1/me/calendar/viewers", { viewers: ["me"] }, "sam");
    const res = await s.call("GET", `/v1/me/calendar/shared?${week}`, undefined, "sam");
    expect(res.json().calendars).toEqual([]);
  });

  it("needs a bounded window", async () => {
    expect((await s.call("GET", "/v1/me/calendar/shared", undefined, "pat")).statusCode).toBe(400);
    expect(
      (await s.call("GET", "/v1/me/calendar/shared?from=2026-11-20T00:00:00Z&to=2026-11-13T00:00:00Z", undefined, "pat"))
        .statusCode,
    ).toBe(400);
    expect(
      (await s.call("GET", "/v1/me/calendar/shared?from=2026-01-01T00:00:00Z&to=2026-12-31T00:00:00Z", undefined, "pat"))
        .statusCode,
    ).toBe(400);
    expect((await s.call("GET", `/v1/me/calendar/shared?${week}`, undefined, null)).statusCode).toBe(401);
  });
});
