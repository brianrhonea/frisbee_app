import { describe, expect, it } from "vitest";
import { calendarEventEnd, calendarLinkNotesMax, googleCalendarUrl, outlookCalendarUrl } from "../src/calendar_links.js";

const params = (url: string) => new URL(url).searchParams;

describe("calendar links", () => {
  const event = {
    title: "Track session & strides",
    startsAt: "2026-11-15T11:00:00-06:00",
    location: "High school track, lane 1",
    description: "Bring water.\nSpikes optional.",
  };

  it("ends an hour after the start unless it has an end", () => {
    expect(calendarEventEnd(event)).toBe("2026-11-15T18:00:00.000Z");
    expect(calendarEventEnd({ ...event, endsAt: "2026-11-15T19:30:00Z" })).toBe("2026-11-15T19:30:00Z");
  });

  it("builds Google Calendar's new-event link", () => {
    const url = googleCalendarUrl(event);
    expect(url.startsWith("https://calendar.google.com/calendar/render?action=TEMPLATE&")).toBe(true);
    const p = params(url);
    expect(p.get("text")).toBe("Track session & strides");
    expect(p.get("dates")).toBe("20261115T170000Z/20261115T180000Z");
    expect(p.get("location")).toBe("High school track, lane 1");
    expect(p.get("details")).toBe("Bring water.\nSpikes optional.");
    // Spaces as %20, never "+".
    expect(url).not.toContain("+");
    expect(url).toContain("Track%20session%20%26%20strides");
  });

  it("builds Outlook's new-event link", () => {
    const url = outlookCalendarUrl({ ...event, endsAt: "2026-11-15T19:30:00.000Z" });
    expect(url.startsWith("https://outlook.live.com/calendar/0/deeplink/compose?")).toBe(true);
    const p = params(url);
    expect(p.get("rru")).toBe("addevent");
    expect(p.get("path")).toBe("/calendar/action/compose");
    expect(p.get("subject")).toBe("Track session & strides");
    expect(p.get("startdt")).toBe("2026-11-15T17:00:00Z");
    expect(p.get("enddt")).toBe("2026-11-15T19:30:00Z");
    expect(p.get("location")).toBe("High school track, lane 1");
    expect(p.get("body")).toBe("Bring water.\nSpikes optional.");
    expect(p.get("allday")).toBe("false");
  });

  it("leaves out an empty location and notes", () => {
    const bare = { title: "Pickup", startsAt: "2026-11-15T17:00:00Z", location: "  ", description: "" };
    for (const url of [googleCalendarUrl(bare), outlookCalendarUrl(bare)]) {
      const p = params(url);
      expect(p.has("location")).toBe(false);
      expect(p.has("details") || p.has("body")).toBe(false);
    }
  });

  it("cuts long notes so the link stays a usable size", () => {
    const details = params(googleCalendarUrl({ ...event, description: "x".repeat(5000) })).get("details")!;
    expect(details.length).toBe(calendarLinkNotesMax);
    expect(details.endsWith("…")).toBe(true);
    // An emoji on the cut stays whole (a split one would make the link throw).
    const emoji = `${"x".repeat(calendarLinkNotesMax - 2)}🥏🥏🥏`;
    const cut = params(outlookCalendarUrl({ ...event, description: emoji })).get("body")!;
    expect([...cut]).toHaveLength(calendarLinkNotesMax);
    expect(cut.endsWith("🥏…")).toBe(true);
  });
});
