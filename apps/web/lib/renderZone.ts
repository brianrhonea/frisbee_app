import { useSyncExternalStore } from "react";
import { serverLocale } from "./dates";

const never = () => () => {};

/**
 * The time zone to show dates in: "UTC" on the server and while the page
 * hydrates, so the browser's first render matches the server's HTML, then
 * the viewer's own (undefined). Pages members open after loading never
 * see the UTC pass.
 */
export function useRenderZone(): string | undefined {
  return useSyncExternalStore(
    never,
    () => undefined,
    () => "UTC",
  );
}

/** The locale that goes with [zone]: fixed for the server's UTC pass (as LocalTime), else the viewer's. */
export const localeFor = (zone: string | undefined) => (zone ? serverLocale : undefined);

/** A day's key in [zone], for grouping by day. */
export const dayKey = (d: Date, zone: string | undefined) =>
  d.toLocaleDateString("en-CA", { year: "numeric", month: "2-digit", day: "2-digit", timeZone: zone });
