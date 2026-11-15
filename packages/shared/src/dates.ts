// Dates and times on the wire: ISO 8601 with Z or an offset, never a bare
// local time (the API runs in UTC on Cloud Run, so "2026-11-15T18:00"
// would silently become 18:00 UTC). The website sends toISOString() and
// the app toUtc().toIso8601String(); both carry Z.
import { z } from "zod";

const firestoreMin = Date.UTC(1, 0, 1);
const firestoreMax = Date.UTC(9999, 11, 31, 23, 59, 59, 999);

/** Whether [s] parses to a time Firestore can store as a timestamp. */
const storable = (s: string) => {
  const t = Date.parse(s);
  return !Number.isNaN(t) && t >= firestoreMin && t <= firestoreMax;
};

/** An ISO date-time with Z or an offset that Firestore can store; [message] when it isn't. */
export const isoDateTime = (message = "Give a date and time.") =>
  z.iso.datetime({ offset: true, message }).refine(storable, message);
