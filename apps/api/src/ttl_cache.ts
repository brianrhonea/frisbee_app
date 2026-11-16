/**
 * A small in-process cache of promises: each key's answer is kept for
 * [ttlMs], at most [max] keys (the least recently used go first). Callers
 * asking at once share one load; a load that fails is forgotten, so the
 * next caller tries again.
 */
export class TtlCache<T> {
  private readonly entries = new Map<string, { at: number; value: Promise<T> }>();

  constructor(
    private readonly ttlMs: number,
    private readonly max: number,
    private readonly now: () => number = Date.now,
  ) {}

  get size(): number {
    return this.entries.size;
  }

  get(key: string, load: () => Promise<T>): Promise<T> {
    const t = this.now();
    const hit = this.entries.get(key);
    if (hit && t - hit.at < this.ttlMs) {
      // Most recently used last.
      this.entries.delete(key);
      this.entries.set(key, hit);
      return hit.value;
    }
    const value = load();
    const entry = { at: t, value };
    this.entries.delete(key);
    this.entries.set(key, entry);
    while (this.entries.size > this.max) this.entries.delete(this.entries.keys().next().value as string);
    value.catch(() => {
      if (this.entries.get(key) === entry) this.entries.delete(key);
    });
    return value;
  }
}
