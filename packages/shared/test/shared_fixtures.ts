// Reads the shared example vectors in ../fixtures. The app's tests
// (apps/mobile/test/shared_fixtures) write them from the app's
// implementation, the reference; these tests check the TypeScript ports
// give the same results. Refresh them from apps/mobile with:
//   flutter test test/shared_fixtures --dart-define=UPDATE_FIXTURES=true
import { readFileSync } from "node:fs";

export interface Fixture<C> {
  about: string;
  cases: C[];
}

export function fixture<C>(path: string): Fixture<C> {
  return JSON.parse(readFileSync(new URL(`../fixtures/${path}`, import.meta.url), "utf8")) as Fixture<C>;
}

const pad = (n: number, w = 2) => String(n).padStart(w, "0");

/**
 * [d] as the app writes a local date (DateTime.toIso8601String with no
 * offset): fixtures hold wall-clock times so they read the same in any
 * time zone.
 */
export function localIso(d: Date | string | null | undefined): string | null {
  if (d == null) return null;
  const x = typeof d === "string" ? new Date(d) : d;
  return (
    `${pad(x.getFullYear(), 4)}-${pad(x.getMonth() + 1)}-${pad(x.getDate())}` +
    `T${pad(x.getHours())}:${pad(x.getMinutes())}:${pad(x.getSeconds())}.${pad(x.getMilliseconds(), 3)}`
  );
}
