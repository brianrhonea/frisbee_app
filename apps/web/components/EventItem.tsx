"use client";
import { type ReactNode, useEffect, useState } from "react";

function parts(d: Date, timeZone?: string) {
  return {
    month: d.toLocaleDateString("en-US", { month: "short", timeZone }),
    day: d.toLocaleDateString("en-US", { day: "numeric", timeZone }),
  };
}

/** A date badge (in the visitor's time zone once loaded) and details. */
export function EventItem({ startsAt, children }: { startsAt?: string; children: ReactNode }) {
  const d = startsAt ? new Date(startsAt) : null;
  const ok = d !== null && !Number.isNaN(d.getTime());
  const [local, setLocal] = useState<{ month: string; day: string } | null>(null);
  useEffect(() => {
    if (startsAt) setLocal(parts(new Date(startsAt)));
  }, [startsAt]);
  const shown = ok ? (local ?? parts(d, "UTC")) : null;
  return (
    <div className="row-card event-row">
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
