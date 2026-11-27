"use client";
import type { ReactNode } from "react";
import { DateBadge } from "./ui/DateBadge";

/**
 * A date badge (in the visitor's time zone once loaded) and details: a card
 * of its own, or a [plain] row inside a card's list.
 */
export function EventItem({ startsAt, plain, children }: { startsAt?: string; plain?: boolean; children: ReactNode }) {
  return (
    <div className={plain ? "event-row" : "row-card event-row"}>
      <DateBadge startsAt={startsAt} unit="month" />
      <span>{children}</span>
    </div>
  );
}
