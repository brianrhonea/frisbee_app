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

describe("write limits", () => {
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
