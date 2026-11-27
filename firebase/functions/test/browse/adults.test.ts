import { describe, expect, it, vi } from "vitest";

import { AdultVisibility, adultClaimTtlMs, gateMode } from "../../src/browse/adults";

const make = (mode: "enforce" | "report", lookup: (u: string[]) => Promise<Set<string>>, clock = { t: 0 }) => {
  const log = vi.fn();
  return { log, clock, v: new AdultVisibility(lookup, () => mode, () => clock.t, log) };
};

describe("gateMode", () => {
  it("is report unless ACCOUNT_GATE_MODE is enforce", () => {
    expect(gateMode({})).toBe("report");
    expect(gateMode({ ACCOUNT_GATE_MODE: "nonsense" })).toBe("report");
    expect(gateMode({ ACCOUNT_GATE_MODE: " Enforce " })).toBe("enforce");
  });
});

describe("browse AdultVisibility", () => {
  it("hides accounts without ageOk when enforcing, and asks once per window", async () => {
    const lookup = vi.fn(async (u: string[]) => new Set(u.filter((x) => x === "adult")));
    const { v, clock } = make("enforce", lookup);
    expect([...(await v.hidden(["adult", "teen", "adult"]))]).toEqual(["teen"]);
    expect([...(await v.hidden(["teen"]))]).toEqual(["teen"]);
    expect(lookup).toHaveBeenCalledTimes(1);
    clock.t = adultClaimTtlMs + 1;
    await v.hidden(["teen"]);
    expect(lookup).toHaveBeenCalledTimes(2);
  });

  it("hides nothing in report mode and logs a count, never uids", async () => {
    const { v, log } = make("report", async () => new Set());
    expect((await v.hidden(["teen-secret-uid"])).size).toBe(0);
    expect(log).toHaveBeenCalledTimes(1);
    expect(log.mock.calls[0][0]).toMatchObject({ event: "adult_visibility_report", wouldHide: 1 });
    expect(JSON.stringify(log.mock.calls)).not.toContain("teen-secret-uid");
  });

  it("report mode survives a lookup failure; enforce mode fails closed", async () => {
    const boom = async () => {
      throw new Error("getUsers down");
    };
    const report = make("report", boom);
    expect((await report.v.hidden(["u1", "u2"])).size).toBe(0);
    expect(report.log.mock.calls[0][0]).toMatchObject({ event: "adult_visibility_report_error", unchecked: 2 });
    expect(JSON.stringify(report.log.mock.calls)).not.toContain("u1");
    await expect(make("enforce", boom).v.hidden(["u1"])).rejects.toThrow("getUsers down");
  });
});
