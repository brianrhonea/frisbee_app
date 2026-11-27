"use client";
import { DateBadge } from "@/components/ui/DateBadge";

/** Whether [iso] falls on today in the viewer's time zone. */
export function isToday(iso: string | null | undefined): boolean {
  if (!iso) return false;
  const d = new Date(iso);
  const n = new Date();
  return d.getFullYear() === n.getFullYear() && d.getMonth() === n.getMonth() && d.getDate() === n.getDate();
}

/**
 * A schedule row's date tile, as the app's: the weekday over the day. This
 * is the shared DateBadge (components/ui/DateBadge.tsx) in its weekday form.
 */
export function DateTile({ startsAt }: { startsAt?: string | null }) {
  return <DateBadge startsAt={startsAt} unit="weekday" />;
}
