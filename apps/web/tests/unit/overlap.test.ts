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
