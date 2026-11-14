import { count, type Counter, type Limit } from "./model.js";

/**
 * Per-instance counts in memory: a cheap backstop for signed-in writes
 * (security review S9), with no Firestore read per request. Each Cloud Run
 * instance counts on its own, and counts start over when one starts, so
 * the real ceiling is [limit] × instances and daily caps are best-effort;
 * the functions' flood mute (limits/{uid}.mutedUntil) still applies.
 */
export class MemoryRateLimiter {
  private readonly counters = new Map<string, { counter: Counter; windowMs: number }>();

  constructor(private readonly now: () => number = Date.now) {}

  /** Counts one action for [key]; true if it's allowed. */
  admit(key: string, limit: Limit): boolean {
    const now = this.now();
    if (this.counters.size > 50_000) this.sweep(now);
    const { counter, over } = count(this.counters.get(key)?.counter, now, limit);
    this.counters.set(key, { counter, windowMs: limit.windowMs });
    return !over;
  }

  /** Drops counters whose own window has ended (a minute's or a day's). */
  private sweep(now: number) {
    for (const [k, { counter, windowMs }] of this.counters) if (now - counter.start >= windowMs) this.counters.delete(k);
  }
}
