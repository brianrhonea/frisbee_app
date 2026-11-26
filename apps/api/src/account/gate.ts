// Sets the account gate's custom claims (docs/specifications/contracts/
// account-gate.md). `ageOk` follows a saved birth date of 18 or over;
// `terms` follows the Terms agreement. Both are derived here from the
// stored records, never from anything the client sends, and only ever set
// (an adult stays one; the birth date can't change; a Terms bump just
// leaves the old `terms` below the current version until they agree again).
import { adultAge, ageOn, ageOkClaim, hasAgreed, termsClaim } from "@stall10/shared";
import type { Caller, UserLookup } from "../auth.js";
import type { BirthDates } from "../teams/club_age.js";
import type { DocStore } from "../store.js";

export class AccountGate {
  constructor(
    private readonly store: DocStore,
    private readonly users: UserLookup,
    /** Absent without the personal-details key: no one can be shown to be an adult, so `ageOk` is never set. */
    private readonly births: BirthDates | undefined,
    private readonly now: () => number = Date.now,
  ) {}

  /**
   * Brings the caller's claims up to what the records say: `ageOk` when
   * the saved birth date makes them 18 or over, `terms` when they agreed.
   * Returns true when their token lacks one now set, so the client must
   * call `getIdToken(true)` before its next write. Safe to repeat. This
   * is also the lazy migration of accounts made before the gate existed:
   * the status endpoint calls it.
   */
  async sync(caller: Caller): Promise<boolean> {
    // The birth date is only opened (decrypted, server side) while their token lacks `ageOk`.
    const needsAge = caller.ageOk !== true;
    const [birthDate, user] = await Promise.all([
      needsAge ? (this.births?.birthDate(caller.uid) ?? null) : null,
      this.store.get(`users/${caller.uid}`),
    ]);
    // The date in the furthest-ahead time zone (UTC+14), as personal
    // details count ages.
    const today = new Date(this.now() + 14 * 3600_000);
    const adult = needsAge && birthDate !== null && ageOn(birthDate, today) >= adultAge;
    const agreed = hasAgreed(user?.agreedTerms);
    const claims: Record<string, unknown> = {};
    if (adult && caller.ageOk !== true) claims[ageOkClaim] = true;
    const version = (user?.agreedTerms as { version: number } | undefined)?.version;
    if (agreed && typeof version === "number" && caller.terms !== version) claims[termsClaim] = version;
    if (Object.keys(claims).length === 0) return false;
    if (!this.users.setClaims) return false;
    await this.users.setClaims(caller.uid, claims);
    return true;
  }
}
