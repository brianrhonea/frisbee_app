"use client";
import { useEffect, useState } from "react";
import { formatDate, serverLocale } from "@/lib/dates";

/**
 * The date tile of a schedule or event row (the app's DateBadge): a short
 * word over the day in the scoreboard face. [unit] picks the word: the
 * weekday (schedule rows, "THU 16") or the month (event lists, "JAN 16").
 * Shown in the viewer's time zone once loaded; the server's first render is
 * UTC with a fixed locale, which the browser then rewrites.
 *
 * It is decoration (the row's text carries the date), so it is hidden from
 * assistive tech. The classes are the existing `.date-tile` (weekday) and
 * `.event-date` (month), so every place that styles them keeps working.
 */
export type DateBadgeUnit = "weekday" | "month";

function parts(d: Date, unit: DateBadgeUnit, timeZone?: string) {
  const locale = timeZone ? serverLocale : undefined;
  return {
    word: formatDate(d, unit === "month" ? { month: "short", timeZone } : { weekday: "short", timeZone }, locale),
    day: formatDate(d, { day: "numeric", timeZone }, locale),
  };
}

export function DateBadge({ startsAt, unit = "weekday" }: { startsAt?: string | null; unit?: DateBadgeUnit }) {
  const d = startsAt ? new Date(startsAt) : null;
  const ok = d !== null && !Number.isNaN(d.getTime());
  const [local, setLocal] = useState<{ word: string; day: string } | null>(null);
  useEffect(() => {
    if (startsAt) setLocal(parts(new Date(startsAt), unit));
  }, [startsAt, unit]);
  const shown = ok ? (local ?? parts(d, unit, "UTC")) : null;
  return (
    <span className={`ui-date ${unit === "month" ? "event-date" : "date-tile"}`} aria-hidden="true" suppressHydrationWarning>
      {shown ? (
        <>
          <small>{shown.word}</small>
          <b>{shown.day}</b>
        </>
      ) : (
        <b>–</b>
      )}
    </span>
  );
}
