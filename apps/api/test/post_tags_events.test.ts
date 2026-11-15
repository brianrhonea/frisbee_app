// Players' posts tagged with a tournament and posts sharing an event,
// following firestore.rules' posts rule: validUserPost's tournamentKey
// ('tournament_.+', at most 300) and tournamentName (at most 100) conjuncts,
// the 'event' kind with validSharedEvent, sharesOwnTeamEvent and notMuted.
import { beforeEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { FakeMediaStorage, FakeStore, FakeTeamRepository, FakeUsers, FakeVerifier } from "./fakes.js";

const now = Date.UTC(2026, 10, 14, 12);
let store: FakeStore;
let call: (method: "POST" | "PATCH", url: string, body: object, uid?: string) => Promise<{ status: number; json: () => any }>;

beforeEach(() => {
  store = new FakeStore(() => now);
  const users = new FakeUsers();
  users.records.set("me", { name: "Pat", email: "p@x.test" });
  const app = buildApp({ verifier: new FakeVerifier(), users, teams: new FakeTeamRepository(), store, media: new FakeMediaStorage(), now: () => now });
  call = async (method, url, body, uid = "me") => {
    const res = await app.inject({ method, url, payload: body, headers: { authorization: `Bearer token:${uid}` } });
    return { status: res.statusCode, json: () => res.json() };
  };
  store.put("teams/t1", { name: "Haze", kind: "team", memberIds: ["me", "pl"], members: { me: "player", pl: "player" }, memberPerms: { me: ["manageEvents"] } });
  store.put("teams/t1/events/e1", { title: "Practice", type: "practice", startsAt: new Date(now + 86_400_000), endsAt: new Date(now + 90_000_000), location: "Field 2", notes: "secret" });
  store.put("users/me/events/m1", { title: "Track", type: "workout", startsAt: new Date(now + 3_600_000) });
});

const tag = { key: "tournament_host_t1", name: "Spring Fling" };

describe("tournament tags (validUserPost)", () => {
  it("stores the key and name on a new post", async () => {
    const res = await call("POST", "/v1/posts", { body: "We're here", tournament: tag });
    expect(res.status).toBe(201);
    expect(store.doc(`posts/${res.json().id}`)).toMatchObject({ kind: "text", tournamentKey: "tournament_host_t1", tournamentName: "Spring Fling" });
  });

  it("leaves both null without a tag (tournamentKey == null)", async () => {
    const res = await call("POST", "/v1/posts", { body: "hi" });
    expect(store.doc(`posts/${res.json().id}`)).toMatchObject({ tournamentKey: null, tournamentName: null });
  });

  it("refuses a key that isn't a tournament's (matches('tournament_.+'))", async () => {
    expect((await call("POST", "/v1/posts", { body: "x", tournament: { key: "team_t1", name: "" } })).status).toBe(400);
    expect((await call("POST", "/v1/posts", { body: "x", tournament: { key: "tournament_", name: "" } })).status).toBe(400);
  });

  it("refuses a key over 300 characters (validString(…, 300))", async () => {
    expect((await call("POST", "/v1/posts", { body: "x", tournament: { key: `tournament_${"a".repeat(290)}`, name: "" } })).status).toBe(400);
  });

  it("refuses a name over 100 characters (validString(tournamentName, 100))", async () => {
    expect((await call("POST", "/v1/posts", { body: "x", tournament: { key: "tournament_a_b", name: "n".repeat(101) } })).status).toBe(400);
  });

  it("an edit keeps the tag when absent, changes it, and clears it with null", async () => {
    const id = (await call("POST", "/v1/posts", { body: "x", tournament: tag })).json().id;
    await call("PATCH", `/v1/posts/${id}`, { body: "y" });
    expect(store.doc(`posts/${id}`)?.tournamentKey).toBe("tournament_host_t1");
    await call("PATCH", `/v1/posts/${id}`, { body: "y", tournament: { key: "tournament_h_t2", name: "" } });
    expect(store.doc(`posts/${id}`)).toMatchObject({ tournamentKey: "tournament_h_t2", tournamentName: null });
    await call("PATCH", `/v1/posts/${id}`, { body: "y", tournament: null });
    expect(store.doc(`posts/${id}`)).toMatchObject({ tournamentKey: null, tournamentName: null });
  });
});

describe("event posts (validSharedEvent, sharesOwnTeamEvent)", () => {
  it("copies a team event's details from the stored event, never its notes", async () => {
    const res = await call("POST", "/v1/posts", { body: "Come along", shareEvent: { eventId: "e1", teamId: "t1" } });
    expect(res.status).toBe(201);
    const post = store.doc(`posts/${res.json().id}`)!;
    expect(post.kind).toBe("event");
    expect(post.workout).toBeNull();
    expect(post.event).toEqual({
      eventId: "e1",
      title: "Practice",
      type: "practice",
      startsAt: new Date(now + 86_400_000),
      endsAt: new Date(now + 90_000_000),
      location: "Field 2",
      teamId: "t1",
      teamName: "Haze",
    });
  });

  it("shares a team's event only for those who run its schedule (can(…, 'manageEvents'))", async () => {
    expect((await call("POST", "/v1/posts", { body: "", shareEvent: { eventId: "e1", teamId: "t1" } }, "pl")).status).toBe(403);
    expect((await call("POST", "/v1/posts", { body: "", shareEvent: { eventId: "e1", teamId: "nope" } })).status).toBe(403);
  });

  it("shares an event from the caller's own schedule (teamId null), with no words needed", async () => {
    const res = await call("POST", "/v1/posts", { body: "", shareEvent: { eventId: "m1", teamId: null } });
    expect(res.status).toBe(201);
    const ev = store.doc(`posts/${res.json().id}`)!.event as Record<string, unknown>;
    expect(ev).toEqual({ eventId: "m1", title: "Track", type: "workout", startsAt: new Date(now + 3_600_000) });
    expect((await call("POST", "/v1/posts", { body: "", shareEvent: { eventId: "m1", teamId: null } }, "pl")).status).toBe(404);
  });

  it("needs a stored event with a title and start (validSharedEvent's title and startsAt)", async () => {
    store.put("users/me/events/bad", { title: "", startsAt: new Date(now) });
    expect((await call("POST", "/v1/posts", { body: "", shareEvent: { eventId: "bad", teamId: null } })).status).toBe(412);
    expect((await call("POST", "/v1/posts", { body: "", shareEvent: { eventId: "gone", teamId: null } })).status).toBe(404);
  });

  it("needs a start time, files an unknown type as other, and clips location and team name (validSharedEvent)", async () => {
    store.put("users/me/events/nostart", { title: "When?" });
    expect((await call("POST", "/v1/posts", { body: "", shareEvent: { eventId: "nostart", teamId: null } })).status).toBe(412);
    store.put("teams/t1", { ...store.doc("teams/t1")!, name: "N".repeat(150) });
    store.put("teams/t1/events/odd", { title: "Odd", type: "party", startsAt: new Date(now), location: "L".repeat(250) });
    const res = await call("POST", "/v1/posts", { body: "", shareEvent: { eventId: "odd", teamId: "t1" } });
    const ev = store.doc(`posts/${res.json().id}`)!.event as Record<string, string>;
    expect(ev.type).toBe("other");
    expect(ev.location).toHaveLength(200);
    expect(ev.teamName).toHaveLength(100);
  });

  it("is an event post only: no workout, photos or links with it (kind == 'event' && workout == null)", async () => {
    expect((await call("POST", "/v1/posts", { body: "", shareEvent: { eventId: "m1", teamId: null }, links: ["https://x.test"] })).status).toBe(400);
    expect((await call("POST", "/v1/posts", { body: "", shareEvent: { eventId: "m1", teamId: null }, workout: { activity: "run", durationMinutes: 10 } })).status).toBe(400);
  });

  it("isn't allowed while muted (notMuted)", async () => {
    store.put("limits/me", { mutedUntil: new Date(now + 60_000) });
    expect((await call("POST", "/v1/posts", { body: "", shareEvent: { eventId: "m1", teamId: null } })).status).toBe(429);
  });
});

// Calendar events (the app shares them from its editor with no teamId):
// validSharedEvent's shape, plus the calendar API's own access check, since
// clients can never read calendars/{id}/events and the copy mustn't leak them.
describe("calendar event posts (validSharedEvent, the calendar's editors)", () => {
  const share = (eventId: string, calendarId: string | null, uid = "me", teamId: string | null = null) =>
    call("POST", "/v1/posts", { body: "", shareEvent: { eventId, teamId, calendarId } }, uid);

  beforeEach(() => {
    store.put("calendars/c1", {
      ownerId: "own",
      name: "Club",
      members: { own: "owner", me: "edit", vw: "view" },
      memberIds: ["own", "me", "vw"],
      pending: { inv: "edit" },
    });
    store.put("calendars/c1/events/ce1", { title: "Board meeting", type: "other", startsAt: new Date(now + 7_200_000), location: "Clubhouse", notes: "private" });
    store.put("calendars/own", { ownerId: "own", name: "My calendar", members: { own: "owner", me: "edit", vw: "view" }, memberIds: ["own", "me", "vw"] });
    store.put("users/own/events/oe1", { title: "Own's practice", type: "practice", startsAt: new Date(now + 3_600_000) });
  });

  it("copies an editor's calendar event from the stored event, without notes or a team (validSharedEvent's keys)", async () => {
    const res = await share("ce1", "c1");
    expect(res.status).toBe(201);
    const post = store.doc(`posts/${res.json().id}`)!;
    expect(post.kind).toBe("event");
    expect(post.event).toEqual({ eventId: "ce1", title: "Board meeting", type: "other", startsAt: new Date(now + 7_200_000), location: "Clubhouse" });
  });

  it("the owner shares too", async () => {
    expect((await share("ce1", "c1", "own")).status).toBe(201);
  });

  it("refuses someone who can only view the calendar (canEdit(role))", async () => {
    expect((await share("ce1", "c1", "vw")).status).toBe(403);
  });

  it("refuses someone not on it, as not found (members[uid])", async () => {
    expect((await share("ce1", "c1", "pl")).status).toBe(404);
  });

  it("refuses an invitee who hasn't accepted (pending isn't members)", async () => {
    expect((await share("ce1", "c1", "inv")).status).toBe(404);
  });

  it("refuses a calendar that doesn't exist", async () => {
    expect((await share("ce1", "nope")).status).toBe(404);
  });

  it("needs the event on that calendar", async () => {
    expect((await share("gone", "c1")).status).toBe(404);
    // Another calendar's event isn't found through this one.
    expect((await share("m1", "c1")).status).toBe(404);
  });

  it("reads the caller's own uid as My calendar (users/{uid}/events)", async () => {
    const res = await share("m1", "me");
    expect(res.status).toBe(201);
    expect(store.doc(`posts/${res.json().id}`)!.event).toEqual({ eventId: "m1", title: "Track", type: "workout", startsAt: new Date(now + 3_600_000) });
  });

  it("reads someone else's My calendar, shared with the caller to edit, from their users/{uid}/events", async () => {
    const res = await share("oe1", "own");
    expect(res.status).toBe(201);
    expect((store.doc(`posts/${res.json().id}`)!.event as Record<string, unknown>).title).toBe("Own's practice");
    expect((await share("oe1", "own", "vw")).status).toBe(403);
    expect((await share("oe1", "own", "pl")).status).toBe(404);
  });

  it("takes a team or a calendar, not both", async () => {
    expect((await share("e1", "c1", "me", "t1")).status).toBe(400);
  });

  it("needs a title and a start (validSharedEvent's title and startsAt)", async () => {
    store.put("calendars/c1/events/notitle", { title: " ", startsAt: new Date(now) });
    store.put("calendars/c1/events/nostart", { title: "When?" });
    expect((await share("notitle", "c1")).status).toBe(412);
    expect((await share("nostart", "c1")).status).toBe(412);
  });

  it("files an unknown type as other and clips the location (e.type in [...], validString(location, 200))", async () => {
    store.put("calendars/c1/events/odd", { title: "Odd", type: "party", startsAt: new Date(now), location: "L".repeat(250) });
    const res = await share("odd", "c1");
    const ev = store.doc(`posts/${res.json().id}`)!.event as Record<string, string>;
    expect(ev.type).toBe("other");
    expect(ev.location).toHaveLength(200);
  });

  it("isn't allowed while muted (notMuted)", async () => {
    store.put("limits/me", { mutedUntil: new Date(now + 60_000) });
    expect((await share("ce1", "c1")).status).toBe(429);
  });
});
