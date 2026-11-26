"use client";
// The account gate on the website (docs/specifications/contracts/account-gate.md
// section 7): what a gated write that stays refused (403 account_incomplete)
// tells the page, so PersonalGate can show the step that's missing. The
// API and the rules enforce the gate; this only explains it.
import {
  type AccountGateField,
  accountGateFields,
  adultAge,
  adultOnlyMessage,
  ageOn,
  birthDateProblem,
  isCalendarDate,
  tooYoungMessage,
} from "@stall10/shared";

/** The missing requirements in the contract's order, from an error's `fields` (unknown keys dropped). */
export function missingFields(fields: Record<string, string> | undefined): AccountGateField[] {
  return accountGateFields.filter((f) => !!fields && f in fields);
}

type Listener = (missing: AccountGateField[] | null) => void;
const listeners = new Set<Listener>();
let current: AccountGateField[] | null = null;

/** A write is still refused after the one status check and retry: show the first missing step. */
export function announceIncomplete(missing: AccountGateField[]) {
  current = missing.length ? missing : null;
  for (const l of listeners) l(current);
}

/** A step was finished (or the account changed): stop showing it. */
export function clearIncomplete() {
  if (current === null) return;
  current = null;
  for (const l of listeners) l(null);
}

/** Calls [fn] with the current answer now and on every change; returns the unsubscribe. */
export function subscribeIncomplete(fn: Listener): () => void {
  listeners.add(fn);
  fn(current);
  return () => {
    listeners.delete(fn);
  };
}

/**
 * A birth date's problem for the adult-only launch (18 and over): the shared
 * checks (format, future, absurd year), then 18+. Under 13 gets the same
 * adult-only message as 13 to 17.
 */
export function adultBirthDateProblem(birthDate: string, today: string | Date): string | null {
  const wrong = birthDateProblem(birthDate, today);
  if (wrong === tooYoungMessage) return adultOnlyMessage;
  if (wrong) return wrong;
  return ageOn(birthDate, today) < adultAge ? adultOnlyMessage : null;
}

/** Today's calendar date where the browser is, YYYY-MM-DD. */
export function localToday(): string {
  const d = new Date();
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

/** True for a well-formed saved birth date that makes the person under 18. */
export function isUnderAge(birthDate: string | undefined | null, today: string | Date): boolean {
  return !!birthDate && isCalendarDate(birthDate) && ageOn(birthDate, today) < adultAge;
}
