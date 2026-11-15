"use client";
import { type ReactNode, useEffect, useState } from "react";
import { formatDate, serverLocale } from "@/lib/dates";

function parts(d: Date, timeZone?: string) {
  return {
    // The server's UTC copy has a fixed locale, so the browser's first render matches it.
    month: formatDate(d, { month: "short", timeZone }, timeZone ? serverLocale : undefined),
    day: formatDate(d, { day: "numeric", timeZone }, timeZone ? serverLocale : undefined),
  };
}

/**
 * A date badge (in the visitor's time zone once loaded) and details: a card
 * of its own, or a [plain] row inside a card's list.
 */
export function EventItem({ startsAt, plain, children }: { startsAt?: string; plain?: boolean; children: ReactNode }) {
  const d = startsAt ? new Date(startsAt) : null;
  const ok = d !== null && !Number.isNaN(d.getTime());
  const [local, setLocal] = useState<{ month: string; day: string } | null>(null);
  useEffect(() => {
    if (startsAt) setLocal(parts(new Date(startsAt)));
  }, [startsAt]);
  const shown = ok ? (local ?? parts(d, "UTC")) : null;
  return (
    <div className={plain ? "event-row" : "row-card event-row"}>
      <span className="event-date" aria-hidden="true" suppressHydrationWarning>
        {shown ? (
          <>
            <small>{shown.month}</small>
            <b>{shown.day}</b>
          </>
        ) : (
          <b>–</b>
        )}
      </span>
      <span>{children}</span>
    </div>
  );
}
