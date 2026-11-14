// Calendars (CalendarService) against FakeStore: invites that show nothing
// until accepted, Can view / Can edit, events on any calendar the caller may
// change, and the subscription feed (docs/requirements.md D4). Viewers see
// title, type, time and place, never notes. Events on "My calendar" keep the
// fields firestore.rules' validMine allows, since the app writes them too.
import { beforeEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import type { BrowseRepository } from "../src/browse/repository.js";
import type { CalendarRepository } from "../src/calendar/repository.js";
import type { RateLimiter } from "../src/limits/limiter.js";
import type { Data } from "../src/store.js";
import { FakeStore, FakeTeamRepository, FakeUsers, FakeVerifier } from "./fakes.js";

const now = Date.UTC(2026, 10, 13, 12);

const isoOf = (d: Data): Data =>
  Object.fromEntries(Object.entries(d).map(([k, v]) => [k, v instanceof Date ? v.toISOString() : v]));

/** The queries, answered from FakeStore's documents. */
class FakeCalendar implements CalendarRepository {
  constructor(private readonly store: FakeStore) {}
  private calendars() {
    return [...this.store.docs.entries()]
      .filter(([path]) => /^calendars\/[^/]+$/.test(path))
      .map(([path, d]) => ({ id: path.slice("calendars/".length), data: isoOf(d) }));
  }
  async calendarsOf(uid: string, limit: number) {
    return this.calendars()
      .filter((c) => Array.isArray(c.data.memberIds) && c.data.memberIds.includes(uid))
      .slice(0, limit);
  }
  async ownedBy(uid: string, limit: number) {
    return this.calendars().filter((c) => c.data.ownerId === uid).slice(0, limit);
  }
  async eventsBetween(collection: string, from: number, to: number, limit: number) {
    const prefix = `${collection}/`;
    return [...this.store.docs.entries()]
      .filter(([path]) => path.startsWith(prefix) && !path.slice(prefix.length).includes("/"))
      .map(([path, d]) => ({ id: path.slice(prefix.length), data: d }))
      .filter(({ data }) => {
        const t = (data.startsAt as Date).getTime();
        return t >= from && t < to;
      })
      .sort((a, b) => (a.data.startsAt as Date).getTime() - (b.data.startsAt as Date).getTime())
      .slice(0, limit)
      .map(({ id, data }) => ({ id, data: isoOf(data) }));
  }
}

class FakeLimiter implements RateLimiter {
  allow = true;
  keys: string[] = [];
  async admit(key: string) {
    this.keys.push(key);
    return this.allow;
  }
}

function setup() {
  const store = new FakeStore(() => now);
  const limiter = new FakeLimiter();
  const app = buildApp({
    verifier: new FakeVerifier(),
    users: new FakeUsers(),
    teams: new FakeTeamRepository(),
    store,
    calendar: new FakeCalendar(store),
    browse: { repo: {} as BrowseRepository, limiter, imageUrl: (p) => p },
    publicUrl: "https://api.stall10.test",
    now: () => now,
  });
  const call = (method: "GET" | "POST" | "PATCH" | "DELETE", url: string, body?: object, uid: string | null = "me") =>
    app.inject({
      method,
      url,
      ...(body && { payload: body }),
      headers: uid ? { authorization: `Bearer token:${uid}` } : {},
    });
  return { store, limiter, call, app };
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

async function newCalendar(name = "Training", uid = "me"): Promise<string> {
  const res = await s.call("POST", "/v1/me/calendars", { name, color: "blue" }, uid);
  expect(res.statusCode).toBe(201);
  return res.json().id;
}

async function invite(id: string, who: string, role: "view" | "edit" = "view") {
  return s.call("POST", `/v1/calendars/${id}/invites`, { uid: who, role });
}

describe("calendars", () => {
  it("starts everyone with My calendar, owned by them", async () => {
    const res = await s.call("GET", "/v1/me/calendars");
    expect(res.statusCode).toBe(200);
    expect(res.headers["cache-control"]).toBe("private, no-store");
    expect(res.json().calendars).toEqual([
      {
        id: "me",
        name: "My calendar",
        color: "green",
        owner: { uid: "me", name: "Mia Member", username: "mia", photoUrl: null },
        role: "owner",
        isDefault: true,
        members: [{ uid: "me", name: "Mia Member", username: "mia", photoUrl: null, role: "owner" }],
        pending: [],
      },
    ]);
    expect(s.store.doc("calendars/me")).toMatchObject({ ownerId: "me", memberIds: ["me"] });
    expect((await s.call("GET", "/v1/me/calendars", undefined, null)).statusCode).toBe(401);
  });

  it("makes, renames and deletes more, but never My calendar", async () => {
    const id = await newCalendar();
    expect((await s.call("PATCH", `/v1/calendars/${id}`, { name: "Track", color: "red" })).statusCode).toBe(204);
    expect(s.store.doc(`calendars/${id}`)).toMatchObject({ name: "Track", color: "red" });
    expect((await s.call("PATCH", `/v1/calendars/${id}`, { color: "plaid" })).statusCode).toBe(400);
    expect((await s.call("POST", "/v1/me/calendars", { name: " " })).statusCode).toBe(400);
    expect((await s.call("DELETE", "/v1/calendars/me")).statusCode).toBe(412);

    await s.call("POST", `/v1/calendars/${id}/events`, event);
    await invite(id, "pat");
    expect((await s.call("DELETE", `/v1/calendars/${id}`)).statusCode).toBe(204);
    expect(s.store.doc(`calendars/${id}`)).toBeUndefined();
    expect(s.store.doc(`users/pat/calendarInvites/${id}`)).toBeUndefined();
    expect([...s.store.docs.keys()].some((k) => k.startsWith(`calendars/${id}/`))).toBe(false);
  });

  it("caps how many one person owns", async () => {
    for (let i = 0; i < 19; i++) await newCalendar(`C${i}`);
    expect((await s.call("POST", "/v1/me/calendars", { name: "One too many" })).statusCode).toBe(412);
  });

  it("hides other people's calendars, and lets only the owner change them", async () => {
    const id = await newCalendar();
    expect((await s.call("PATCH", `/v1/calendars/${id}`, { name: "Mine now" }, "pat")).statusCode).toBe(404);
    expect((await s.call("DELETE", `/v1/calendars/${id}`, undefined, "pat")).statusCode).toBe(404);
    await invite(id, "pat", "edit");
    await s.call("POST", `/v1/me/calendar-invites/${id}/accept`, undefined, "pat");
    expect((await s.call("PATCH", `/v1/calendars/${id}`, { name: "Mine now" }, "pat")).statusCode).toBe(403);
    expect((await s.call("POST", `/v1/calendars/${id}/invites`, { uid: "sam" }, "pat")).statusCode).toBe(403);
  });
});

describe("invites", () => {
  it("shows the calendar only after the invitee accepts", async () => {
    const id = await newCalendar();
    await s.call("POST", `/v1/calendars/${id}/events`, event);
    expect((await invite(id, "pat", "edit")).statusCode).toBe(204);
    expect(s.store.doc(`users/pat/calendarInvites/${id}`)).toMatchObject({
      calendarId: id,
      calendarName: "Training",
      role: "edit",
      fromId: "me",
    });

    // Invited isn't shared.
    expect((await s.call("GET", "/v1/me/calendars", undefined, "pat")).json().calendars.map((c: { id: string }) => c.id)).toEqual(["pat"]);
    expect((await s.call("GET", `/v1/me/calendar-events?${week}`, undefined, "pat")).json().events).toEqual([]);
    expect((await s.call("POST", `/v1/calendars/${id}/events`, event, "pat")).statusCode).toBe(404);

    const invites = (await s.call("GET", "/v1/me/calendar-invites", undefined, "pat")).json().invites;
    expect(invites).toEqual([
      {
        calendarId: id,
        calendarName: "Training",
        color: "blue",
        role: "edit",
        from: { uid: "me", name: "Mia Member", username: "mia", photoUrl: null },
        createdAt: new Date(now).toISOString(),
      },
    ]);
    const owner = (await s.call("GET", "/v1/me/calendars")).json().calendars.find((c: { id: string }) => c.id === id);
    expect(owner.pending).toEqual([{ uid: "pat", name: "Pat Player", username: "pat", photoUrl: "https://img/p.jpg", role: "edit" }]);

    expect((await s.call("POST", `/v1/me/calendar-invites/${id}/accept`, undefined, "pat")).statusCode).toBe(204);
    expect(s.store.doc(`users/pat/calendarInvites/${id}`)).toBeUndefined();
    expect(s.store.doc(`calendars/${id}`)).toMatchObject({ members: { me: "owner", pat: "edit" }, memberIds: ["me", "pat"], pending: {} });
    const shared = (await s.call("GET", "/v1/me/calendars", undefined, "pat")).json().calendars;
    expect(shared[1]).toEqual({
      id,
      name: "Training",
      color: "blue",
      owner: { uid: "me", name: "Mia Member", username: "mia", photoUrl: null },
      role: "edit",
      isDefault: false,
    });
    const events = (await s.call("GET", `/v1/me/calendar-events?${week}`, undefined, "pat")).json().events;
    expect(events).toMatchObject([{ calendarId: id, title: "Track session", notes: "Knee still sore — go easy" }]);
  });

  it("declines, withdraws, and refuses an invite that's gone", async () => {
    const id = await newCalendar();
    await invite(id, "pat");
    expect((await s.call("POST", `/v1/me/calendar-invites/${id}/decline`, undefined, "pat")).statusCode).toBe(204);
    expect(s.store.doc(`calendars/${id}`)!.pending).toEqual({});
    expect((await s.call("POST", `/v1/me/calendar-invites/${id}/accept`, undefined, "pat")).statusCode).toBe(404);

    await invite(id, "sam");
    expect((await s.call("DELETE", `/v1/calendars/${id}/invites/sam`)).statusCode).toBe(204);
    expect(s.store.doc(`users/sam/calendarInvites/${id}`)).toBeUndefined();
    expect((await s.call("POST", `/v1/me/calendar-invites/${id}/accept`, undefined, "sam")).statusCode).toBe(404);
    expect(s.store.doc(`calendars/${id}`)!.memberIds).toEqual(["me"]);
  });

  it("can't be accepted by someone else, or forged by writing an invite doc", async () => {
    const id = await newCalendar();
    await invite(id, "pat");
    expect((await s.call("POST", `/v1/me/calendar-invites/${id}/accept`, undefined, "sam")).statusCode).toBe(404);
    // An invite doc alone (no pending entry on the calendar) grants nothing.
    s.store.put(`users/sam/calendarInvites/${id}`, { calendarId: id, role: "edit" });
    expect((await s.call("GET", "/v1/me/calendar-invites", undefined, "sam")).json().invites).toEqual([]);
    expect((await s.call("POST", `/v1/me/calendar-invites/${id}/accept`, undefined, "sam")).statusCode).toBe(404);
    expect(s.store.doc(`calendars/${id}`)!.memberIds).toEqual(["me"]);
  });

  it("refuses the owner, strangers, members already on it, and too many people", async () => {
    const id = await newCalendar();
    expect((await invite(id, "me")).statusCode).toBe(400);
    expect((await invite(id, "ghost")).statusCode).toBe(404);
    expect((await s.call("POST", `/v1/calendars/${id}/invites`, { uid: "pat", role: "owner" })).statusCode).toBe(400);
    await invite(id, "pat");
    await s.call("POST", `/v1/me/calendar-invites/${id}/accept`, undefined, "pat");
    expect((await invite(id, "pat")).statusCode).toBe(409);

    const pending = Object.fromEntries(Array.from({ length: 48 }, (_, i) => [`u${i}`, "view"]));
    s.store.put(`calendars/${id}`, { ...s.store.doc(`calendars/${id}`)!, pending });
    expect((await invite(id, "sam")).statusCode).toBe(412);
  });

  it("is refused while the owner is muted", async () => {
    const id = await newCalendar();
    s.store.put("limits/me", { mutedUntil: new Date(now + 60_000) });
    expect((await invite(id, "pat")).statusCode).toBe(429);
  });
});

describe("members", () => {
  async function shared(role: "view" | "edit") {
    const id = await newCalendar();
    await invite(id, "pat", role);
    await s.call("POST", `/v1/me/calendar-invites/${id}/accept`, undefined, "pat");
    return id;
  }

  it("lets viewers see events without notes, and not change them", async () => {
    const id = await shared("view");
    const { id: eventId } = (await s.call("POST", `/v1/calendars/${id}/events`, event)).json();
    const res = await s.call("GET", `/v1/me/calendar-events?${week}`, undefined, "pat");
    expect(res.json().events).toEqual([
      {
        id: eventId,
        calendarId: id,
        title: "Track session",
        type: "workout",
        startsAt: event.startsAt,
        endsAt: event.endsAt,
        location: "High school track",
      },
    ]);
    expect(JSON.stringify(res.json())).not.toContain("Knee");
    expect((await s.call("POST", `/v1/calendars/${id}/events`, event, "pat")).statusCode).toBe(403);
    expect((await s.call("PATCH", `/v1/calendars/${id}/events/${eventId}`, event, "pat")).statusCode).toBe(403);
    expect((await s.call("DELETE", `/v1/calendars/${id}/events/${eventId}`, undefined, "pat")).statusCode).toBe(403);
  });

  it("lets editors add, change and delete events", async () => {
    const id = await shared("edit");
    const res = await s.call("POST", `/v1/calendars/${id}/events`, event, "pat");
    expect(res.statusCode).toBe(201);
    const eventId = res.json().id;
    const one = await s.call("GET", `/v1/calendars/${id}/events/${eventId}`, undefined, "pat");
    expect(one.json()).toMatchObject({ id: eventId, calendarId: id, title: "Track session", notes: "Knee still sore — go easy" });
    expect((await s.call("GET", `/v1/calendars/${id}/events/${eventId}`, undefined, "sam")).statusCode).toBe(404);
    expect((await s.call("GET", `/v1/calendars/${id}/events/nope`, undefined, "pat")).statusCode).toBe(404);
    expect((await s.call("PATCH", `/v1/calendars/${id}/events/${eventId}`, { ...event, title: "Tempo" }, "pat")).statusCode).toBe(204);
    expect(s.store.doc(`calendars/${id}/events/${eventId}`)).toMatchObject({ title: "Tempo" });
    expect((await s.call("DELETE", `/v1/calendars/${id}/events/${eventId}`, undefined, "pat")).statusCode).toBe(204);
    expect(s.store.doc(`calendars/${id}/events/${eventId}`)).toBeUndefined();
  });

  it("changes roles, removes people, and lets members leave", async () => {
    const id = await shared("view");
    expect((await s.call("PATCH", `/v1/calendars/${id}/members/pat`, { role: "edit" })).statusCode).toBe(204);
    expect(s.store.doc(`calendars/${id}`)!.members).toEqual({ me: "owner", pat: "edit" });
    expect((await s.call("PATCH", `/v1/calendars/${id}/members/me`, { role: "view" })).statusCode).toBe(400);
    expect((await s.call("PATCH", `/v1/calendars/${id}/members/sam`, { role: "view" })).statusCode).toBe(404);

    expect((await s.call("DELETE", `/v1/calendars/${id}/members/me`, undefined, "pat")).statusCode).toBe(403);
    expect((await s.call("DELETE", `/v1/calendars/${id}/members/pat`, undefined, "pat")).statusCode).toBe(204);
    expect(s.store.doc(`calendars/${id}`)).toMatchObject({ members: { me: "owner" }, memberIds: ["me"] });
    expect((await s.call("GET", `/v1/me/calendar-events?${week}`, undefined, "pat")).json().events).toEqual([]);
    expect((await s.call("DELETE", `/v1/calendars/${id}/members/me`)).statusCode).toBe(400);
  });
});

describe("events", () => {
  it("saves My calendar's events where the app does, with validMine's fields only", async () => {
    const res = await s.call("POST", "/v1/calendars/me/events", event);
    expect(res.statusCode).toBe(201);
    const saved = s.store.doc(`users/me/events/${res.json().id}`)!;
    expect(Object.keys(saved).sort()).toEqual(["createdAt", "endsAt", "location", "notes", "poll", "startsAt", "title", "type", "updatedAt"]);
    expect(saved).toMatchObject({ title: "Track session", type: "workout", poll: null });
    expect(saved.startsAt).toEqual(new Date(event.startsAt));
  });

  it("lets an editor of My calendar write into the owner's events", async () => {
    await s.call("GET", "/v1/me/calendars");
    await invite("me", "pat", "edit");
    await s.call("POST", "/v1/me/calendar-invites/me/accept", undefined, "pat");
    const res = await s.call("POST", "/v1/calendars/me/events", event, "pat");
    expect(res.statusCode).toBe(201);
    expect(s.store.doc(`users/me/events/${res.json().id}`)).toBeDefined();
    expect([...s.store.docs.keys()].some((k) => k.startsWith("users/pat/events/"))).toBe(false);
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
    for (const b of bad) {
      expect((await s.call("POST", "/v1/calendars/me/events", b)).statusCode, JSON.stringify(b).slice(0, 80)).toBe(400);
    }
    expect((await s.call("POST", "/v1/calendars/me/events", event, null)).statusCode).toBe(401);
    expect((await s.call("POST", "/v1/calendars/me/events", event, "pat")).statusCode).toBe(404);
  });

  it("lists every calendar's events in a bounded window, soonest first", async () => {
    const id = await newCalendar();
    await s.call("POST", `/v1/calendars/${id}/events`, { ...event, title: "Later", startsAt: "2026-11-16T17:00:00.000Z", endsAt: null });
    await s.call("POST", "/v1/calendars/me/events", event);
    await s.call("POST", "/v1/calendars/me/events", { ...event, title: "Next month", startsAt: "2026-12-20T17:00:00.000Z", endsAt: null });
    const res = await s.call("GET", `/v1/me/calendar-events?${week}`);
    expect(res.json().events.map((e: { title: string; calendarId: string }) => [e.title, e.calendarId])).toEqual([
      ["Track session", "me"],
      ["Later", id],
    ]);
    expect((await s.call("GET", "/v1/me/calendar-events")).statusCode).toBe(400);
    expect((await s.call("GET", "/v1/me/calendar-events?from=2026-01-01T00:00:00Z&to=2026-12-31T00:00:00Z")).statusCode).toBe(400);
  });
});

describe("subscription feed", () => {
  it("makes a private link, serves iCalendar from it, and resets it", async () => {
    expect((await s.call("GET", "/v1/me/calendar-feed")).json()).toEqual({ url: null, webcal: null });
    const made = (await s.call("POST", "/v1/me/calendar-feed")).json();
    expect(made.url).toMatch(/^https:\/\/api\.stall10\.test\/v1\/ical\/[A-Za-z0-9_-]{32}\.ics$/);
    expect(made.webcal).toBe(made.url.replace("https://", "webcal://"));
    expect((await s.call("GET", "/v1/me/calendar-feed")).json()).toEqual(made);

    const id = await newCalendar();
    await invite(id, "pat");
    await s.call("POST", "/v1/calendars/me/events", event);
    const path = new URL(made.url).pathname;
    const res = await s.call("GET", path, undefined, null);
    expect(res.statusCode).toBe(200);
    expect(res.headers["content-type"]).toBe("text/calendar; charset=utf-8");
    expect(res.headers["cache-control"]).toBe("private, no-store");
    expect(res.body).toContain("BEGIN:VCALENDAR\r\n");
    expect(res.body).toContain("SUMMARY:Track session\r\n");
    expect(res.body).toContain("UID:me-");
    expect(res.body).toContain("DESCRIPTION:Knee still sore — go easy\r\n");
    expect(s.limiter.keys).toHaveLength(1);
    expect(s.limiter.keys[0]).toMatch(/^ical_[0-9a-f]{32}$/);

    const again = (await s.call("POST", "/v1/me/calendar-feed")).json();
    expect(again.url).not.toBe(made.url);
    expect((await s.call("GET", path, undefined, null)).statusCode).toBe(404);
    expect((await s.call("GET", new URL(again.url).pathname, undefined, null)).statusCode).toBe(200);

    expect((await s.call("DELETE", "/v1/me/calendar-feed")).statusCode).toBe(204);
    expect((await s.call("GET", new URL(again.url).pathname, undefined, null)).statusCode).toBe(404);
    expect([...s.store.docs.keys()].some((k) => k.startsWith("calendarFeeds/"))).toBe(false);
  });

  it("follows membership at each fetch and keeps notes from viewers", async () => {
    const id = await newCalendar();
    await s.call("POST", `/v1/calendars/${id}/events`, event);
    await invite(id, "pat");
    const feed = new URL((await s.call("POST", "/v1/me/calendar-feed", undefined, "pat")).json().url).pathname;
    expect((await s.call("GET", feed, undefined, null)).body).not.toContain("Track session");
    await s.call("POST", `/v1/me/calendar-invites/${id}/accept`, undefined, "pat");
    const body = (await s.call("GET", feed, undefined, null)).body;
    expect(body).toContain("SUMMARY:Track session\r\n");
    expect(body).toContain("DESCRIPTION:Calendar: Training\r\n");
    expect(body).not.toContain("Knee");
    await s.call("DELETE", `/v1/calendars/${id}/members/pat`);
    expect((await s.call("GET", feed, undefined, null)).body).not.toContain("Track session");
  });

  it("turns away bad links and too many fetches", async () => {
    expect((await s.call("GET", "/v1/ical/short.ics", undefined, null)).statusCode).toBe(404);
    expect((await s.call("GET", `/v1/ical/${"a".repeat(32)}.ics`, undefined, null)).statusCode).toBe(404);
    const made = (await s.call("POST", "/v1/me/calendar-feed")).json();
    s.limiter.allow = false;
    expect((await s.call("GET", new URL(made.url).pathname, undefined, null)).statusCode).toBe(429);
  });
});
