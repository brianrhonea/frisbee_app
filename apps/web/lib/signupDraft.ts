"use client";
/**
 * What sign-up's first step took (the birthday on /sign-up, and the first
 * and last name from /sign-up or "Your name and username"), held in memory
 * only (never in browser storage) until the details form picks them up,
 * so they aren't asked twice. Gone on reload, when the form simply asks
 * again (the name then comes from the account's display name).
 */
let birthDate: string | undefined;
let name: { first: string; last: string } | undefined;

export const signupDraft = {
  setBirthDate(value: string) {
    birthDate = value;
  },
  /** Read once. */
  takeBirthDate(): string | undefined {
    const v = birthDate;
    birthDate = undefined;
    return v;
  },
  setName(first: string, last: string) {
    name = { first: first.trim(), last: last.trim() };
  },
  /** Read once. */
  takeName(): { first: string; last: string } | undefined {
    const v = name;
    name = undefined;
    return v;
  },
};
