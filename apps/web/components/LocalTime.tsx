"use client";
import { useEffect, useState } from "react";

type Style = "date" | "dateTime" | "relative";

function format(d: Date, style: Style, timeZone?: string): string {
  if (style === "date") {
    return d.toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric", timeZone });
  }
  if (style === "dateTime") {
    return d.toLocaleString("en-US", {
      weekday: "short",
      month: "short",
      day: "numeric",
      hour: "numeric",
      minute: "2-digit",
      timeZone,
      timeZoneName: timeZone === "UTC" ? "short" : undefined,
    });
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
