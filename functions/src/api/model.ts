// Pure helpers for the `api` group: rate limits and search.

/** Things people do that a flood of fake traffic would repeat. */
export type Action =
  | "message"
  | "post"
  | "comment"
  | "follow"
  | "joinRequest"
  | "team"
  | "search"
  | "signIn";

export interface Limit {
  max: number;
  windowMs: number;
}

const minute = 60_000;
const hour = 60 * minute;

/**
 * At most `max` of each action per user per window. Generous for real
 * people (a fast chat is a few messages a minute) and tight for scripts.
 */
export const limits: Record<Action, Limit> = {
  message: { max: 20, windowMs: minute },
  post: { max: 10, windowMs: hour },
  comment: { max: 30, windowMs: 10 * minute },
  follow: { max: 60, windowMs: hour },
  joinRequest: { max: 20, windowMs: hour },
  team: { max: 5, windowMs: 24 * hour },
  search: { max: 30, windowMs: minute },
  // Per username, against password guessing.
  signIn: { max: 10, windowMs: 15 * minute },
};

/** How long someone over a limit can't post, message, comment or follow. */
export const muteMs = 10 * minute;

/** One fixed window's count, stored in `limits/{uid}.counts.{action}`. */
export interface Counter {
  start: number;
  n: number;
}

/**
 * Counts one more [action] at [now]. A window that has ended starts over.
 * `over` is true for every action past the limit in the window.
 */
export function count(
  prev: Counter | undefined,
  now: number,
  limit: Limit,
): { counter: Counter; over: boolean } {
  const fresh = !prev || typeof prev.start !== "number" || typeof prev.n !== "number" || now - prev.start >= limit.windowMs || now < prev.start;
  const counter = fresh ? { start: now, n: 1 } : { start: prev.start, n: prev.n + 1 };
  return { counter, over: counter.n > limit.max };
}

/** Whether `mutedUntil` (ms since epoch, or missing) is still in force. */
export function isMuted(mutedUntil: number | undefined, now: number): boolean {
  return typeof mutedUntil === "number" && mutedUntil > now;
}

/** What `api-search` looks in. */
export type SearchKind = "players" | "people" | "teams";

export const searchKinds: readonly SearchKind[] = ["players", "people", "teams"];

/** Results returned per search, before the app filters and sorts them. */
export const searchLimit = 50;

/**
 * The keyword the app sends: the longest word of the query, as
 * `searchKeywords` in lib/domain/models/model_utils.dart stores them
 * (lower case, no separators, at most 20 characters). Null when it isn't
 * one.
 */
export function searchKey(key: unknown): string | null {
  if (typeof key !== "string") return null;
  if (key.length < 1 || key.length > 20) return null;
  if (key !== key.toLowerCase() || /[\s\-_.]/.test(key)) return null;
  return key;
}
