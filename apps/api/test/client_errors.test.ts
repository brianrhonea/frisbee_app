// `POST /v1/client-errors` with fakes: open to anyone (no token, no App
// Check), strict body, server-side redaction, Error Reporting entry shape,
// silent per-IP limit, CORS for the website.
import { describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { clientErrorLimits, reportedErrorEntry, reportedErrorType } from "../src/client_errors/routes.js";
import { redact, sanitizePath } from "../src/client_errors/sanitize.js";
import { FakeTeamRepository, FakeUsers, FakeVerifier } from "./fakes.js";

const valid = {
  message: "Cannot read properties of undefined",
  stack: "TypeError: Cannot read properties of undefined\n    at Page (https://stall10.app/_next/static/app.js:10:5)",
  url: "/teams/abc",
  release: "0.59.8",
};

function setup(opts: { enforceAppCheck?: boolean } = {}) {
  const entries: Record<string, unknown>[] = [];
  const clock = { now: Date.parse("2026-11-26T12:00:00Z") };
  const app = buildApp({
    verifier: new FakeVerifier(),
    users: new FakeUsers(),
    teams: new FakeTeamRepository(),
    now: () => clock.now,
    enforceAppCheck: opts.enforceAppCheck,
    corsOrigins: ["https://stall10.app", "https://stall10-*.vercel.app"],
    clientErrors: { sink: (e) => entries.push(e) },
  });
  const post = (payload: unknown, headers: Record<string, string> = {}, remoteAddress?: string) =>
    app.inject({ method: "POST", url: "/v1/client-errors", payload: payload as object, headers, remoteAddress });
  return { app, entries, post, clock };
}

describe("POST /v1/client-errors", () => {
  it("answers 204 with no token and no App Check, even when App Check is enforced", async () => {
    const { post, entries } = setup({ enforceAppCheck: true });
    const res = await post(valid);
    expect(res.statusCode).toBe(204);
    expect(res.body).toBe("");
    expect(entries).toHaveLength(1);
  });

  it("treats a bad token as a visitor, not an error", async () => {
    const { post, entries } = setup();
    const res = await post(valid, { authorization: "Bearer not-a-real-token" });
    expect(res.statusCode).toBe(204);
    expect(entries).toHaveLength(1);
  });

  it("accepts a missing digest and an optional one", async () => {
    const { post, entries } = setup();
    expect((await post({ ...valid, digest: "1234567" })).statusCode).toBe(204);
    expect(entries[0].digest).toBe("1234567");
  });

  it.each([
    ["an extra field", { ...valid, userId: "u1" }],
    ["a missing message", { stack: valid.stack, url: valid.url, release: valid.release }],
    ["a missing stack", { message: "x", url: valid.url, release: valid.release }],
    ["a missing release", { message: "x", stack: "s", url: valid.url }],
    ["an empty url", { ...valid, url: "" }],
    ["a message over 1 KB", { ...valid, message: "m".repeat(1025) }],
    ["a stack over 8 KB", { ...valid, stack: "s".repeat(8 * 1024 + 1) }],
    ["a non-string message", { ...valid, message: 5 }],
    ["an array body", [valid]],
  ])("rejects %s with 400 and logs nothing", async (_name, body) => {
    const { post, entries } = setup();
    const res = await post(body);
    expect(res.statusCode).toBe(400);
    expect(entries).toHaveLength(0);
  });

  it("rejects a body over 16 KB", async () => {
    const { post, entries } = setup();
    const res = await post({ ...valid, digest: "d".repeat(20_000) });
    expect(res.statusCode).toBeGreaterThanOrEqual(400);
    expect(res.statusCode).toBeLessThan(500);
    expect(entries).toHaveLength(0);
  });

  it("accepts the largest allowed report", async () => {
    const { post } = setup();
    const res = await post({ ...valid, message: "m ".repeat(512), stack: "at x\n".repeat(1600) });
    expect(res.statusCode).toBe(204);
  });

  it("logs an Error Reporting entry with the stack as the message and the path as the URL", async () => {
    const { post, entries } = setup();
    await post({ ...valid, url: "https://stall10.app/teams/abc?token=secret#frag" });
    expect(entries).toHaveLength(1);
    const e = entries[0];
    expect(e).toMatchObject({
      severity: "ERROR",
      "@type": reportedErrorType,
      serviceContext: { service: "web", version: "0.59.8" },
      message: valid.stack,
      context: { httpRequest: { url: "/teams/abc" } },
    });
    expect(Object.keys(e)).not.toEqual(expect.arrayContaining(["uid", "userId", "ip", "remoteIp"]));
    expect(JSON.stringify(e)).not.toContain("secret");
  });

  it("falls back to the message when the stack is empty", () => {
    const e = reportedErrorEntry({ ...valid, stack: "" });
    expect(e.message).toBe(valid.message);
    expect(e.reportedMessage).toBeUndefined();
  });

  it("puts no caller identity or address in the entry", async () => {
    const { post, entries } = setup();
    await post(valid, { authorization: "Bearer user-1", "x-forwarded-for": "203.0.113.9" }, "198.51.100.7");
    const text = JSON.stringify(entries[0]);
    expect(text).not.toContain("203.0.113.9");
    expect(text).not.toContain("198.51.100.7");
    expect(text).not.toContain("user-1");
  });

  it("redacts emails, JWTs, bearer tokens and long ids in the message and stack", async () => {
    const { post, entries } = setup();
    const jwt = "eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiJ1MSJ9.c2lnbmF0dXJl";
    const id = "a".repeat(40);
    await post({
      ...valid,
      message: `Failed for ann@example.com with ${jwt}`,
      stack: `Error: Authorization: Bearer abc.def-123 at https://x.app/a.js?code=SECRET:1:2 uid=${id}`,
    });
    const text = JSON.stringify(entries[0]);
    for (const leaked of ["ann@example.com", jwt, "abc.def-123", id, "SECRET"]) expect(text).not.toContain(leaked);
    expect(text).toContain("[email]");
    expect(text).toContain("[jwt]");
    expect(text).toContain("Bearer [token]");
    expect(text).toContain("[id]");
    expect(text).toContain("https://x.app/a.js:1:2");
  });

  it("limits per IP, silently: still 204, nothing logged past the limit, other IPs unaffected", async () => {
    const { post, entries } = setup();
    const perMinute = clientErrorLimits[0].max;
    for (let i = 0; i < perMinute + 5; i++) expect((await post(valid, {}, "198.51.100.1")).statusCode).toBe(204);
    expect(entries).toHaveLength(perMinute);
    expect((await post(valid, {}, "198.51.100.2")).statusCode).toBe(204);
    expect(entries).toHaveLength(perMinute + 1);
  });

  it("applies the daily cap after the minute window passes", async () => {
    const { post, entries, clock } = setup();
    const [minute, day] = clientErrorLimits;
    let sent = 0;
    while (sent < day.max) {
      for (let i = 0; i < minute.max && sent < day.max; i++, sent++) await post(valid, {}, "198.51.100.3");
      clock.now += 61_000;
    }
    expect(entries).toHaveLength(day.max);
    await post(valid, {}, "198.51.100.3");
    expect(entries).toHaveLength(day.max);
  });

  it("counts reports over the limit without telling the sender", async () => {
    const { post } = setup();
    for (let i = 0; i < clientErrorLimits[0].max; i++) await post(valid, {}, "198.51.100.4");
    const res = await post(valid, {}, "198.51.100.4");
    expect(res.statusCode).toBe(204);
    expect(res.body).toBe("");
  });
});

describe("CORS for /v1/client-errors", () => {
  it("answers the preflight for the website's origin", async () => {
    const { app } = setup({ enforceAppCheck: true });
    const res = await app.inject({
      method: "OPTIONS",
      url: "/v1/client-errors",
      headers: {
        origin: "https://stall10.app",
        "access-control-request-method": "POST",
        "access-control-request-headers": "content-type",
      },
    });
    expect(res.statusCode).toBe(204);
    expect(res.headers["access-control-allow-origin"]).toBe("https://stall10.app");
    expect(res.headers["access-control-allow-methods"]).toContain("POST");
    expect(String(res.headers["access-control-allow-headers"]).toLowerCase()).toContain("content-type");
  });

  it("allows a preview origin and sends the allow-origin header on the POST itself", async () => {
    const { post } = setup();
    const res = await post(valid, { origin: "https://stall10-git-x.vercel.app" });
    expect(res.statusCode).toBe(204);
    expect(res.headers["access-control-allow-origin"]).toBe("https://stall10-git-x.vercel.app");
  });

  it("gives other origins no CORS headers", async () => {
    const { app } = setup();
    const res = await app.inject({
      method: "OPTIONS",
      url: "/v1/client-errors",
      headers: { origin: "https://evil.example", "access-control-request-method": "POST" },
    });
    expect(res.headers["access-control-allow-origin"]).toBeUndefined();
  });
});

describe("sanitising", () => {
  it("cuts a URL down to its path", () => {
    expect(sanitizePath("https://stall10.app/a/b?x=1#y")).toBe("/a/b");
    expect(sanitizePath("/a?x=1")).toBe("/a");
    expect(sanitizePath("a#frag")).toBe("/a");
    expect(sanitizePath("/invite/" + "z".repeat(40))).toBe("/invite/[id]");
  });

  it("leaves ordinary text alone", () => {
    expect(redact("TypeError: x is undefined at app.js:10:5")).toBe("TypeError: x is undefined at app.js:10:5");
  });
});
