// Dates as the website shows and edits them: in the viewer's own time zone
// and locale (undefined: the browser's), the same everywhere.

/** Midnight at the start of today, in the browser's time zone. */
export function startOfToday(): Date {
  const n = new Date();
  return new Date(n.getFullYear(), n.getMonth(), n.getDate());
}

/** An ISO time (or a Date) → the value a datetime-local input takes, in the browser's zone; "" for none. */
export function toLocalInput(at: string | Date | null | undefined): string {
  if (!at) return "";
  const d = typeof at === "string" ? new Date(at) : at;
  if (Number.isNaN(d.getTime())) return "";
  return new Date(d.getTime() - d.getTimezoneOffset() * 60_000).toISOString().slice(0, 16);
}

/** A datetime-local input's value → an ISO time; null when empty. */
export const fromLocalInput = (v: string): string | null => (v ? new Date(v).toISOString() : null);

const asDate = (at: string | Date) => (typeof at === "string" ? new Date(at) : at);

/**
 * The date part of [at] in the viewer's locale, e.g. formatDate(iso, { month: "short", day: "numeric" }).
 * [locale] only for text the server renders before the browser rewrites
 * it (serverLocale), which must match on both sides.
 */
export const formatDate = (at: string | Date, o: Intl.DateTimeFormatOptions, locale?: string) => asDate(at).toLocaleDateString(locale, o);

/** [at] with its time, in the viewer's locale (or [locale], as for formatDate). */
export const formatDateTime = (at: string | Date, o?: Intl.DateTimeFormatOptions, locale?: string) => asDate(at).toLocaleString(locale, o);

/** The fixed locale of a date the server renders (in UTC) before the browser shows the viewer's own. */
export const serverLocale = "en-US";

/** The time of day of [at], in the viewer's locale. */
export const formatTime = (at: string | Date, o: Intl.DateTimeFormatOptions = { hour: "numeric", minute: "2-digit" }) =>
  asDate(at).toLocaleTimeString(undefined, o);
