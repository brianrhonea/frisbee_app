import { describe, expect, it } from "vitest";

import { count, isMuted, limits, searchKey } from "../../src/api/model";

describe("count", () => {
  const limit = { max: 3, windowMs: 1000 };

  it("starts a window on the first action", () => {
    expect(count(undefined, 5000, limit)).toEqual({ counter: { start: 5000, n: 1 }, over: false });
  });

  it("is over only past the max within the window", () => {
    let c = count(undefined, 0, limit).counter;
    for (const t of [10, 20]) c = count(c, t, limit).counter;
    expect(c.n).toBe(3);
    expect(count(c, 30, limit).over).toBe(true);
  });

  it("starts over once the window ends, or on bad data", () => {
    expect(count({ start: 0, n: 99 }, 1000, limit)).toEqual({ counter: { start: 1000, n: 1 }, over: false });
    expect(count({ start: 9000, n: 99 }, 1000, limit).counter).toEqual({ start: 1000, n: 1 });
    expect(count({ start: "x", n: 1 } as never, 1000, limit).counter).toEqual({ start: 1000, n: 1 });
  });

  it("lets a fast but real chat through", () => {
    let c = count(undefined, 0, limits.message).counter;
    for (let i = 1; i < 15; i++) c = count(c, i * 3000, limits.message).counter;
    expect(c.n).toBeLessThanOrEqual(limits.message.max);
  });
});

describe("isMuted", () => {
  it("is muted until the time passes", () => {
    expect(isMuted(2000, 1000)).toBe(true);
    expect(isMuted(1000, 1000)).toBe(false);
    expect(isMuted(undefined, 1000)).toBe(false);
  });
});

describe("searchKey", () => {
  it("accepts a stored keyword", () => {
    expect(searchKey("pat")).toBe("pat");
    expect(searchKey("ñandú")).toBe("ñandú");
  });

  it("rejects anything the app wouldn't send", () => {
    for (const k of ["", "Pat", "pat l", "pat_l", "a".repeat(21), 5, null]) {
      expect(searchKey(k)).toBeNull();
    }
  });
});
