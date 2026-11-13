// Rate limits, from firebase/functions/src/api/model.ts (count, isMuted,
// searchKey and the browse limit) so the API counts in the same
// `limits/{key}` documents the Cloud Functions do. Keep them in step.

export interface Limit {
  max: number;
  windowMs: number;
}

export interface Counter {
  start: number;
  n: number;
}

const minute = 60_000;

/** Website reads per visitor (or member) per minute, as the callables allow. */
export const browseLimit: Limit = { max: 120, windowMs: minute };

/** How long someone over a limit is turned away. */
export const muteMs = 10 * minute;

/**
 * Counts one more action at [now]. A window that has ended starts over.
 * `over` is true for every action past the limit in the window.
 */
export function count(prev: Counter | undefined, now: number, limit: Limit): { counter: Counter; over: boolean } {
  const fresh =
    !prev || typeof prev.start !== "number" || typeof prev.n !== "number" || now - prev.start >= limit.windowMs || now < prev.start;
  const counter = fresh ? { start: now, n: 1 } : { start: prev.start, n: prev.n + 1 };
  return { counter, over: counter.n > limit.max };
}

/** Whether `mutedUntil` (ms since epoch, or missing) is still in force. */
export function isMuted(mutedUntil: number | undefined, now: number): boolean {
  return typeof mutedUntil === "number" && mutedUntil > now;
}

/** Results per search. */
export const searchLimit = 50;

/**
 * A search keyword as the directory stores them (lower case, no
 * separators, at most 20 characters), or null.
 */
export function searchKey(key: unknown): string | null {
  if (typeof key !== "string") return null;
  if (key.length < 1 || key.length > 20) return null;
  if (key !== key.toLowerCase() || /[\s\-_.]/.test(key)) return null;
  return key;
}
