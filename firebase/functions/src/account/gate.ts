// The account gate for callables (docs/specifications/contracts/account-gate.md,
// review finding F2): the same check the API and the rules make on a write.
// A signed-in caller needs a verified email, the `ageOk` claim and the
// CURRENT Terms version in the ID token, or the callable that writes or
// hands out access (LiveKit tokens, league and draft changes) refuses.
// Pure, so it is unit-tested without Firebase.

import { HttpsError } from "firebase-functions/v2/https";

/**
 * The CURRENT Terms version: termsVersion in packages/shared/src/agreements.ts.
 * Functions can't import the shared package, so test/account/callable_gate.test.ts
 * fails until this equals it (bump all three together with the rules).
 */
export const currentTermsVersion = 1;

export type GateField = "email_unverified" | "age" | "terms";

/** The API's texts (packages/shared account_gate.ts accountGateMessages); a test keeps them equal. */
export const gateMessages: Record<GateField, string> = {
  email_unverified: "Verify your email address to continue.",
  age: "Add your date of birth in About you to continue. Stall 10 is for players 18 and older.",
  terms: "Agree to the Community Guidelines and Terms to continue.",
};

/** The slice of a callable's `auth` the check reads. */
export interface GateAuth {
  token: Record<string, unknown>;
}

/** What the token lacks of a complete account, in the API's report order. */
export function gateMissing(auth: GateAuth): GateField[] {
  const t = auth.token;
  const missing: GateField[] = [];
  if (t.email_verified !== true) missing.push("email_unverified");
  if (t.ageOk !== true) missing.push("age");
  if (typeof t.terms !== "number" || t.terms < currentTermsVersion) missing.push("terms");
  return missing;
}

/**
 * Throws `permission-denied` (the callable form of the API's 403
 * account_incomplete; details.code is "account_incomplete", details.fields
 * says what is missing) unless the caller's token is a complete account.
 * Call it right after the sign-in check, before reading any request data.
 */
export function requireCompleteAccount(auth: GateAuth): void {
  const missing = gateMissing(auth);
  if (missing.length === 0) return;
  throw new HttpsError("permission-denied", gateMessages[missing[0]!], {
    code: "account_incomplete",
    fields: Object.fromEntries(missing.map((f) => [f, gateMessages[f]])),
  });
}
