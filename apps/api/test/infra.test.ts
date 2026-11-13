// CORS, readiness, proxy trust, logging and shutdown: the Cloud Run plumbing
// around the routes (src/cors.ts, logging.ts, shutdown.ts, app.ts).
import { afterEach, describe, expect, it, vi } from "vitest";
import { type AppDeps, buildApp, trustHops } from "../src/app.js";
import { originMatcher, parseCorsOrigins } from "../src/cors.js";
import { cloudLoggingOptions, traceField } from "../src/logging.js";
import { shutdownHandler } from "../src/shutdown.js";
import { FakeTeamRepository, FakeUsers, FakeVerifier } from "./fakes.js";

function setup(opts: Partial<AppDeps> = {}) {
  return buildApp({ verifier: new FakeVerifier(), users: new FakeUsers(), teams: new FakeTeamRepository(), ...opts });
}

const site = "https://stall10.app";
const team = { name: "The Haze", division: "open", level: "club", city: "Austin" };

describe("CORS", () => {
  const origins = [site, "http://localhost:3000", "https://stall10-*.vercel.app"];

  it("answers a preflight from an allowed origin without auth, even with App Check enforced", async () => {
    const app = setup({ corsOrigins: origins, enforceAppCheck: true });
    const res = await app.inject({
      method: "OPTIONS",
      url: "/v1/teams",
      headers: { origin: site, "access-control-request-method": "POST", "access-control-request-headers": "authorization" },
    });
    expect(res.statusCode).toBe(204);
    expect(res.headers["access-control-allow-origin"]).toBe(site);
    expect(res.headers["access-control-allow-methods"]).toContain("POST");
    expect(res.headers["access-control-allow-headers"]).toContain("authorization");
    expect(res.headers["access-control-allow-headers"]).toContain("x-firebase-appcheck");
    expect(res.headers["access-control-allow-credentials"]).toBeUndefined();
    expect(res.headers.vary).toContain("Origin");
  });

  it("gives a disallowed origin no CORS headers", async () => {
    const app = setup({ corsOrigins: origins });
    const pre = await app.inject({
      method: "OPTIONS",
      url: "/v1/teams",
      headers: { origin: "https://evil.example", "access-control-request-method": "POST" },
    });
    expect(pre.statusCode).toBe(204);
    expect(pre.headers["access-control-allow-origin"]).toBeUndefined();
    expect(pre.headers["access-control-allow-methods"]).toBeUndefined();

    const get = await app.inject({ url: "/health", headers: { origin: "https://evil.example" } });
    expect(get.headers["access-control-allow-origin"]).toBeUndefined();
  });

  it("keeps the CORS header on errors, so the site can read the message", async () => {
    const app = setup({ corsOrigins: origins });
    const res = await app.inject({ method: "POST", url: "/v1/teams", payload: team, headers: { origin: site } });
    expect(res.statusCode).toBe(401);
    expect(res.json().error.code).toBe("unauthenticated");
    expect(res.headers["access-control-allow-origin"]).toBe(site);
  });

  it("allows a real request from an allowed origin", async () => {
    const app = setup({ corsOrigins: origins });
    const res = await app.inject({
      method: "POST",
      url: "/v1/teams",
      payload: team,
      headers: { origin: "http://localhost:3000", authorization: "Bearer token:u1:Pat" },
    });
    expect(res.statusCode).toBe(201);
    expect(res.headers["access-control-allow-origin"]).toBe("http://localhost:3000");
  });

  it("allows nothing cross-origin by default", async () => {
    const res = await setup().inject({ url: "/health", headers: { origin: "http://localhost:3000" } });
    expect(res.headers["access-control-allow-origin"]).toBeUndefined();
  });

  it("matches wildcard origins within one label only", () => {
    const allowed = originMatcher(origins);
    expect(allowed("https://stall10-abc123-team.vercel.app")).toBe(true);
    expect(allowed("HTTPS://STALL10.APP")).toBe(true);
    expect(allowed("https://stall10-x.evil.com/.vercel.app")).toBe(false);
    expect(allowed("https://stall10-.vercel.app")).toBe(false);
    expect(allowed("https://stall10-a.b.vercel.app")).toBe(false);
    expect(allowed("https://stall10.app.evil.com")).toBe(false);
    expect(originMatcher(["http://localhost:*"])("http://localhost:5173")).toBe(true);
  });

  it("reads CORS_ORIGINS", () => {
    expect(parseCorsOrigins(undefined)).toEqual(["http://localhost:3000"]);
    expect(parseCorsOrigins(" https://a.test/ , ,https://b.test")).toEqual(["https://a.test", "https://b.test"]);
    expect(parseCorsOrigins("")).toEqual([]);
  });
});

describe("GET /ready", () => {
  it("answers ok without auth, even with App Check enforced", async () => {
    const res = await setup({ enforceAppCheck: true, ready: async () => {} }).inject({ url: "/ready" });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ ok: true });
  });

  it("answers 503 while the readiness check fails", async () => {
    const res = await setup({
      ready: async () => {
        throw new Error("no credentials");
      },
    }).inject({ url: "/ready" });
    expect(res.statusCode).toBe(503);
  });

  it("keeps /health public with App Check enforced", async () => {
    const res = await setup({ enforceAppCheck: true }).inject({ url: "/health" });
    expect(res.statusCode).toBe(200);
  });
});

describe("trustProxy", () => {
  async function ipFor(trustProxy: AppDeps["trustProxy"]) {
    const app = setup({ trustProxy });
    app.get("/v1/test-ip", async (req) => ({ ip: req.ip }));
    const res = await app.inject({
      url: "/v1/test-ip",
      remoteAddress: "169.254.1.1",
      headers: { "x-forwarded-for": "6.6.6.6, 203.0.113.7" },
    });
    return res.json().ip;
  }

  it("takes the address Cloud Run appended, not the one the client sent", async () => {
    expect(await ipFor(trustHops(1))).toBe("203.0.113.7");
  });

  it("trusts a second hop behind a Hosting rewrite", async () => {
    expect(await ipFor(trustHops(2))).toBe("6.6.6.6");
  });

  it("ignores X-Forwarded-For when off", async () => {
    expect(await ipFor(false)).toBe("169.254.1.1");
  });
});

describe("logging", () => {
  it("maps pino levels to Cloud Logging severities", () => {
    const opts = cloudLoggingOptions("info");
    expect(opts.messageKey).toBe("message");
    expect(opts.formatters?.level?.("warn", 40)).toEqual({ severity: "WARNING" });
    expect(opts.formatters?.level?.("fatal", 60)).toEqual({ severity: "CRITICAL" });
  });

  it("writes JSON lines with severity and message", async () => {
    const lines: string[] = [];
    const app = setup({
      logger: { ...cloudLoggingOptions("info"), stream: { write: (l: string) => lines.push(l) } },
      traceProjectId: "demo",
    });
    await app.inject({ url: "/health", headers: { "x-cloud-trace-context": "0123456789abcdef0123456789abcdef/1;o=1" } });
    const entries = lines.map((l) => JSON.parse(l));
    expect(entries.length).toBeGreaterThan(0);
    for (const e of entries) {
      expect(e.severity).toBe("INFO");
      expect(typeof e.message).toBe("string");
      expect(e.level).toBeUndefined();
    }
    // Fastify's own request lines carry the trace too.
    const traced = entries.filter((e) => e["logging.googleapis.com/trace"] === "projects/demo/traces/0123456789abcdef0123456789abcdef");
    expect(traced.map((e) => e.message)).toEqual(expect.arrayContaining(["incoming request", "request completed"]));
  });

  it("reads trace ids only from well-formed headers", () => {
    expect(traceField("nope", "p")).toBeNull();
    expect(traceField(undefined, "p")).toBeNull();
  });
});

describe("shutdown", () => {
  afterEach(() => {
    vi.useRealTimers();
  });

  it("finishes in-flight requests, then exits 0", async () => {
    const app = setup();
    let release!: () => void;
    app.get("/v1/slow", () => new Promise((resolve) => (release = () => resolve({ done: true }))));
    await app.listen({ port: 0, host: "127.0.0.1" });
    const { port } = app.server.address() as { port: number };

    const inFlight = fetch(`http://127.0.0.1:${port}/v1/slow`);
    await vi.waitFor(() => expect(release).toBeDefined());
    const exit = vi.fn();
    const done = shutdownHandler(app, { exit, timeoutMs: 5000 })("SIGTERM");
    expect(exit).not.toHaveBeenCalled();

    release();
    expect((await inFlight).status).toBe(200);
    await done;
    expect(exit).toHaveBeenCalledWith(0);
  });

  it("closes once however many signals arrive", async () => {
    const app = setup();
    const close = vi.spyOn(app, "close");
    const exit = vi.fn();
    const handler = shutdownHandler(app, { exit });
    await Promise.all([handler("SIGTERM"), handler("SIGINT")]);
    expect(close).toHaveBeenCalledTimes(1);
    expect(exit).toHaveBeenCalledTimes(1);
  });

  it("exits 1 when closing takes too long", async () => {
    vi.useFakeTimers();
    const app = setup();
    vi.spyOn(app, "close").mockReturnValue(new Promise(() => {}) as never);
    const exit = vi.fn();
    void shutdownHandler(app, { exit, timeoutMs: 8000 })("SIGTERM");
    await vi.advanceTimersByTimeAsync(8000);
    expect(exit).toHaveBeenCalledWith(1);
  });
});
