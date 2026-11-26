// The account gate (docs/specifications/contracts/account-gate.md): until an
// account has a verified email, a saved birth date that makes it an adult
// (18+, adultAge) and the current Terms agreed, it may read but not write.
// The API sets two custom claims on the Auth user once the last two are
// true, and checks the token's `email_verified` plus those claims on every
// write (apps/api/src/account/gate.ts); firestore.rules and storage.rules
// check the same three things on every client write.

/** Custom claim: true once a saved birth date makes the person 18 or over. Set only by the API. */
export const ageOkClaim = "ageOk";
/** Custom claim: the Terms version the person agreed to (agreements.ts). Set only by the API. */
export const termsClaim = "terms";

/** What a gated write can be missing, in the order they're reported. */
export const accountGateFields = ["email_unverified", "age", "terms"] as const;
export type AccountGateField = (typeof accountGateFields)[number];

/** Launch is adults only: 18 and over (personal.ts adultAge). */
export const adultOnlyMessage = "You must be 18 or older to use Stall 10.";

/** `fields` of the `account_incomplete` error, keyed by what is missing. */
export const accountGateMessages: Record<AccountGateField, string> = {
  email_unverified: "Verify your email address to continue.",
  age: "Add your date of birth in About you to continue. Stall 10 is for players 18 and older.",
  terms: "Agree to the Community Guidelines and Terms to continue.",
};

/** The birth date is saved once and can't be changed afterwards. */
export const birthDateLockedMessage = "Your date of birth can't be changed. Contact support if it's wrong.";
