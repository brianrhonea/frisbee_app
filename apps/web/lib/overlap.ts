/**
 * Overlap warning for the event editors (Sprint 4 C5): does the event being saved run into one already loaded
 * in the schedule? Pure and local: it only looks at the events the page already holds, never fetches other
 * people's.
 *
 * Rules (the same as the app's):
 * - Cancelled events are ignored (`status` "cancelled"/"canceled", or `cancelled: true`). The website's data has
 *   no cancelled flag yet (a cancelled event is deleted), so this is for when one exists.
 * - An event with no end lasts one hour.
 * - Two timed events overlap when each starts before the other ends; one that starts exactly when the other
 *   ends does not.
 * - An all-day event (`allDay: true`) covers its whole day. It overlaps another all-day event on a shared day,
 *   and a timed event that touches that day. (The website has no all-day events today; this is for when it does.)
 * - The event being edited never overlaps itself (`ignoreId`). A repeating event is checked on its first
 *   occurrence only.
 */
export interface Span {
  id?: string;
  title?: string;
  startsAt?: string | null;
  endsAt?: string | null;
  allDay?: boolean;
  status?: string | null;
  cancelled?: boolean;
}

const hour = 3_600_000;

const cancelled = (s: Span) => s.cancelled === true || s.status === "cancelled" || s.status === "canceled";

/** [from, to) in ms, or null when there is no usable start. An all-day span runs from midnight to midnight, local. */
function range(s: Span): [number, number] | null {
  const start = s.startsAt ? Date.parse(s.startsAt) : NaN;
  if (Number.isNaN(start)) return null;
  if (s.allDay) {
    const first = new Date(start);
    const from = new Date(first.getFullYear(), first.getMonth(), first.getDate()).getTime();
    const end = s.endsAt ? Date.parse(s.endsAt) : NaN;
    const last = Number.isNaN(end) || end < start ? first : new Date(end);
    const to = new Date(last.getFullYear(), last.getMonth(), last.getDate() + 1).getTime();
    return [from, to];
  }
  const end = s.endsAt ? Date.parse(s.endsAt) : NaN;
  return [start, Number.isNaN(end) || end <= start ? start + hour : end];
}

/** True when the two spans overlap by the rules above. */
export function spansOverlap(a: Span, b: Span): boolean {
  const x = range(a);
  const y = range(b);
  if (!x || !y) return false;
  return x[0] < y[1] && y[0] < x[1];
}

/** The first of [others] the [candidate] overlaps, or null. */
export function findOverlap(candidate: Span, others: Span[], ignoreId?: string): Span | null {
  if (cancelled(candidate)) return null;
  for (const o of others) {
    if (cancelled(o) || (ignoreId && o.id === ignoreId)) continue;
    if (spansOverlap(candidate, o)) return o;
  }
  return null;
}

/** The question the editors ask: "This overlaps with Practice (Tue, Nov 24, 6:00 PM). Save anyway?". */
export function overlapMessage(title: string | undefined, startsAt: string | null | undefined, allDay = false): string {
  const when = startsAt ? new Date(startsAt) : null;
  const time =
    when && !Number.isNaN(when.getTime())
      ? when.toLocaleString(undefined, allDay ? { weekday: "short", month: "short", day: "numeric" } : { weekday: "short", month: "short", day: "numeric", hour: "numeric", minute: "2-digit" })
      : "";
  return `This overlaps with ${title?.trim() || "another event"}${time ? ` (${time})` : ""}. Save anyway?`;
}
