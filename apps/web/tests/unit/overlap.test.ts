import { describe, expect, it } from "vitest";
import { findOverlap, overlapMessage, spansOverlap } from "@/lib/overlap";

const at = (h: number, m = 0) => new Date(2026, 10, 24, h, m).toISOString();

describe("overlap check (S4 C5)", () => {
  it("finds a timed event that runs into the new one", () => {
    const other = { id: "a", title: "Practice", startsAt: at(18), endsAt: at(20) };
    expect(findOverlap({ startsAt: at(19), endsAt: at(21) }, [other])).toBe(other);
    expect(findOverlap({ startsAt: at(17), endsAt: at(18, 30) }, [other])).toBe(other);
    expect(findOverlap({ startsAt: at(18, 30), endsAt: at(19) }, [other])).toBe(other);
  });

  it("is not an overlap when one starts as the other ends, or on another day", () => {
    const other = { title: "Practice", startsAt: at(18), endsAt: at(20) };
    expect(findOverlap({ startsAt: at(20), endsAt: at(21) }, [other])).toBeNull();
    expect(findOverlap({ startsAt: at(16), endsAt: at(18) }, [other])).toBeNull();
    expect(findOverlap({ startsAt: new Date(2026, 10, 25, 18).toISOString() }, [other])).toBeNull();
  });

  it("gives an event with no end one hour", () => {
    const other = { startsAt: at(18) };
    expect(spansOverlap({ startsAt: at(18, 59) }, other)).toBe(true);
    expect(spansOverlap({ startsAt: at(19) }, other)).toBe(false);
  });

  it("ignores cancelled events and the event being edited", () => {
    const base = { title: "Practice", startsAt: at(18), endsAt: at(20) };
    expect(findOverlap({ startsAt: at(19) }, [{ ...base, status: "cancelled" }])).toBeNull();
    expect(findOverlap({ startsAt: at(19) }, [{ ...base, cancelled: true }])).toBeNull();
    expect(findOverlap({ id: "e1", startsAt: at(19) }, [{ ...base, id: "e1" }], "e1")).toBeNull();
    expect(findOverlap({ startsAt: at(19), status: "cancelled" }, [base])).toBeNull();
  });

  it("treats an all-day event as the whole day, against all-day and timed events alike", () => {
    const allDay = { title: "Tournament", startsAt: new Date(2026, 10, 24).toISOString(), allDay: true };
    expect(spansOverlap(allDay, { startsAt: at(7), endsAt: at(8) })).toBe(true);
    expect(spansOverlap({ startsAt: at(23), endsAt: at(23, 30) }, allDay)).toBe(true);
    expect(spansOverlap(allDay, { startsAt: new Date(2026, 10, 24, 12).toISOString(), allDay: true })).toBe(true);
    expect(spansOverlap(allDay, { startsAt: new Date(2026, 10, 25, 9).toISOString() })).toBe(false);
    expect(spansOverlap(allDay, { startsAt: new Date(2026, 10, 25).toISOString(), allDay: true })).toBe(false);
  });

  it("checks every occurrence of a new repeating event, not only the first", () => {
    // Weekly from Tue Nov 24 18:00, until Dec 15: Nov 24, Dec 1, Dec 8, Dec 15. Practice sits on the third (Dec 8).
    const start = new Date(2026, 10, 24, 18).toISOString();
    const end = new Date(2026, 10, 24, 19).toISOString();
    const rule = { repeat: { freq: "weekly" as const, until: "2026-12-15" }, timeZone: Intl.DateTimeFormat().resolvedOptions().timeZone };
    const third = { id: "x", title: "Game", startsAt: new Date(2026, 11, 8, 18, 30).toISOString(), endsAt: new Date(2026, 11, 8, 20).toISOString() };
    expect(findOverlap({ startsAt: start, endsAt: end }, [third])).toBeNull();
    expect(findOverlap({ startsAt: start, endsAt: end }, [third], undefined, rule)).toBe(third);
    // Beyond the series' last date there is nothing to meet.
    const late = { ...third, startsAt: new Date(2026, 11, 22, 18).toISOString(), endsAt: new Date(2026, 11, 22, 19).toISOString() };
    expect(findOverlap({ startsAt: start, endsAt: end }, [late], undefined, rule)).toBeNull();
    // A daily series is met on any day, at the same time of day only.
    const daily = { repeat: { freq: "daily" as const, until: "2026-11-30" }, timeZone: rule.timeZone };
    const sameHour = { title: "Run", startsAt: new Date(2026, 10, 27, 18, 15).toISOString(), endsAt: new Date(2026, 10, 27, 18, 45).toISOString() };
    const otherHour = { title: "Run", startsAt: new Date(2026, 10, 27, 9).toISOString(), endsAt: new Date(2026, 10, 27, 10).toISOString() };
    expect(findOverlap({ startsAt: start, endsAt: end }, [sameHour], undefined, daily)).toBe(sameHour);
    expect(findOverlap({ startsAt: start, endsAt: end }, [otherHour], undefined, daily)).toBeNull();
  });

  it("leaves out the other events of the series being edited", () => {
    const mine = { id: "s_1", series: { id: "s" }, title: "Practice", startsAt: at(18), endsAt: at(20) };
    expect(findOverlap({ id: "s_0", series: { id: "s" }, startsAt: at(19), endsAt: at(21) }, [mine])).toBeNull();
    expect(findOverlap({ id: "s_0", series: { id: "other" }, startsAt: at(19), endsAt: at(21) }, [mine])).toBe(mine);
  });

  it("says nothing about an event without a usable start", () => {
    expect(findOverlap({ startsAt: "not a date" }, [{ startsAt: at(18) }])).toBeNull();
    expect(findOverlap({ startsAt: at(18) }, [{ title: "No time" }])).toBeNull();
  });

  it("words the question with the other event's title and time", () => {
    const text = overlapMessage("Practice", at(18));
    expect(text).toMatch(/^This overlaps with Practice \(.+\)\. Save anyway\?$/);
    expect(overlapMessage(undefined, null)).toBe("This overlaps with another event. Save anyway?");
  });
});
