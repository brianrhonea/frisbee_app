"use client";
import { useEffect, useState } from "react";
import { formatDate, formatDateTime, serverLocale } from "@/lib/dates";

type Style = "date" | "dateTime" | "time" | "relative";

function format(d: Date, style: Style, timeZone?: string): string {
  // The server's UTC copy has a fixed locale, so the browser's first render matches it.
  const locale = timeZone ? serverLocale : undefined;
  if (style === "date") {
    return formatDate(d, { month: "short", day: "numeric", year: "numeric", timeZone }, locale);
  }
  if (style === "time") {
    return formatDateTime(d, { hour: "numeric", minute: "2-digit", timeZone }, locale);
  }
  if (style === "dateTime") {
    return formatDateTime(d, {
      weekday: "short",
      month: "short",
      day: "numeric",
      hour: "numeric",
      minute: "2-digit",
      timeZone,
      timeZoneName: timeZone === "UTC" ? "short" : undefined,
    }, locale);
  }
  const s = Math.round((Date.now() - d.getTime()) / 1000);
  if (s < 60) return "just now";
  if (s < 3600) return `${Math.floor(s / 60)}m`;
  if (s < 86400) return `${Math.floor(s / 3600)}h`;
  if (s < 7 * 86400) return `${Math.floor(s / 86400)}d`;
  return format(d, "date", timeZone);
}

/**
 * A date in the visitor's own time zone. The server renders it in UTC
 * (it can't know the zone), then the browser rewrites it.
 */
export function LocalTime({ iso, style = "date" }: { iso?: string; style?: Style }) {
  const [text, setText] = useState<string | null>(null);
  useEffect(() => {
    if (iso) setText(format(new Date(iso), style));
  }, [iso, style]);
  if (!iso) return null;
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return null;
  return (
    <time dateTime={iso} suppressHydrationWarning>
      {text ?? format(d, style === "relative" ? "date" : style, "UTC")}
    </time>
  );
}
