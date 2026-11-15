// Per-caller caps on reads that fan out to many documents (as the home
// feed's meReadLimits): a roster reads up to ~1,000 profile cards, post
// states a like and a repost per post, the calendar routes every calendar
// the caller is on. Per member, per instance, like the write limits.
import type { FastifyRequest } from "fastify";
import { type Caller, requireCaller } from "../auth.js";
import { ApiError } from "../errors.js";
import type { MemoryRateLimiter } from "./memory.js";
import type { Limit } from "./model.js";

export const readLimits = {
  roster: { max: 60, windowMs: 60_000 },
  postStates: { max: 120, windowMs: 60_000 },
  calendars: { max: 60, windowMs: 60_000 },
  calendarEvents: { max: 60, windowMs: 60_000 },
} satisfies Record<string, Limit>;

export type ReadBucket = keyof typeof readLimits;

/** The signed-in caller, counted against [bucket] when there's a [limiter]. */
export function readCaller(limiter: MemoryRateLimiter | undefined) {
  return (req: FastifyRequest, bucket: ReadBucket): Caller => {
    const c = requireCaller(req);
    if (limiter && !limiter.admit(`read-${bucket}:${c.uid}`, readLimits[bucket])) {
      throw new ApiError("resource_exhausted", "You're doing that too fast. Wait a minute and try again.");
    }
    return c;
  };
}
