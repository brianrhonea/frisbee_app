import type { FastifyInstance } from "fastify";
import { ApiError } from "../errors.js";
import type { MemoryRateLimiter } from "./memory.js";
import type { Limit } from "./model.js";

const minute = 60_000;
const day = 24 * 60 * minute;

/** Every signed-in write, whatever the route (security review S9). */
export const anyWriteLimit: Limit = { max: 120, windowMs: minute };

/**
 * Tighter limits on writes that reach other people or can be guessed at:
 * joining by code, invites, new teams, uploads and new conversations.
 * Keys are "METHOD route".
 */
export const routeWriteLimits: Record<string, Limit[]> = {
  "POST /v1/teams/join": [{ max: 10, windowMs: minute }],
  "POST /v1/teams": [{ max: 5, windowMs: minute }, { max: 30, windowMs: day }],
  "POST /v1/invite-codes": [{ max: 20, windowMs: minute }],
  "POST /v1/teams/:teamId/invites": [{ max: 20, windowMs: minute }],
  "POST /v1/teams/:teamId/join-requests": [{ max: 10, windowMs: minute }],
  "POST /v1/uploads": [{ max: 30, windowMs: minute }],
  "POST /v1/conversations": [{ max: 10, windowMs: minute }, { max: 100, windowMs: day }],
  "POST /v1/conversations/groups": [{ max: 5, windowMs: minute }, { max: 30, windowMs: day }],
};

const reads = new Set(["GET", "HEAD", "OPTIONS"]);

/**
 * Counts each signed-in caller's writes in memory (per instance, so the
 * real ceiling is the limit times the instances), after the auth hook has
 * read the caller. Visitors' writes fail their own sign-in check.
 */
export function registerWriteLimits(app: FastifyInstance, limiter: MemoryRateLimiter) {
  app.addHook("preHandler", async (req) => {
    if (reads.has(req.method) || !req.caller) return;
    const uid = req.caller.uid;
    const route = `${req.method} ${req.routeOptions.url ?? ""}`;
    const limits = routeWriteLimits[route] ?? [];
    const ok = limiter.admit(`any:${uid}`, anyWriteLimit) && limits.every((limit, i) => limiter.admit(`${route}#${i}:${uid}`, limit));
    if (!ok) throw new ApiError("resource_exhausted", "You're doing that too fast. Wait a minute and try again.");
  });
}
