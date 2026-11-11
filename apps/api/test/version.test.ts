import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { FakeTeamRepository, FakeUsers, FakeVerifier } from "./fakes.js";

const { version } = JSON.parse(readFileSync(new URL("../package.json", import.meta.url), "utf8")) as { version: string };

describe("version", () => {
  const app = buildApp({ verifier: new FakeVerifier(), users: new FakeUsers(), teams: new FakeTeamRepository() });

  it("GET /health reports package.json's version", async () => {
    const res = await app.inject({ url: "/health" });
    expect(res.json()).toEqual({ ok: true, version });
  });

  it("every answer, errors too, names the version", async () => {
    const res = await app.inject({ method: "POST", url: "/v1/teams", payload: {} });
    expect(res.statusCode).toBe(401);
    expect(res.headers["x-stall10-api-version"]).toBe(version);
  });
});
