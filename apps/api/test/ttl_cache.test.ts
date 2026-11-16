import { describe, expect, it } from "vitest";
import { TtlCache } from "../src/ttl_cache.js";

describe("TtlCache", () => {
  it("shares one load per key until it expires", async () => {
    let t = 0;
    let loads = 0;
    const cache = new TtlCache<number>(1000, 10, () => t);
    const load = async () => ++loads;
    expect(await Promise.all([cache.get("a", load), cache.get("a", load)])).toEqual([1, 1]);
    t = 999;
    expect(await cache.get("a", load)).toBe(1);
    t = 1000;
    expect(await cache.get("a", load)).toBe(2);
  });

  it("keeps at most [max] keys, dropping the least recently used", async () => {
    const cache = new TtlCache<string>(1000, 2, () => 0);
    await cache.get("a", async () => "a");
    await cache.get("b", async () => "b");
    await cache.get("a", async () => "a2"); // a is used again
    await cache.get("c", async () => "c");
    expect(cache.size).toBe(2);
    expect(await cache.get("a", async () => "reloaded")).toBe("a");
    expect(await cache.get("b", async () => "reloaded")).toBe("reloaded");
  });

  it("forgets a failed load", async () => {
    const cache = new TtlCache<string>(1000, 10, () => 0);
    await expect(cache.get("a", async () => Promise.reject(new Error("down")))).rejects.toThrow("down");
    expect(await cache.get("a", async () => "ok")).toBe("ok");
  });
});
