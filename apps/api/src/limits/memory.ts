import { count, type Counter, type Limit } from "./model.js";

/**
 * Per-instance counts in memory: a cheap backstop for signed-in writes
 * (security review S9), with no Firestore read per request. Each Cloud Run
 * instance counts on its own, so the real ceiling is [limit] × instances;
 * the functions' flood mute (limits/{uid}.mutedUntil) still applies.
 */
export class MemoryRateLimiter {
  private readonly counters = new Map<string, Counter>();

  constructor(private readonly now: () => number = Date.now) {}

  /** Counts one action for [key]; true if it's allowed. */
  admit(key: string, limit: Limit): boolean {
    const now = this.now();
    if (this.counters.size > 50_000) this.sweep(now, limit.windowMs);
    const { counter, over } = count(this.counters.get(key), now, limit);
    this.counters.set(key, counter);
    return !over;
  }

  private sweep(now: number, windowMs: number) {
    for (const [k, c] of this.counters) if (now - c.start >= windowMs) this.counters.delete(k);
  }
}
