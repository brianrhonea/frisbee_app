// Recurring events: a repeat (daily, weekly, every two weeks or monthly
// until an end date) written out as one ordinary event per occurrence, so
// RSVPs, reminders, the iCal feed and every list keep working unchanged.
// The app's port is apps/mobile/lib/domain/recurrence.dart; both are
// checked against fixtures/recurrence (written by the app's
// test/shared_fixtures/recurrence_fixtures_test.dart).
import { z } from "zod";

export const repeatFrequencies = ["daily", "weekly", "biweekly", "monthly"] as const;
export type RepeatFrequency = (typeof repeatFrequencies)[number];

/** How a repeat reads in a picker ("Weekly"). */
export const repeatFrequencyLabels: Record<RepeatFrequency, string> = {
  daily: "Daily",
  weekly: "Weekly",
  biweekly: "Every 2 weeks",
  monthly: "Monthly",
};

/** The most events one repeat writes out. */
export const maxRepeatOccurrences = 100;

/** The furthest a repeat's end date can be after its first event, in days. */
export const maxRepeatDays = 366;

/** A local calendar date, month 1–12. */
export interface CalendarDate {
  year: number;
  month: number;
  day: number;
}

/** `YYYY-MM-DD`. */
const dateOnly = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "Pick an end date.");

/** How an event repeats: [until] is the last day (inclusive) it can fall on. */
export const repeatSchema = z.strictObject({
  freq: z.enum(repeatFrequencies),
  until: dateOnly,
});
export type Repeat = z.infer<typeof repeatSchema>;

/** `?scope=` on editing or deleting an event in a series: it alone, or it and every later one. */
export const seriesScopes = ["one", "following"] as const;
export type SeriesScope = (typeof seriesScopes)[number];
export const seriesScopeSchema = z.object({ scope: z.enum(seriesScopes).default("one") });

/**
 * `series` on each event of a repeating series: which series, its place
 * and size (so "this and following" knows the later ones' ids without a
 * query), and the repeat, for showing "Repeats weekly until …".
 */
export const seriesSchema = z.strictObject({
  id: z.string().min(1).max(64),
  index: z.number().int().min(0).max(maxRepeatOccurrences - 1),
  count: z.number().int().min(2).max(maxRepeatOccurrences),
  freq: z.enum(repeatFrequencies),
  until: dateOnly,
});
export type Series = z.infer<typeof seriesSchema>;

/** The document id of a series' [index]th event: every event's id is known from the series. */
export const occurrenceId = (seriesId: string, index: number) => `${seriesId}_${index}`;

/**
 * `seriesWrite` on a team event written in bulk ("this and following"):
 * one id per bulk write, [lead] on the event the person edited, so the
 * change notification goes out once (firebase/functions teamEvent).
 * [delete] marks events about to be deleted.
 */
export interface SeriesWrite {
  id: string;
  lead: boolean;
  delete?: boolean;
}

export function parseDateOnly(s: string): CalendarDate {
  const [year, month, day] = s.split("-").map(Number);
  return { year: year!, month: month!, day: day! };
}

export function formatDateOnly(d: CalendarDate): string {
  const p = (n: number, w = 2) => String(n).padStart(w, "0");
  return `${p(d.year, 4)}-${p(d.month)}-${p(d.day)}`;
}

// Calendar arithmetic in UTC, so no time zone can shift a day.
const utc = (d: CalendarDate) => Date.UTC(d.year, d.month - 1, d.day);
const fromUtc = (ms: number): CalendarDate => {
  const x = new Date(ms);
  return { year: x.getUTCFullYear(), month: x.getUTCMonth() + 1, day: x.getUTCDate() };
};
const dayMs = 86_400_000;
const daysInMonth = (year: number, month: number) => new Date(Date.UTC(year, month, 0)).getUTCDate();

/**
 * The dates a repeat starting on [start] falls on, [start] first, up to
 * and including [until]. Monthly keeps the day of the month and skips
 * months without it (the 31st skips 30-day months), as RFC 5545 does.
 * Stops one past [maxRepeatOccurrences] so [repeatProblem] can tell.
 */
export function repeatDates(start: CalendarDate, repeat: Repeat): CalendarDate[] {
  const end = utc(parseDateOnly(repeat.until));
  const out: CalendarDate[] = [];
  const cap = maxRepeatOccurrences + 1;
  if (repeat.freq === "monthly") {
    for (let k = 0; out.length < cap; k++) {
      const m0 = start.month - 1 + k;
      const year = start.year + Math.floor(m0 / 12);
      const month = (m0 % 12) + 1;
      if (start.day > daysInMonth(year, month)) continue;
      const d = { year, month, day: start.day };
      if (utc(d) > end) break;
      out.push(d);
    }
    return out;
  }
  const step = { daily: 1, weekly: 7, biweekly: 14 }[repeat.freq];
  for (let ms = utc(start); ms <= end && out.length < cap; ms += step * dayMs) out.push(fromUtc(ms));
  return out;
}

/** Why a repeat from [start] can't be saved, or null when it can. */
export function repeatProblem(start: CalendarDate, repeat: Repeat): string | null {
  const until = parseDateOnly(repeat.until);
  if (utc(until) < utc(start)) return "The repeat can't end before the event.";
  if ((utc(until) - utc(start)) / dayMs > maxRepeatDays) return "Repeat for at most a year.";
  const n = repeatDates(start, repeat).length;
  if (n > maxRepeatOccurrences) return `That's more than ${maxRepeatOccurrences} events. Pick an earlier end date.`;
  if (n < 2) return "Pick an end date that makes it repeat at least once.";
  return null;
}

/** "Repeats weekly until Mar 3, 2027" (the app's repeatSummary). */
export function repeatSummary(repeat: Pick<Repeat, "freq" | "until">): string {
  const u = parseDateOnly(repeat.until);
  const until = new Date(Date.UTC(u.year, u.month - 1, u.day)).toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
    timeZone: "UTC",
  });
  const how = { daily: "daily", weekly: "weekly", biweekly: "every 2 weeks", monthly: "monthly" }[repeat.freq];
  return `Repeats ${how} until ${until}`;
}

// ---- Instants: the API converts wall-clock times in the caller's zone. ----

interface WallClock extends CalendarDate {
  hour: number;
  minute: number;
  second: number;
}

function wallClockAt(ms: number, timeZone: string): WallClock {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone,
    hourCycle: "h23",
    year: "numeric",
    month: "numeric",
    day: "numeric",
    hour: "numeric",
    minute: "numeric",
    second: "numeric",
  }).formatToParts(new Date(ms));
  const get = (t: string) => Number(parts.find((p) => p.type === t)?.value ?? 0);
  return { year: get("year"), month: get("month"), day: get("day"), hour: get("hour") % 24, minute: get("minute"), second: get("second") };
}

const wallMs = (w: WallClock) => Date.UTC(w.year, w.month - 1, w.day, w.hour, w.minute, w.second);

/** The instant [w] is in [timeZone] (the later one when a clock change makes it ambiguous). */
function wallClockToUtc(w: WallClock, timeZone: string): number {
  const target = wallMs(w);
  let guess = target;
  for (let i = 0; i < 3; i++) {
    const offset = wallMs(wallClockAt(guess, timeZone)) - guess;
    const next = target - offset;
    if (next === guess) break;
    guess = next;
  }
  return guess;
}

/** Whether [timeZone] is an IANA zone this runtime knows. */
export function isTimeZone(timeZone: string): boolean {
  try {
    new Intl.DateTimeFormat("en-US", { timeZone });
    return true;
  } catch {
    return false;
  }
}

/** The local date [iso] falls on in [timeZone]. */
export function dateIn(iso: string, timeZone: string): CalendarDate {
  const w = wallClockAt(Date.parse(iso), timeZone);
  return { year: w.year, month: w.month, day: w.day };
}

/**
 * Every occurrence of an event starting at [startsAt] (and lasting until
 * [endsAt]) repeated by [repeat], at the same wall-clock time in
 * [timeZone], so a 7 pm practice stays at 7 pm across a clock change.
 */
export function seriesTimes(
  startsAt: string,
  endsAt: string | null,
  repeat: Repeat,
  timeZone: string,
): Array<{ startsAt: string; endsAt: string | null }> {
  const startMs = Date.parse(startsAt);
  const length = endsAt === null ? null : Date.parse(endsAt) - startMs;
  const clock = wallClockAt(startMs, timeZone);
  return repeatDates(clock, repeat)
    .slice(0, maxRepeatOccurrences)
    .map((d) => {
      const ms = wallClockToUtc({ ...clock, ...d }, timeZone);
      return { startsAt: new Date(ms).toISOString(), endsAt: length === null ? null : new Date(ms + length).toISOString() };
    });
}

/**
 * How editing "this and following" moves each later occurrence: the
 * edited one's change in time of day (in minutes, wall clock in
 * [timeZone]) and in date (whole days), and its new length.
 */
export function seriesShift(
  before: { startsAt: string },
  after: { startsAt: string; endsAt: string | null },
  timeZone: string,
): { days: number; minutes: number; length: number | null } {
  const a = wallClockAt(Date.parse(before.startsAt), timeZone);
  const b = wallClockAt(Date.parse(after.startsAt), timeZone);
  const days = Math.round((utc(b) - utc(a)) / dayMs);
  const minutes = b.hour * 60 + b.minute - (a.hour * 60 + a.minute);
  const length = after.endsAt === null ? null : Date.parse(after.endsAt) - Date.parse(after.startsAt);
  return { days, minutes, length };
}

/** [startsAt] moved by [shift] (from [seriesShift]), with its end. */
export function shiftOccurrence(
  startsAt: string,
  shift: { days: number; minutes: number; length: number | null },
  timeZone: string,
): { startsAt: string; endsAt: string | null } {
  const w = wallClockAt(Date.parse(startsAt), timeZone);
  const moved = new Date(Date.UTC(w.year, w.month - 1, w.day + shift.days, w.hour, w.minute + shift.minutes, w.second));
  const ms = wallClockToUtc(
    {
      year: moved.getUTCFullYear(),
      month: moved.getUTCMonth() + 1,
      day: moved.getUTCDate(),
      hour: moved.getUTCHours(),
      minute: moved.getUTCMinutes(),
      second: moved.getUTCSeconds(),
    },
    timeZone,
  );
  return { startsAt: new Date(ms).toISOString(), endsAt: shift.length === null ? null : new Date(ms + shift.length).toISOString() };
}
