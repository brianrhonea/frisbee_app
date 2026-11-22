// "Add to calendar" on the website: links that open Google Calendar's or
// Outlook's new-event page filled in with the event, where the person picks
// the calendar and saves. Apple Calendar and others take the .ics file
// (icsEvent). The fields are the app's native "add event" ones
// (CalendarEntry in apps/mobile/lib/data/services/device_calendar_service.dart):
// title, start, end (an hour by default), location and notes.
import { icsDate } from "./ical.js";

export interface CalendarLinkEvent {
  title: string;
  startsAt: string;
  /** Without an end, an hour long. */
  endsAt?: string | null;
  location?: string;
  description?: string;
}

/** Notes in a link are cut here, so the address stays a size browsers and calendars accept. */
export const calendarLinkNotesMax = 1500;

/** When [e] ends: its end, or an hour after it starts (as the .ics files and the app). */
export function calendarEventEnd(e: Pick<CalendarLinkEvent, "startsAt" | "endsAt">): string {
  return e.endsAt ?? new Date(Date.parse(e.startsAt) + 3_600_000).toISOString();
}

/** The notes, cut to [calendarLinkNotesMax] characters (whole code points, so an emoji is never split). */
function notes(e: CalendarLinkEvent): string {
  const chars = [...(e.description ?? "").trim()];
  return chars.length > calendarLinkNotesMax ? `${chars.slice(0, calendarLinkNotesMax - 1).join("").trimEnd()}…` : chars.join("");
}

/** A query string with %20 for spaces (some calendars show "+" literally), skipping empty values. */
function query(params: [string, string | undefined][]): string {
  return params
    .filter((p): p is [string, string] => !!p[1])
    .map(([k, v]) => `${k}=${encodeURIComponent(v)}`)
    .join("&");
}

/** 2026-11-15T17:00:00Z */
function isoUtc(iso: string): string {
  return new Date(iso).toISOString().replace(/\.\d{3}Z$/, "Z");
}

/** Google Calendar's new-event page for [e] (calendar.google.com/calendar/render?action=TEMPLATE). */
export function googleCalendarUrl(e: CalendarLinkEvent): string {
  return `https://calendar.google.com/calendar/render?${query([
    ["action", "TEMPLATE"],
    ["text", e.title],
    ["dates", `${icsDate(e.startsAt)}/${icsDate(calendarEventEnd(e))}`],
    ["location", e.location?.trim()],
    ["details", notes(e)],
  ])}`;
}

/** Outlook's new-event page for [e] (outlook.live.com deeplink compose; UTC times with Z). */
export function outlookCalendarUrl(e: CalendarLinkEvent): string {
  return `https://outlook.live.com/calendar/0/deeplink/compose?${query([
    ["path", "/calendar/action/compose"],
    ["rru", "addevent"],
    ["subject", e.title],
    ["startdt", isoUtc(e.startsAt)],
    ["enddt", isoUtc(calendarEventEnd(e))],
    ["location", e.location?.trim()],
    ["body", notes(e)],
    ["allday", "false"],
  ])}`;
}
