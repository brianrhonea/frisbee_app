// Small helpers the schedule and calendar settings share.
import { type CalendarColor, calendarColorHex, icsEvent, icsFileName } from "@stall10/shared";

export const colorOf = (c: CalendarColor | undefined) => calendarColorHex[c ?? "green"] ?? calendarColorHex.green;

/** An event to add to someone's calendar: the .ics fields (Google and Outlook links use all but [uid]). */
export type CalendarFileEvent = {
  /** Stable per event, so adding the file again updates it. */
  uid: string;
  title: string;
  startsAt: string;
  endsAt?: string | null;
  location?: string;
  description?: string;
};

/** "Apple / other" in Add to calendar: one event as an .ics file, which Apple Calendar and the rest open (the same file as the app's). */
export function downloadIcs(e: CalendarFileEvent) {
  const ics = icsEvent(e);
  const url = URL.createObjectURL(new Blob([ics], { type: "text/calendar;charset=utf-8" }));
  const a = document.createElement("a");
  a.href = url;
  a.download = icsFileName(e.title);
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 10_000);
}

/** "Pickup · Sat, Nov 21 at 6:00 PM · Riverside Park": what a shared event says, as the app's eventShareText. */
export function eventShareText(e: CalendarFileEvent): string {
  const d = new Date(e.startsAt);
  const when = d.toLocaleDateString("en-US", { weekday: "short", month: "short", day: "numeric" });
  const time = d.toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit" });
  return [e.title || "Event", `${when} at ${time}`, ...(e.location?.trim() ? [e.location.trim()] : [])].join(" · ");
}

/**
 * Share in Add to calendar: sends one event to anyone, no shared calendar
 * needed. The browser's share sheet with the .ics file where it takes
 * files (phones), else with the text; else the text is copied. Says what
 * happened, for the menu to show.
 */
export async function shareCalendarEvent(e: CalendarFileEvent): Promise<"shared" | "copied" | "cancelled"> {
  const text = eventShareText(e);
  const file = new File([icsEvent(e)], icsFileName(e.title), { type: "text/calendar" });
  try {
    if (navigator.canShare?.({ files: [file] })) {
      await navigator.share({ title: e.title, text, files: [file] });
      return "shared";
    }
    if (typeof navigator.share === "function") {
      await navigator.share({ title: e.title, text });
      return "shared";
    }
  } catch (err) {
    if ((err as Error).name === "AbortError") return "cancelled";
  }
  await navigator.clipboard.writeText(text);
  return "copied";
}

const hiddenKey = "stall10.hiddenCalendars";

/** Calendars the viewer has hidden on this browser (a convenience; nothing is shared). */
export function loadHidden(): string[] {
  try {
    const v = JSON.parse(localStorage.getItem(hiddenKey) ?? "[]");
    return Array.isArray(v) ? v.filter((x): x is string => typeof x === "string") : [];
  } catch {
    return [];
  }
}

export function saveHidden(ids: string[]) {
  try {
    localStorage.setItem(hiddenKey, JSON.stringify(ids));
  } catch {
    // Private windows may refuse storage; hiding then lasts for the visit.
  }
}
