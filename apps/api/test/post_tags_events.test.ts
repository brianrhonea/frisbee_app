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

  it("is an event post only: no workout, photos or links with it (kind == 'event' && workout == null)", async () => {
    expect((await call("POST", "/v1/posts", { body: "", shareEvent: { eventId: "m1", teamId: null }, links: ["https://x.test"] })).status).toBe(400);
    expect((await call("POST", "/v1/posts", { body: "", shareEvent: { eventId: "m1", teamId: null }, workout: { activity: "run", durationMinutes: 10 } })).status).toBe(400);
  });

  it("isn't allowed while muted (notMuted)", async () => {
    store.put("limits/me", { mutedUntil: new Date(now + 60_000) });
    expect((await call("POST", "/v1/posts", { body: "", shareEvent: { eventId: "m1", teamId: null } })).status).toBe(429);
  });
});
