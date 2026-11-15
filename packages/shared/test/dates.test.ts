import { describe, expect, it } from "vitest";
import { isoDateTime, saveTeamEventRequestSchema } from "../src/index.js";

describe("isoDateTime: an offset is required", () => {
  const s = isoDateTime();
  it("takes what the website and app send", () => {
    // new Date().toISOString(), and Dart's toUtc().toIso8601String() (micro- or no fraction).
    for (const v of ["2026-11-15T18:00:00.000Z", "2026-11-15T18:00:00.123456Z", "2026-11-15T18:00:00Z", "2026-11-15T12:00:00-06:00"]) {
      expect(s.safeParse(v).success).toBe(true);
    }
  });
  it("refuses local times, dates alone and junk", () => {
    for (const v of ["2026-11-15T18:00", "2026-11-15T18:00:00", "2026-11-15", "Nov 15 2026", "", "+275760-09-13T00:00:00.000Z"]) {
      expect(s.safeParse(v).success).toBe(false);
    }
  });
  it("gives the field's own message", () => {
    expect(isoDateTime("Give a date.").safeParse("2026-11-15").error?.issues[0].message).toBe("Give a date.");
  });
});

describe("the schemas that used to take any parseable date", () => {
  it("a team event needs an offset on its times", () => {
    const event = { title: "Practice", type: "practice", location: "", notes: "" };
    expect(saveTeamEventRequestSchema.safeParse({ ...event, startsAt: "2026-11-15T18:00:00.000Z" }).success).toBe(true);
    expect(saveTeamEventRequestSchema.safeParse({ ...event, startsAt: "2026-11-15T18:00" }).success).toBe(false);
  });
});
