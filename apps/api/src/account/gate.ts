// Sets the account gate's custom claims (docs/specifications/contracts/
// account-gate.md). `ageOk` follows a saved birth date of 18 or over;
// `terms` follows the Terms agreement. Both are derived here from the
// stored records, never from anything the client sends, and only ever set
// (an adult stays one; the birth date can't change; a Terms bump just
// leaves the old `terms` below the current version until they agree again).
import { adultAge, ageOn, ageOkClaim, hasAgreed, minimumAge, termsClaim } from "@stall10/shared";
import type { Caller, UserLookup } from "../auth.js";
import type { BirthDates } from "../teams/club_age.js";
import type { DocStore } from "../store.js";

/** The slice of a request logger the gate uses (Fastify's `req.log`). */
export interface GateLog {
  warn(obj: object, msg: string): void;
}

/** What the stored records say about an account, as [AccountGate.evaluate] reads them. */
export interface GateEvaluation {
  /** The claims the records earn that [caller]'s token doesn't carry yet. */
  claims: Record<string, unknown>;
  /** The saved birth date's age class, or null when none could be read: for reporting, never sent anywhere. */
  ageClass: "adult" | "under18" | "under13" | null;
}

export class AccountGate {
  constructor(
    private readonly store: DocStore,
    private readonly users: UserLookup,
    /** Absent without the personal-details key: no one can be shown to be an adult, so `ageOk` is never set. */
    private readonly births: BirthDates | undefined,
    private readonly now: () => number = Date.now,
  ) {}

  /**
   * What the records earn [caller] beyond their token: `ageOk` when the
   * saved birth date makes them 18 or over, `terms` when they agreed. The
   * birth date is only opened (decrypted, server side) while the token
   * lacks `ageOk`. If it can't be opened (a decrypt failure, F9), nothing
   * is granted for age: it is logged and the rest still answers.
   */
  async evaluate(caller: Caller, log?: GateLog): Promise<GateEvaluation> {
    const needsAge = caller.ageOk !== true;
    const [birthDate, user] = await Promise.all([needsAge ? this.openBirthDate(caller.uid, log) : null, this.store.get(`users/${caller.uid}`)]);
    // The date in the furthest-ahead time zone (UTC+14), as personal
    // details count ages.
    const today = new Date(this.now() + 14 * 3600_000);
    const age = birthDate === null ? null : ageOn(birthDate, today);
    const claims: Record<string, unknown> = {};
    if (age !== null && age >= adultAge && caller.ageOk !== true) claims[ageOkClaim] = true;
    const version = (user?.agreedTerms as { version: number } | undefined)?.version;
    if (hasAgreed(user?.agreedTerms) && typeof version === "number" && caller.terms !== version) claims[termsClaim] = version;
    const ageClass = age === null ? null : age >= adultAge ? "adult" : age >= minimumAge ? "under18" : "under13";
    return { claims, ageClass };
  }

  /**
   * Brings the caller's claims up to what the records say. Returns true when
   * their token lacks one now set, so the client must call
   * `getIdToken(true)` before its next write (even if Auth already holds it:
   * the users abstraction skips a write that changes nothing). Safe to
   * repeat. This is also the lazy migration of accounts made before the
   * gate existed: the status endpoint calls it.
   */
  async sync(caller: Caller, log?: GateLog): Promise<boolean> {
    const { claims } = await this.evaluate(caller, log);
    if (Object.keys(claims).length === 0) return false;
    if (!this.users.setClaims) return false;
    await this.users.setClaims(caller.uid, claims);
    return true;
  }

  /** The saved birth date, or null when there is none or it can't be opened (logged, no detail of it). */
  private async openBirthDate(uid: string, log?: GateLog): Promise<string | null> {
    try {
      return (await this.births?.birthDate(uid)) ?? null;
    } catch (err) {
      log?.warn({ event: "account_gate_decrypt_failed", uid, err: err instanceof Error ? err.name : "error" }, "birth date could not be opened; no age claim granted");
      return null;
    }
  }
}
