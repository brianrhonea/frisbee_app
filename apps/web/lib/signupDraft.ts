"use client";
/**
 * The birthday typed on /sign-up's first step, held in memory only (never
 * in browser storage) until the details form picks it up, so it isn't
 * asked twice. Gone on reload, when the form simply asks again.
 */
let birthDate: string | undefined;

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
};
