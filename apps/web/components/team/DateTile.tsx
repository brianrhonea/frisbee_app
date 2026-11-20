"use client";
import { useEffect, useState } from "react";
import { formatDate, serverLocale } from "@/lib/dates";

function parts(d: Date, timeZone?: string) {
  const locale = timeZone ? serverLocale : undefined;
  return {
    weekday: formatDate(d, { weekday: "short", timeZone }, locale),
    day: formatDate(d, { day: "numeric", timeZone }, locale),
  };
}

/** Whether [iso] falls on today in the viewer's time zone. */
export function isToday(iso: string | null | undefined): boolean {
  if (!iso) return false;
  const d = new Date(iso);
  const n = new Date();
  return d.getFullYear() === n.getFullYear() && d.getMonth() === n.getMonth() && d.getDate() === n.getDate();
}

/**
 * A schedule row's date tile, as the app's: the weekday over the day in
 * the scoreboard face, in the viewer's time zone once loaded (UTC on the
 * server's first render, which the browser then rewrites).
 */
export function DateTile({ startsAt }: { startsAt?: string | null }) {
  const d = startsAt ? new Date(startsAt) : null;
  const ok = d !== null && !Number.isNaN(d.getTime());
  const [local, setLocal] = useState<{ weekday: string; day: string } | null>(null);
  useEffect(() => {
    if (startsAt) setLocal(parts(new Date(startsAt)));
  }, [startsAt]);
  const shown = ok ? (local ?? parts(d, "UTC")) : null;
  return (
    <span className="date-tile" aria-hidden="true" suppressHydrationWarning>
      {shown ? (
        <>
          <small>{shown.weekday}</small>
          <b>{shown.day}</b>
        </>
      ) : (
        <b>–</b>
      )}
    </span>
  );
}
