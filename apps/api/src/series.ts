// Repeating events (packages/shared recurrence.ts): a series is written out
// as one event per occurrence, with ids `${seriesId}_${index}`, so "this and
// following" reaches the later events by id, without a query. Used by team
// events (hub/service.ts) and calendar events (calendar/service.ts).
import {
  dateIn,
  isTimeZone,
  occurrenceId,
  type Repeat,
  repeatProblem,
  type Series,
  type SeriesScope,
  seriesScopeSchema,
  seriesShift,
  seriesTimes,
  shiftOccurrence,
} from "@stall10/shared";
import { ApiError, parseBody } from "./errors.js";
import type { Data } from "./store.js";

/** `?scope=one|following` on an edit or delete (one when left out). */
export function scopeOf(query: unknown): SeriesScope {
  return parseBody(seriesScopeSchema, query ?? {}).scope;
}

function zone(timeZone: string | undefined): string {
  const tz = timeZone ?? "UTC";
  if (!isTimeZone(tz)) throw new ApiError("invalid_argument", "That time zone isn't one we know.");
  return tz;
}

export interface Occurrence {
  id: string;
  startsAt: Date;
  endsAt: Date | null;
  series: Series;
}

/** The events of a new series in [seriesId], first one first. */
export function seriesOccurrences(
  seriesId: string,
  req: { startsAt: string; endsAt: string | null; repeat: Repeat; timeZone?: string },
): Occurrence[] {
  const tz = zone(req.timeZone);
  const problem = repeatProblem(dateIn(req.startsAt, tz), req.repeat);
  if (problem) throw new ApiError("invalid_argument", problem);
  const times = seriesTimes(req.startsAt, req.endsAt, req.repeat, tz);
  return times.map((t, index) => ({
    id: occurrenceId(seriesId, index),
    startsAt: new Date(t.startsAt),
    endsAt: t.endsAt === null ? null : new Date(t.endsAt),
    series: { id: seriesId, index, count: times.length, freq: req.repeat.freq, until: req.repeat.until },
  }));
}

/** A stored event's series, or null for a one-off. */
export function seriesOf(event: Data | null | undefined): Series | null {
  const s = event?.series as Partial<Series> | undefined;
  if (!s || typeof s.id !== "string" || typeof s.index !== "number" || typeof s.count !== "number") return null;
  return s as Series;
}

/** The ids of the events after [event] in its series (some may be deleted). */
export function laterIds(event: Data): string[] {
  const s = seriesOf(event);
  if (!s) return [];
  const out: string[] = [];
  for (let i = s.index + 1; i < Math.min(s.count, 100); i++) out.push(occurrenceId(s.id, i));
  return out;
}

const iso = (v: unknown): string => (v instanceof Date ? v : new Date(v as string)).toISOString();

/**
 * How a later event moves when [before] became [after] for "this and
 * following": the same change of date and time of day, the new length.
 */
export function moveLater(
  before: Data,
  after: { startsAt: Date; endsAt: Date | null },
  timeZone: string | undefined,
): (later: Data) => { startsAt: Date; endsAt: Date | null } {
  const tz = zone(timeZone);
  const shift = seriesShift(
    { startsAt: iso(before.startsAt) },
    { startsAt: after.startsAt.toISOString(), endsAt: after.endsAt?.toISOString() ?? null },
    tz,
  );
  return (later) => {
    const t = shiftOccurrence(iso(later.startsAt), shift, tz);
    return { startsAt: new Date(t.startsAt), endsAt: t.endsAt === null ? null : new Date(t.endsAt) };
  };
}
