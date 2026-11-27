// D-1317: accounts made before the adult-only gate (13 to 17, or never
// asked) have no `ageOk` claim. When ACCOUNT_GATE_MODE=enforce they are left
// out of what strangers can browse (search, public profiles, public posts)
// and can't be sent direct messages. In report mode nothing changes and the
// would-be hiding is only logged.
//
// The answer comes from the Auth custom claim, looked up in batches and kept
// for a few minutes, so a page of results costs at most one `getUsers` call
// and the age record (encrypted) is never opened here. Without a claim
// lookup (UserLookup.ageOkOf, absent in tests and local runs) nothing is
// hidden. The accounts must have been backfilled (account/backfill.ts) before
// enforcement, or adults who never signed in since the gate will be hidden too.
import type { AccountGateMode, UserLookup } from "../auth.js";

/** How long one account's claim is trusted before it is asked again. */
export const adultClaimTtlMs = 5 * 60_000;
const cacheMax = 10_000;

export class AdultVisibility {
  private readonly known = new Map<string, { at: number; ok: boolean }>();

  constructor(
    private readonly users: UserLookup,
    private readonly mode: AccountGateMode,
    private readonly now: () => number = Date.now,
    private readonly log: (event: Record<string, unknown>) => void = (e) => console.warn(JSON.stringify(e)),
  ) {}

  /** Whether hiding is even possible here (a claim lookup exists). */
  private get active(): boolean {
    return typeof this.users.ageOkOf === "function";
  }

  private async withClaims(uids: string[]): Promise<Map<string, boolean>> {
    const at = this.now();
    const out = new Map<string, boolean>();
    const ask: string[] = [];
    for (const u of new Set(uids)) {
      const hit = this.known.get(u);
      if (hit && at - hit.at < adultClaimTtlMs) out.set(u, hit.ok);
      else ask.push(u);
    }
    if (ask.length > 0) {
      const ok = await this.users.ageOkOf!(ask);
      if (this.known.size + ask.length > cacheMax) this.known.clear();
      for (const u of ask) {
        this.known.set(u, { at, ok: ok.has(u) });
        out.set(u, ok.has(u));
      }
    }
    return out;
  }

  /**
   * Which of [uids] to leave out: those without `ageOk` in enforce mode.
   * In report mode, none (how many would be is logged, a count only).
   */
  async hidden(uids: string[]): Promise<Set<string>> {
    if (!this.active || uids.length === 0) return new Set();
    let claims: Map<string, boolean>;
    try {
      claims = await this.withClaims(uids);
    } catch (e) {
      // Enforcing fails closed (the request fails). Reporting must never
      // break a request: log how many were unchecked, never who.
      if (this.mode !== "report") throw e;
      this.log({ severity: "WARNING", event: "adult_visibility_report_error", unchecked: new Set(uids).size });
      return new Set();
    }
    const without = [...claims].filter(([, ok]) => !ok).map(([u]) => u);
    if (without.length === 0) return new Set();
    if (this.mode === "report") {
      this.log({ severity: "WARNING", event: "adult_visibility_report", wouldHide: without.length });
      return new Set();
    }
    return new Set(without);
  }

  async isHidden(uid: string): Promise<boolean> {
    return (await this.hidden([uid])).has(uid);
  }
}
