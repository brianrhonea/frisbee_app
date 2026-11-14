import { describe, expect, it } from "vitest";
import { icsCalendar, icsDate, icsFold, icsText } from "../src/ical.js";

describe("iCalendar", () => {
  it("escapes text as RFC 5545 says", () => {
    expect(icsText("a\\b;c,d\ne\r\nf")).toBe("a\\\\b\\;c\\,d\\ne\\nf");
  });

  it("writes UTC dates", () => {
    expect(icsDate("2026-11-15T11:00:00-06:00")).toBe("20261115T170000Z");
  });

  it("folds at 75 octets without splitting characters", () => {
    const line = `SUMMARY:${"é".repeat(60)}`; // 8 + 120 octets
    const folded = icsFold(line);
    const parts = folded.split("\r\n");
    expect(parts.length).toBeGreaterThan(1);
    for (const [i, p] of parts.entries()) {
      expect(new TextEncoder().encode(p).length).toBeLessThanOrEqual(75);
      if (i > 0) expect(p.startsWith(" ")).toBe(true);
    }
    expect(parts.map((p, i) => (i ? p.slice(1) : p)).join("")).toBe(line);
    expect(icsFold("SHORT:x")).toBe("SHORT:x");
  });

  it("writes a calendar with CRLF lines, stable UIDs and an hour by default", () => {
    const ics = icsCalendar({
      name: "Casey, training",
      now: "2026-11-13T12:00:00Z",
      refreshHours: 1,
      events: [
        { uid: "e1@stall10.app", title: "Track; easy", startsAt: "2026-11-15T17:00:00Z", location: "Track, lane 1" },
      ],
    });
    expect(ics.endsWith("\r\n")).toBe(true);
    expect(ics.split("\r\n").every((l) => !l.includes("\n"))).toBe(true);
    expect(ics).toContain("X-WR-CALNAME:Casey\\, training\r\n");
    expect(ics).toContain("UID:e1@stall10.app\r\n");
    expect(ics).toContain("DTSTART:20261115T170000Z\r\nDTEND:20261115T180000Z\r\n");
    expect(ics).toContain("SUMMARY:Track\\; easy\r\n");
    expect(ics).toContain("LOCATION:Track\\, lane 1\r\n");
    expect(ics).toContain("REFRESH-INTERVAL;VALUE=DURATION:PT1H\r\n");
    expect(ics).not.toContain("DESCRIPTION");
  });
});
