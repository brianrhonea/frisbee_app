// One-off: marks existing under-13 refusals `under13: true` so the scheduled
// purge in the functions (D-U13), which can't open the sealed birth date, can
// find them. Refusals written before the marker existed carry no flag. Each
// refusal is opened with the API's cipher and judged the way disabledForAge
// judges it; only an under-13 one is marked. A refusal whose date can't be
// read is NOT marked (the purge deletes an account for good) and is counted,
// for the owner to look at. Idempotent; a dry run (the default) writes
// nothing. The command line is src/scripts/backfill_under13.ts. Logs uids and
// counts only, never a date.
import type { PersonalService } from "../personal/service.js";

export interface RefusalRecord {
  id: string;
  under13?: unknown;
}

export interface Under13BackfillReport {
  scanned: number;
  /** Under 13 and already marked. */
  alreadyMarked: number;
  /** Under 13 and unmarked: would be (dry run) or were (apply) marked. */
  marked: number;
  /** Refusals under 18 only: never marked. */
  adultOnly: number;
  /** Sealed date could not be read: left alone. */
  unreadable: string[];
  /** Marker write failed (apply only). */
  writeFailures: string[];
  applied: boolean;
}

export async function backfillUnder13Marker(opts: {
  refusals: AsyncIterable<RefusalRecord>;
  personal: Pick<PersonalService, "refusalKind">;
  /** Writes the marker; only called when applying. */
  mark: (uid: string) => Promise<void>;
  apply: boolean;
}): Promise<Under13BackfillReport> {
  const report: Under13BackfillReport = { scanned: 0, alreadyMarked: 0, marked: 0, adultOnly: 0, unreadable: [], writeFailures: [], applied: opts.apply };
  for await (const r of opts.refusals) {
    report.scanned++;
    const kind = await opts.personal.refusalKind(r.id);
    if (kind === "unreadable") {
      report.unreadable.push(r.id);
      continue;
    }
    if (kind !== "under13") {
      // A marker on an adult-only refusal would let the purge delete an adult's account: never.
      report.adultOnly++;
      continue;
    }
    if (r.under13 === true) {
      report.alreadyMarked++;
      continue;
    }
    if (!opts.apply) {
      report.marked++;
      continue;
    }
    try {
      await opts.mark(r.id);
      report.marked++;
    } catch {
      report.writeFailures.push(r.id);
    }
  }
  return report;
}
