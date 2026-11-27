// One-off claim backfill for the account gate (docs/specifications/contracts/
// account-gate.md section 5): sets `ageOk` and `terms` on every Auth user whose
// stored records already earn them, so the rules (deployed last) don't lock out
// existing accounts. The same rule as the status endpoint's lazy sync
// (AccountGate.evaluate), run over all users. Idempotent: a user whose claims
// already hold is left alone, and a dry run (the default) writes nothing.
// The command line is src/scripts/backfill_claims.ts. Never logs a birth date,
// a name or an email: uids and counts only.
import type { Caller } from "../auth.js";
import { type AccountGate, type GateLog } from "./gate.js";
import { type ClaimsAuth, setMergedClaims } from "./claims.js";

/** One Auth user, as the Admin SDK's listUsers gives it (only what the backfill reads). */
export interface BackfillUser {
  uid: string;
  customClaims?: Record<string, unknown> | null;
  disabled?: boolean;
}

export interface BackfillReport {
  scanned: number;
  /** Users who would get (dry run) or got (apply) at least one claim. */
  changed: number;
  /** Of those, how many gain each claim. */
  grantsAgeOk: number;
  grantsTerms: number;
  /** Adults whose profile lacks `adult: true`: would get (dry run) or got (apply) it (D-1317). */
  adultMarked: number;
  /** Adults with no profile yet: nothing to mark (the next sync does it). */
  adultNoProfile: number;
  /** Users whose claims already hold everything their records earn. */
  unchanged: number;
  /** Saved birth dates under 18: they get no `ageOk`; counted, never named. */
  minors: number;
  /** Users whose birth date could not be opened: they got no age claim. */
  decryptFailures: string[];
  /** Users whose claim write failed (apply only). */
  writeFailures: string[];
  applied: boolean;
}

/** The ID-token view of a user's current claims, as the API builds a Caller from a token. */
function callerOf(user: BackfillUser): Caller {
  const c = user.customClaims ?? {};
  return { uid: user.uid, ...(c.ageOk === true && { ageOk: true }), ...(typeof c.terms === "number" && { terms: c.terms }) };
}

export async function backfillClaims(opts: {
  users: AsyncIterable<BackfillUser>;
  gate: AccountGate;
  auth: ClaimsAuth;
  /** false (the default of the command line): report only, write nothing. */
  apply: boolean;
}): Promise<BackfillReport> {
  const report: BackfillReport = {
    scanned: 0, changed: 0, grantsAgeOk: 0, grantsTerms: 0, unchanged: 0, minors: 0, adultMarked: 0, adultNoProfile: 0,
    decryptFailures: [], writeFailures: [], applied: opts.apply,
  };
  for await (const user of opts.users) {
    report.scanned++;
    const log: GateLog = {
      warn: (obj: object) => {
        if ((obj as { event?: string }).event === "account_gate_decrypt_failed") report.decryptFailures.push(user.uid);
      },
    };
    const { claims, ageClass } = await opts.gate.evaluate(callerOf(user), log);
    if (ageClass === "under18" || ageClass === "under13") report.minors++;
    // D-1317: every adult (the claim already held, or earned by this run) gets `adult: true` on their profile.
    if (callerOf(user).ageOk === true || claims.ageOk === true) {
      try {
        const marked = await opts.gate.markAdult(user.uid, opts.apply);
        if (marked === "set") report.adultMarked++;
        else if (marked === "noProfile") report.adultNoProfile++;
      } catch {
        report.writeFailures.push(user.uid);
      }
    }
    if (Object.keys(claims).length === 0) {
      report.unchanged++;
      continue;
    }
    report.changed++;
    if ("ageOk" in claims) report.grantsAgeOk++;
    if ("terms" in claims) report.grantsTerms++;
    if (!opts.apply) continue;
    try {
      // Merged into the user's current claims (staff stays), and a no-op if they already match.
      await setMergedClaims(opts.auth, user.uid, claims);
    } catch {
      report.writeFailures.push(user.uid);
    }
  }
  return report;
}
