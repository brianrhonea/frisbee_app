// Repeating events (recurrence.ts): the dates against the app's port
// (apps/mobile/lib/domain/models/recurrence.dart) on the vectors in
// fixtures/recurrence (written by
// apps/mobile/test/shared_fixtures/recurrence_fixtures_test.dart), and the
// instants the API writes in a caller's time zone.
import { describe, expect, it } from "vitest";
import {
  formatDateOnly,
  parseDateOnly,
  type Repeat,
  repeatDates,
  repeatProblem,
  repeatSummary,
  seriesShift,
  seriesTimes,
  shiftOccurrence,
} from "../src/index.js";
import { fixture } from "./shared_fixtures.js";

interface DatesCase {
  name: string;
  start: string;
  freq: Repeat["freq"];
  until: string;
  dates: string[];
  problem: string | null;
  summary: string;
}

describe("repeat dates match the app (fixtures/recurrence/dates.json)", () => {
  it.each(fixture<DatesCase>("recurrence/dates.json").cases)("$name", (c) => {
    const repeat = { freq: c.freq, until: c.until };
    const start = parseDateOnly(c.start);
    expect(repeatDates(start, repeat).map(formatDateOnly)).toEqual(c.dates);
    expect(repeatProblem(start, repeat)).toBe(c.problem);
    expect(repeatSummary(repeat)).toBe(c.summary);
  });
});

describe("series in a time zone", () => {
  it("keeps the wall-clock time across a clock change", () => {
    // 6 pm in Denver: MDT on Oct 30, MST from Nov 1.
    const times = seriesTimes("2026-10-31T00:00:00.000Z", "2026-10-31T02:00:00.000Z", { freq: "weekly", until: "2026-11-06" }, "America/Denver");
    expect(times).toEqual([
      { startsAt: "2026-10-31T00:00:00.000Z", endsAt: "2026-10-31T02:00:00.000Z" },
      { startsAt: "2026-11-07T01:00:00.000Z", endsAt: "2026-11-07T03:00:00.000Z" },
    ]);
  });

  it("dates are the zone's: a late-evening start is still that day", () => {
    // 11 pm Nov 20 in Los Angeles is Nov 21 in UTC.
    const times = seriesTimes("2026-11-21T07:00:00.000Z", null, { freq: "daily", until: "2026-11-21" }, "America/Los_Angeles");
    expect(times.map((t) => t.startsAt)).toEqual(["2026-11-21T07:00:00.000Z", "2026-11-22T07:00:00.000Z"]);
  });

  it("moves later events by the same change of date and time", () => {
    const shift = seriesShift(
      { startsAt: "2026-11-20T18:00:00.000Z" },
      { startsAt: "2026-11-21T19:30:00.000Z", endsAt: "2026-11-21T21:30:00.000Z" },
      "UTC",
    );
    expect(shift).toEqual({ days: 1, minutes: 90, length: 2 * 3_600_000 });
    expect(shiftOccurrence("2026-11-27T18:00:00.000Z", shift, "UTC")).toEqual({
      startsAt: "2026-11-28T19:30:00.000Z",
      endsAt: "2026-11-28T21:30:00.000Z",
    });
  });
});
