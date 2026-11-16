// The per-caller write limits every signed-in write goes through.
import { describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { FakeMediaStorage, FakeStore, FakeTeamRepository, FakeUsers, FakeVerifier } from "./fakes.js";

function setup() {
  const now = Date.UTC(2026, 10, 14, 12);
  const app = buildApp({
    verifier: new FakeVerifier(),
    users: new FakeUsers(),
    teams: new FakeTeamRepository(),
    store: new FakeStore(() => now),
    media: new FakeMediaStorage(),
    now: () => now,
  });
  return (url: string, uid: string) =>
    app.inject({ method: "POST", url, payload: { code: "NOPE" }, headers: { authorization: `Bearer token:${uid}` } });
}

/** Any method, with a clock the test moves. */
function clocked() {
  let now = Date.UTC(2026, 10, 14, 12);
  const app = buildApp({
    verifier: new FakeVerifier(),
    users: new FakeUsers(),
    teams: new FakeTeamRepository(),
    store: new FakeStore(() => now),
    media: new FakeMediaStorage(),
    now: () => now,
  });
  const send = async (method: "POST" | "PUT", url: string, uid: string) =>
    (await app.inject({ method, url, payload: {}, headers: { authorization: `Bearer token:${uid}` } })).statusCode;
  return { send, tick: (ms: number) => void (now += ms) };
}

const schedules = [
  ["POST", "/v1/teams/g1/group-tournaments/t1/schedule"],
  ["PUT", "/v1/tournaments/t1/divisions/d1/schedule"],
] as const;

describe("write limits", () => {
  for (const [method, url] of schedules) {
    it(`${method} ${url}: five a minute and fifty a day`, async () => {
      const { send, tick } = clocked();
      const codes: number[] = [];
      for (let i = 0; i < 6; i++) codes.push(await send(method, url, "amy"));
      expect(codes.slice(0, 5)).not.toContain(429);
      expect(codes[5]).toBe(429);
      expect(await send(method, url, "ben")).not.toBe(429);
      // A minute later there's room again, until fifty in the day.
      let day = 5;
      while (day < 50) {
        tick(61_000);
        for (let i = 0; i < 5 && day < 50; i++, day++) expect(await send(method, url, "amy")).not.toBe(429);
      }
      tick(61_000);
      expect(await send(method, url, "amy")).toBe(429);
    });
  }

  it("reconcile has its own small bucket", async () => {
    const { send } = clocked();
    const codes: number[] = [];
    for (let i = 0; i < 21; i++) codes.push(await send("POST", "/v1/tournaments/t1/divisions/d1/reconcile", "amy"));
    expect(codes.slice(0, 20)).not.toContain(429);
    expect(codes[20]).toBe(429);
  });

  it("stops guessing join codes after ten a minute, per caller", async () => {
    const post = setup();
    const codes: number[] = [];
    for (let i = 0; i < 11; i++) codes.push((await post("/v1/teams/join", "amy")).statusCode);
    expect(codes.slice(0, 10)).not.toContain(429);
    expect(codes[10]).toBe(429);
    expect((await post("/v1/teams/join", "ben")).statusCode).not.toBe(429);
  });

  it("caps new conversations", async () => {
    const post = setup();
    let last = 0;
    for (let i = 0; i < 11; i++) last = (await post("/v1/conversations", "amy")).statusCode;
    expect(last).toBe(429);
  });
});
