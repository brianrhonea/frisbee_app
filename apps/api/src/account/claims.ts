// Writing the account gate's custom claims to Firebase Auth (docs/specifications/
// contracts/account-gate.md). Kept apart from server.ts so it can be tested
// and reused by the claim backfill script.

/** The two Admin SDK calls it needs: auth.getUser(uid) and auth.setCustomUserClaims(uid, claims). */
export interface ClaimsAuth {
  getUser(uid: string): Promise<{ customClaims?: Record<string, unknown> | null }>;
  setCustomUserClaims(uid: string, claims: Record<string, unknown>): Promise<void>;
}

/**
 * [existing] with [claims] merged in (other claims, such as `staff`, stay),
 * or null when that changes nothing: every claim in [claims] already holds
 * the same value.
 */
export function mergedClaims(existing: Record<string, unknown> | null | undefined, claims: Record<string, unknown>): Record<string, unknown> | null {
  const current = existing ?? {};
  if (Object.entries(claims).every(([k, v]) => k in current && current[k] === v)) return null;
  return { ...current, ...claims };
}

/**
 * Merges [claims] into the user's custom claims. Skips the Auth write when
 * nothing would change (F4: the status endpoint runs this for any caller
 * whose token lags, so a repeat must cost a read, not a write). Returns
 * whether it wrote.
 */
export async function setMergedClaims(auth: ClaimsAuth, uid: string, claims: Record<string, unknown>): Promise<boolean> {
  const merged = mergedClaims((await auth.getUser(uid)).customClaims, claims);
  if (!merged) return false;
  await auth.setCustomUserClaims(uid, merged);
  return true;
}
