// Phase-1 writes contract (docs/specifications/contracts/phase1-writes.md)
// section 6, A1 to A3 and A5: a client-chosen `id` on the three create routes
// that lacked one (team event, group conversation, roster spot), a replay
// answering 409 already_exists, and the usual refusals on those routes
// (visitor, outsider, muted, suspended, incomplete account, bad body).
import { beforeEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { FakeMediaStorage, FakeStore, FakeTeamRepository, FakeUsers, FakeVerifier } from "./fakes.js";

const now = Date.UTC(2026, 10, 14, 12);

function setup() {
  const store = new FakeStore(() => now);
  const users = new FakeUsers();
  const app = buildApp({ verifier: new FakeVerifier(), users, teams: new FakeTeamRepository(), store, media: new FakeMediaStorage(), now: () => now });
  const call = (method: "POST" | "PUT" | "PATCH", url: string, body?: object, who: string | null = "coach") =>
    app.inject({ method, url, ...(body && { payload: body }), headers: who ? { authorization: `Bearer ${who.includes(":") ? who : `token:${who}`}` } : {} });
  return { store, users, call };
}

let s: ReturnType<typeof setup>;
beforeEach(() => {
  s = setup();
  for (const [uid, name] of [["coach", "Casey"], ["player", "Pat"], ["kim", "Kim"]]) {
    s.users.records.set(uid!, { name });
    s.store.put(`profiles/${uid}`, { name });
  }
  s.store.put("teams/t1", {
    name: "Haze",
    kind: "team",
    memberIds: ["coach", "player"],
    members: { coach: "coach", player: "player" },
    memberNames: { coach: "Casey", player: "Pat" },
  });
});

const event = { title: "Practice", startsAt: "2026-11-18T18:00:00Z" };

describe("A1: POST /v1/teams/:teamId/events takes an optional id", () => {
  const url = "/v1/teams/t1/events";

  it("uses the id it is given, and a replay is a 409 that changes nothing", async () => {
    const first = await s.call("POST", url, { ...event, id: "ev1abc" });
    expect(first.statusCode).toBe(201);
    expect(first.json()).toEqual({ id: "ev1abc" });
    expect(s.store.doc("teams/t1/events/ev1abc")).toMatchObject({ title: "Practice", createdBy: "coach" });
    const replay = await s.call("POST", url, { ...event, id: "ev1abc", title: "Changed" });
    expect(replay.statusCode).toBe(409);
    expect(replay.json().error.code).toBe("already_exists");
    expect(s.store.doc("teams/t1/events/ev1abc")?.title).toBe("Practice");
  });

  it("mints an id when none is given, as before", async () => {
    const res = await s.call("POST", url, event);
    expect(res.statusCode).toBe(201);
    expect(res.json().id).toMatch(/\w+/);
    expect(s.store.doc(`teams/t1/events/${res.json().id}`)).toBeDefined();
  });

  it("makes a series' events {id}_{index}, and a replayed series is a 409", async () => {
    const body = { ...event, id: "ser1", repeat: { freq: "weekly", until: "2026-12-09" }, timeZone: "America/Chicago" };
    const first = await s.call("POST", url, body);
    expect(first.statusCode).toBe(201);
    const ids = [...s.store.docs.keys()].filter((k) => k.startsWith("teams/t1/events/ser1_")).sort();
    expect(ids.length).toBeGreaterThan(1);
    expect(ids[0]).toBe("teams/t1/events/ser1_0");
    expect(first.json()).toEqual({ id: "ser1_0" });
    const before = s.store.docs.size;
    expect((await s.call("POST", url, body)).statusCode).toBe(409);
    expect(s.store.docs.size).toBe(before);
  });

  it("refuses a bad id, and an edit that names another event's id", async () => {
    for (const id of ["", "has space", "a/b", "x".repeat(41), "under_score"]) {
      expect((await s.call("POST", url, { ...event, id })).statusCode, id).toBe(400);
    }
    await s.call("POST", url, { ...event, id: "ev2" });
    expect((await s.call("PATCH", `${url}/ev2`, { ...event, id: "other" })).statusCode).toBe(400);
    expect((await s.call("PATCH", `${url}/ev2`, { ...event, id: "ev2", title: "Renamed" })).statusCode).toBe(200);
    expect(s.store.doc("teams/t1/events/ev2")?.title).toBe("Renamed");
  });

  it("is refused for visitors, outsiders, players, muted and suspended callers, and incomplete accounts", async () => {
    const body = { ...event, id: "evx" };
    expect((await s.call("POST", url, body, null)).statusCode).toBe(401);
    expect((await s.call("POST", url, body, "kim")).statusCode).toBe(403);
    expect((await s.call("POST", url, body, "player")).statusCode).toBe(403);
    s.store.put("limits/coach", { mutedUntil: new Date(now + 3600_000) });
    expect((await s.call("POST", url, body)).statusCode).toBe(429);
    s.store.put("limits/coach", { suspended: true });
    expect((await s.call("POST", url, body)).statusCode).toBe(403);
    s.store.put("limits/coach", {});
    for (const kind of ["unverified", "noage", "noterms", "oldterms"]) {
      const res = await s.call("POST", url, body, `${kind}:coach`);
      expect(res.statusCode, kind).toBe(403);
      expect(res.json().error.code, kind).toBe("account_incomplete");
    }
    expect([...s.store.docs.keys()].some((k) => k.endsWith("/events/evx"))).toBe(false);
  });
});

describe("A2: POST /v1/conversations/groups takes an optional id", () => {
  const url = "/v1/conversations/groups";

  it("uses a g- id it is given, and a replay is a 409 that adds no one", async () => {
    s.store.put("users/player/follows/user_coach", { at: new Date(now) });
    const first = await s.call("POST", url, { id: "g-abc123", name: "Crew", members: ["player"] });
    expect(first.statusCode).toBe(201);
    expect(first.json()).toMatchObject({ id: "g-abc123", notAdded: [] });
    expect(s.store.doc("conversations/g-abc123")).toMatchObject({ kind: "group", createdBy: "coach", participants: ["coach", "player"] });
    const replay = await s.call("POST", url, { id: "g-abc123", name: "Other", members: ["kim"] });
    expect(replay.statusCode).toBe(409);
    expect(replay.json().error.code).toBe("already_exists");
    expect(s.store.doc("conversations/g-abc123")).toMatchObject({ name: "Crew", participants: ["coach", "player"] });
  });

  it("mints one when absent, and refuses ids that aren't g- plus letters or digits", async () => {
    const res = await s.call("POST", url, { name: "Crew" });
    expect(res.statusCode).toBe(201);
    expect(res.json().id).toMatch(/^g-[A-Za-z0-9]+$/);
    for (const id of ["abc", "g-a_b", `g-${"x".repeat(41)}`, "coach_player"]) {
      expect((await s.call("POST", url, { id, name: "Crew" })).statusCode, id).toBe(400);
    }
  });

  it("is refused for visitors, muted, and incomplete accounts, and a bad body", async () => {
    expect((await s.call("POST", url, { id: "g-x", name: "Crew" }, null)).statusCode).toBe(401);
    expect((await s.call("POST", url, { id: "g-x", name: "" })).statusCode).toBe(400);
    s.store.put("limits/coach", { mutedUntil: new Date(now + 3600_000) });
    expect((await s.call("POST", url, { id: "g-x", name: "Crew" })).statusCode).toBe(429);
    s.store.put("limits/coach", {});
    expect((await s.call("POST", url, { id: "g-x", name: "Crew" }, "unverified:coach")).json().error.code).toBe("account_incomplete");
    expect(s.store.doc("conversations/g-x")).toBeUndefined();
  });
});

describe("A3: POST /v1/teams/:teamId/roster-players takes an optional id", () => {
  const url = "/v1/teams/t1/roster-players";

  it("uses the id it is given, and a replay is a 409 that changes nothing", async () => {
    const first = await s.call("POST", url, { id: "sp1", name: "Pat P", number: 7, position: "cutter" });
    expect(first.statusCode).toBe(201);
    expect(first.json()).toEqual({ id: "sp1" });
    expect(s.store.doc("teams/t1/roster/sp1")).toMatchObject({ name: "Pat P", number: 7, position: "cutter", userId: null });
    const replay = await s.call("POST", url, { id: "sp1", name: "Someone Else" });
    expect(replay.statusCode).toBe(409);
    expect(replay.json().error.code).toBe("already_exists");
    expect(s.store.doc("teams/t1/roster/sp1")?.name).toBe("Pat P");
  });

  it("refuses a bad id, and an edit that names another spot's id", async () => {
    for (const id of ["", "a b", "a/b", "x".repeat(41)]) expect((await s.call("POST", url, { id, name: "N" })).statusCode, id).toBe(400);
    await s.call("POST", url, { id: "sp2", name: "Sam" });
    expect((await s.call("PUT", `${url}/sp2`, { id: "other", name: "Sam" })).statusCode).toBe(400);
    expect((await s.call("PUT", `${url}/sp2`, { id: "sp2", name: "Samuel" })).statusCode).toBe(204);
    expect(s.store.doc("teams/t1/roster/sp2")?.name).toBe("Samuel");
  });

  it("is refused for visitors, players, outsiders and incomplete accounts, and a bad body", async () => {
    const body = { id: "spx", name: "N" };
    expect((await s.call("POST", url, body, null)).statusCode).toBe(401);
    expect((await s.call("POST", url, body, "player")).statusCode).toBe(403);
    expect((await s.call("POST", url, body, "kim")).statusCode).toBe(403);
    expect((await s.call("POST", url, { id: "spx", name: "" })).statusCode).toBe(400);
    expect((await s.call("POST", url, body, "noterms:coach")).json().error.code).toBe("account_incomplete");
    expect(s.store.doc("teams/t1/roster/spx")).toBeUndefined();
  });
});
