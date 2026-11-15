// Small helpers the schedule and calendar settings share.
import { type CalendarColor, calendarColorHex, icsEvent, icsFileName } from "@stall10/shared";

export const colorOf = (c: CalendarColor | undefined) => calendarColorHex[c ?? "green"] ?? calendarColorHex.green;

/** "Add to calendar": one event as an .ics file, which Outlook, Apple and Google Calendar open (the same file as the app's). */
export function downloadIcs(e: {
  uid: string;
  title: string;
  startsAt: string;
  endsAt?: string | null;
  location?: string;
  description?: string;
}) {
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
