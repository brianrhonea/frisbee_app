// The offline queue's rules (outbox.ts) against the app's
// (fixtures/outbox, written by
// apps/mobile/test/shared_fixtures/outbox_fixtures_test.dart).
import { describe, expect, it } from "vitest";
import { afterTry, dueJobs, type OutboxFailure, type OutboxJob, type OutboxState, outboxBackoffMs, outboxFailureOf, outboxFailureOfHttp } from "../src/outbox.js";
import { fixture } from "./shared_fixtures.js";

const job = (over: Partial<OutboxJob>): OutboxJob => ({
  id: "a",
  uid: "me",
  kind: "directMessage",
  createdAt: "2026-11-16T11:00:00.000Z",
  target: "t",
  label: "",
  state: "waiting",
  attempts: 0,
  nextTryAt: null,
  error: null,
  ...over,
});

describe("outbox fixtures", () => {
  it("classifies error codes as the app does", () => {
    for (const c of fixture<{ code: string; failure: OutboxFailure }>("outbox/failures.json").cases) {
      expect(outboxFailureOf(c.code), c.code).toBe(c.failure);
    }
  });

  it("backs off as the app does", () => {
    for (const c of fixture<{ attempts: number; ms: number }>("outbox/backoff.json").cases) {
      expect(outboxBackoffMs(c.attempts)).toBe(c.ms);
    }
  });

  it("updates a job after a try as the app does", () => {
    type C = { now: string; attempts: number; failure: OutboxFailure | null; message: string; result: Record<string, unknown> };
    for (const c of fixture<C>("outbox/after_try.json").cases) {
      const r = afterTry(job({ attempts: c.attempts }), c.failure, new Date(c.now), c.message);
      const view = r ? { state: r.state, attempts: r.attempts, nextTryAt: r.nextTryAt, error: r.error } : { done: true };
      expect(view, String(c.failure)).toEqual(c.result);
    }
  });

  it("picks the due jobs as the app does", () => {
    type J = { id: string; uid: string; target: string; createdAt: string; state: OutboxState; nextTryAt: string | null };
    for (const c of fixture<{ name: string; now: string; jobs: J[]; due: string[] }>("outbox/due.json").cases) {
      const jobs = c.jobs.map((j) => job(j));
      expect(dueJobs(jobs, "me", new Date(c.now)).map((j) => j.id), c.name).toEqual(c.due);
    }
  });
});

describe("outboxFailureOfHttp", () => {
  it("sorts API answers", () => {
    expect(outboxFailureOfHttp(0)).toBe("network");
    expect(outboxFailureOfHttp(503, "unavailable")).toBe("network");
    expect(outboxFailureOfHttp(500, "internal")).toBe("retry");
    expect(outboxFailureOfHttp(429, "resource_exhausted")).toBe("retry");
    expect(outboxFailureOfHttp(409, "already_exists")).toBe("sent");
    expect(outboxFailureOfHttp(403, "permission_denied")).toBe("permanent");
    expect(outboxFailureOfHttp(400)).toBe("permanent");
  });
});
