// D-1317 for the browse callables, the same rule as the API's
// AdultVisibility (apps/api/src/account/adult_visibility.ts): accounts
// without the `ageOk` claim are left out of public posts, profiles and
// search when ACCOUNT_GATE_MODE=enforce. The env is the API's, with the
// default `report` when unset (the API refuses to start deployed without it,
// functions cannot): in report mode nothing is hidden and only counts are
// logged. Claims are asked in batches of 100 and kept for five minutes.
import { getAuth } from "firebase-admin/auth";

export type GateMode = "enforce" | "report";

export const adultClaimTtlMs = 5 * 60_000;
const cacheMax = 10_000;

/** ACCOUNT_GATE_MODE as the API reads it; anything but "enforce" reports only. */
export function gateMode(env: NodeJS.ProcessEnv = process.env): GateMode {
  return env.ACCOUNT_GATE_MODE?.trim().toLowerCase() === "enforce" ? "enforce" : "report";
}

/** The uids (of those asked) that carry `ageOk`; one getUsers call per 100. */
export async function ageOkOf(uids: string[]): Promise<Set<string>> {
  const ok = new Set<string>();
  for (let i = 0; i < uids.length; i += 100) {
    const res = await getAuth().getUsers(uids.slice(i, i + 100).map((uid) => ({ uid })));
    for (const u of res.users) if (u.customClaims?.ageOk === true) ok.add(u.uid);
  }
  return ok;
}

export class AdultVisibility {
  private readonly known = new Map<string, { at: number; ok: boolean }>();

  constructor(
    private readonly lookup: (uids: string[]) => Promise<Set<string>> = ageOkOf,
    private readonly mode: () => GateMode = gateMode,
    private readonly now: () => number = Date.now,
    private readonly log: (event: Record<string, unknown>) => void = (e) => console.warn(JSON.stringify(e)),
  ) {}

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
      const ok = await this.lookup(ask);
      if (this.known.size + ask.length > cacheMax) this.known.clear();
      for (const u of ask) {
        this.known.set(u, { at, ok: ok.has(u) });
        out.set(u, ok.has(u));
      }
    }
    return out;
  }

  /** Which of [uids] to leave out: those without `ageOk`, in enforce mode only. */
  async hidden(uids: string[]): Promise<Set<string>> {
    if (uids.length === 0) return new Set();
    const mode = this.mode();
    let claims: Map<string, boolean>;
    try {
      claims = await this.withClaims(uids);
    } catch (e) {
      // Enforcing fails closed; reporting never breaks a request (counts only).
      if (mode !== "report") throw e;
      this.log({ severity: "WARNING", event: "adult_visibility_report_error", unchecked: new Set(uids).size });
      return new Set();
    }
    const without = [...claims].filter(([, ok]) => !ok).map(([u]) => u);
    if (without.length === 0) return new Set();
    if (mode === "report") {
      this.log({ severity: "WARNING", event: "adult_visibility_report", wouldHide: without.length });
      return new Set();
    }
    return new Set(without);
  }
}

export const adults = new AdultVisibility();
