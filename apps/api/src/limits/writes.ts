import type { FastifyInstance } from "fastify";
import { type MemoryRateLimiter, tooFast } from "./memory.js";
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
  "PUT /v1/me/identity": [{ max: 10, windowMs: minute }],
  // Each full save is a KMS encrypt and decrypt (the locked-birth-date check), and a
  // refused under-18 date writes a refusal record (F3).
  "PUT /v1/me/personal": [{ max: 5, windowMs: minute }, { max: 20, windowMs: day }],
  // Once per sign-up; each one is a KMS encrypt.
  "PUT /v1/me/personal/birth-date": [{ max: 5, windowMs: minute }, { max: 20, windowMs: day }],
  "DELETE /v1/teams/:teamId": [{ max: 3, windowMs: minute }],
  // Team details; a switch to club decrypts every member's birth date (KMS) and answers how many fail.
  "PATCH /v1/teams/:teamId": [{ max: 5, windowMs: minute }, { max: 30, windowMs: day }],
  "POST /v1/conversations": [{ max: 10, windowMs: minute }, { max: 100, windowMs: day }],
  "POST /v1/conversations/groups": [{ max: 5, windowMs: minute }, { max: 30, windowMs: day }],
  // Publishing a schedule rewrites up to thousands of games.
  "POST /v1/teams/:teamId/group-tournaments/:tournamentId/schedule": [{ max: 5, windowMs: minute }, { max: 50, windowMs: day }],
  "PUT /v1/tournaments/:id/divisions/:divisionId/schedule": [{ max: 5, windowMs: minute }, { max: 50, windowMs: day }],
  // The host's open page asks after each change (debounced); each reads every game and entry.
  "POST /v1/tournaments/:id/divisions/:divisionId/reconcile": [{ max: 20, windowMs: minute }],
};

const reads = new Set(["GET", "HEAD", "OPTIONS"]);

/**
 * Live draft picks and the host's controls skip the any-write count up
 * front: a host auto-picking a 200-player draft would pass 120 a minute.
 * Their own bucket (draftLimits in drafts/routes.ts) bounds them, and every
 * call that fails (a stranger, or someone off the clock) is counted
 * against the any-write bucket after all (countFailedWrite).
 */
export const ownBucket = new Set([
  "POST /v1/tournaments/:tournamentId/divisions/:divisionId/draft/picks",
  "POST /v1/tournaments/:tournamentId/divisions/:divisionId/draft/control",
]);

/** Counts a failed exempt write against [uid]'s any-write bucket; false once it's over. */
export function countFailedWrite(limiter: MemoryRateLimiter, uid: string): boolean {
  return limiter.admit(`any:${uid}`, anyWriteLimit);
}

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
    const ok = (ownBucket.has(route) || limiter.admit(`any:${uid}`, anyWriteLimit)) && limits.every((limit, i) => limiter.admit(`${route}#${i}:${uid}`, limit));
    if (!ok) throw tooFast();
  });
}
