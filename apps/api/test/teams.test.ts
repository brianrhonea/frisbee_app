import { searchKeywords } from "@stall10/shared";
import { beforeEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { tooFastMessage } from "../src/teams/service.js";
import { FakeCipher, FakeStore, FakeTeamRepository, FakeUsers, FakeVerifier, seedBirthDate } from "./fakes.js";

const now = Date.UTC(2026, 10, 11, 12);

async function setup(opts: { enforceAppCheck?: boolean; personal?: boolean } = {}) {
  const teams = new FakeTeamRepository();
  const users = new FakeUsers();
  const store = new FakeStore(() => now);
  const cipher = new FakeCipher();
  const { personal = true, ...rest } = opts;
  const app = buildApp({ verifier: new FakeVerifier(), users, teams, store, personal: personal ? cipher : undefined, now: () => now, ...rest });
  // u1 is an adult, so club teams are theirs to start.
  await seedBirthDate(store, cipher, "u1", "1995-06-01");
  const post = (body: unknown, headers: Record<string, string> = { authorization: "Bearer token:u1:Pat" }) =>
    app.inject({ method: "POST", url: "/v1/teams", payload: body as object, headers });
  return { app, teams, users, store, cipher, post };
}

const team = { name: "The Haze", division: "open", level: "club", city: "Austin" };

describe("POST /v1/teams", () => {
  let t: Awaited<ReturnType<typeof setup>>;
  beforeEach(async () => {
    t = await setup();
  });

  it("creates a team owned by the caller", async () => {
    const res = await t.post(team);
    expect(res.statusCode).toBe(201);
    expect(res.json()).toEqual({ id: "team1" });
    expect(t.teams.created).toEqual([
      {
        id: "team1",
        owner: { uid: "u1", label: "Pat" },
        input: expect.objectContaining({ name: "The Haze", kind: "team", leagueId: null }),
      },
    ]);
  });

  it("names the owner from their Auth record, not a stale token", async () => {
    t.users.records.set("u1", { name: "Pat Lee", email: "pat@x.test" });
    expect((await t.post(team)).statusCode).toBe(201);
    expect(t.teams.created[0].owner).toEqual({ uid: "u1", label: "Pat Lee" });
  });

  it("falls back to the email when the account has no name", async () => {
    t.users.records.set("u1", { email: "pat@x.test" });
    await t.post(team);
    expect(t.teams.created[0].owner.label).toBe("pat@x.test");
  });

  it("needs a signed-in caller", async () => {
    const res = await t.post(team, {});
    expect(res.statusCode).toBe(401);
    expect(res.json().error.code).toBe("unauthenticated");
  });

  it("turns down a bad token", async () => {
    const res = await t.post(team, { authorization: "Bearer nope" });
    expect(res.statusCode).toBe(401);
    expect(t.teams.created).toHaveLength(0);
  });

  it("never takes the owner from the body", async () => {
    const res = await t.post({ ...team, ownerId: "someone-else" });
    expect(res.statusCode).toBe(400);
    expect(res.json().error.code).toBe("invalid_argument");
    expect(res.json().error.fields).toHaveProperty("_");
  });

  it("validates the body", async () => {
    const res = await t.post({ ...team, name: "  " });
    expect(res.statusCode).toBe(400);
    expect(res.json().error).toMatchObject({ message: "Name your team.", fields: { name: "Name your team." } });
  });

  it("turns away a muted caller", async () => {
    t.teams.muted.set("u1", now + 5 * 60_000);
    const res = await t.post(team);
    expect(res.statusCode).toBe(429);
    expect(res.json().error.message).toBe("You're going too fast. Try again in 6 minutes.");
  });

  it("lets a caller whose mute has ended through", async () => {
    t.teams.muted.set("u1", now - 1);
    expect((await t.post(team)).statusCode).toBe(201);
  });

  it("refuses a taken name in the same division", async () => {
    t.teams.listings.push({ id: "x", name: "Haze", kind: "team", division: "open", keywords: searchKeywords("Haze") });
    const res = await t.post(team);
    expect(res.statusCode).toBe(409);
    expect(res.json().error.message).toBe('There\'s already a Open team called "Haze". Pick a different name.');
  });

  it("allows the name in another division", async () => {
    t.teams.listings.push({ id: "x", name: "Haze", kind: "team", division: "mixed", keywords: searchKeywords("Haze") });
    expect((await t.post(team)).statusCode).toBe(201);
  });

  it("reserves a league spot only in a league taking teams", async () => {
    const res = await t.post({ ...team, leagueId: "l1" });
    expect(res.statusCode).toBe(412);
    t.teams.leagues.set("l1", true);
    expect((await t.post({ ...team, leagueId: "l1" })).statusCode).toBe(201);
  });

  it("creates groups", async () => {
    const res = await t.post({
      name: "Austin Pickup",
      division: "mixed",
      level: "pickup",
      kind: "community",
      description: "Sundays",
      requiresApproval: true,
      location: { address: "Zilker", lat: 30.2, lng: -97.7 },
    });
    expect(res.statusCode).toBe(201);
  });

  it("rejects bad JSON", async () => {
    const res = await t.app.inject({
      method: "POST",
      url: "/v1/teams",
      payload: "{not json",
      headers: { authorization: "Bearer token:u1", "content-type": "application/json" },
    });
    expect(res.statusCode).toBe(400);
    expect(res.json().error.code).toBe("invalid_argument");
  });
});

describe("POST /v1/teams: club teams are for players 16 and over", () => {
  // now is 2026-11-11 12:00 UTC; ages count on the date in UTC+14, 2026-11-12.
  let t: Awaited<ReturnType<typeof setup>>;
  beforeEach(async () => {
    t = await setup();
  });
  const as = (uid: string) => ({ authorization: `Bearer token:${uid}:Kid` });
  const club = (name: string) => ({ ...team, name });

  it("lets a creator start one on their 16th birthday", async () => {
    await seedBirthDate(t.store, t.cipher, "k1", "2010-11-12");
    expect((await t.post(club("Birthday"), as("k1"))).statusCode).toBe(201);
  });

  it("refuses the day before, and nothing is made", async () => {
    await seedBirthDate(t.store, t.cipher, "k1", "2010-11-13");
    const res = await t.post(club("Too Soon"), as("k1"));
    expect(res.statusCode).toBe(412);
    expect(res.json().error).toEqual({ code: "failed_precondition", message: "Club teams are for players 16 and over." });
    expect(t.teams.created).toEqual([]);
  });

  it("asks for a date of birth first when there's none on file", async () => {
    const res = await t.post(club("No Birthday"), as("nobody"));
    expect(res.statusCode).toBe(412);
    expect(res.json().error.message).toBe("Add your date of birth in About you to join a club team.");
  });

  it("covers a team started for a club league spot too", async () => {
    t.teams.leagues.set("l1", true);
    await seedBirthDate(t.store, t.cipher, "k1", "2012-01-01");
    expect((await t.post({ ...club("League Spot"), leagueId: "l1" }, as("k1"))).statusCode).toBe(412);
  });

  it("leaves other levels and groups alone", async () => {
    await seedBirthDate(t.store, t.cipher, "k1", "2012-01-01");
    for (const level of ["college", "youth", "league", "pickup"]) {
      expect((await t.post({ ...team, name: `Kids ${level}`, level }, as("k1"))).statusCode).toBe(201);
    }
    expect((await t.post({ ...team, name: "Kids Group", kind: "community" }, as("nobody"))).statusCode).toBe(201);
    // Nothing decrypted for them.
    expect(t.cipher.calls.open).toBe(0);
  });

  it("refuses club teams when the API can't read birth dates (no key)", async () => {
    const off = await setup({ personal: false });
    const res = await off.post(team);
    expect(res.statusCode).toBe(503);
    expect(res.json().error.code).toBe("unavailable");
    expect((await off.post({ ...team, level: "pickup" })).statusCode).toBe(201);
  });
});

describe("App Check", () => {
  it("is required when enforced", async () => {
    const { post } = await setup({ enforceAppCheck: true });
    expect((await post(team)).statusCode).toBe(401);
    expect((await post(team, { authorization: "Bearer token:u1", "x-firebase-appcheck": "bad" })).statusCode).toBe(401);
    expect((await post(team, { authorization: "Bearer token:u1", "x-firebase-appcheck": "good" })).statusCode).toBe(201);
  });

  it("only logs a bad token when not enforced", async () => {
    const { post } = await setup();
    expect((await post(team, { authorization: "Bearer token:u1", "x-firebase-appcheck": "bad" })).statusCode).toBe(201);
  });
});

describe("misc", () => {
  it("answers /health without auth", async () => {
    const { app } = await setup({ enforceAppCheck: true });
    expect((await app.inject({ url: "/health" })).json()).toMatchObject({ ok: true });
  });

  it("404s unknown routes in the error shape", async () => {
    const { app } = await setup();
    const res = await app.inject({ url: "/nope" });
    expect(res.statusCode).toBe(404);
    expect(res.json().error.code).toBe("not_found");
  });

  it("words the mute message like the app", () => {
    expect(tooFastMessage(now + 30_000, now)).toBe("You're going too fast. Try again in a minute.");
    expect(tooFastMessage(now + 125_000, now)).toBe("You're going too fast. Try again in 3 minutes.");
  });
});
