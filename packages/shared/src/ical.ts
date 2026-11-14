// iCalendar (RFC 5545) for Outlook, Apple Calendar and Google Calendar: the
// API's subscription feed and the apps' "Add to calendar" files. Lines end
// in CRLF, text is escaped, and lines longer than 75 octets are folded.

export interface IcsEvent {
  /** Stable across exports, so calendar apps update instead of duplicating. */
  uid: string;
  title: string;
  startsAt: string;
  /** Without an end, an hour long. */
  endsAt?: string | null;
  location?: string;
  description?: string;
  /** Last change (DTSTAMP); now when unknown. */
  updatedAt?: string | null;
}

/** UTF-8 length of [s] (no TextEncoder: this package runs on any JS runtime without DOM types). */
function octets(s: string): number {
  let n = 0;
  for (const ch of s) {
    const c = ch.codePointAt(0) ?? 0;
    n += c < 0x80 ? 1 : c < 0x800 ? 2 : c < 0x10000 ? 3 : 4;
  }
  return n;
}

/** RFC 5545 §3.3.11: backslash, semicolon, comma and newlines. */
export function icsText(s: string): string {
  return s.replace(/\\/g, "\\\\").replace(/;/g, "\\;").replace(/,/g, "\\,").replace(/\r\n|\r|\n/g, "\\n");
}

/** 20261115T170000Z */
export function icsDate(iso: string): string {
  return new Date(iso).toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "");
}

/** RFC 5545 §3.1: lines over 75 octets continue on the next line after a space, never splitting a character. */
export function icsFold(line: string): string {
  if (octets(line) <= 75) return line;
  const out: string[] = [];
  let current = "";
  let size = 0;
  for (const ch of line) {
    const n = octets(ch);
    // The first line holds 75 octets; continuations 74 after their space.
    if (size + n > (out.length === 0 ? 75 : 74)) {
      out.push(current);
      current = "";
      size = 0;
    }
    current += ch;
    size += n;
  }
  out.push(current);
  return out.join("\r\n ");
}

function eventLines(e: IcsEvent, now: string): string[] {
  const end = e.endsAt ?? new Date(Date.parse(e.startsAt) + 3_600_000).toISOString();
  return [
    "BEGIN:VEVENT",
    `UID:${icsText(e.uid)}`,
    `DTSTAMP:${icsDate(e.updatedAt ?? now)}`,
    `DTSTART:${icsDate(e.startsAt)}`,
    `DTEND:${icsDate(end)}`,
    `SUMMARY:${icsText(e.title)}`,
    ...(e.location ? [`LOCATION:${icsText(e.location)}`] : []),
    ...(e.description ? [`DESCRIPTION:${icsText(e.description)}`] : []),
    "END:VEVENT",
  ];
}

/** A whole calendar: a subscription feed, or one event to add. */
export function icsCalendar(a: { name: string; events: IcsEvent[]; now?: string; refreshHours?: number }): string {
  const now = a.now ?? new Date().toISOString();
  const lines = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//Stall 10//Calendar//EN",
    "CALSCALE:GREGORIAN",
    "METHOD:PUBLISH",
    `X-WR-CALNAME:${icsText(a.name)}`,
    ...(a.refreshHours
      ? [`REFRESH-INTERVAL;VALUE=DURATION:PT${a.refreshHours}H`, `X-PUBLISHED-TTL:PT${a.refreshHours}H`]
      : []),
    ...a.events.flatMap((e) => eventLines(e, now)),
    "END:VCALENDAR",
  ];
  return `${lines.map(icsFold).join("\r\n")}\r\n`;
}
