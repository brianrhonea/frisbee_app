// A player's personal details (legal name, birthday, phone, gender,
// address and, under 18, a parent or guardian): asked at sign-up, as USA
// Ultimate's membership form does. Only the player ever sees them: the API
// keeps them encrypted (Cloud KMS) in personalDetails/{uid}, which
// firestore.rules closes to every client. Their email is the account's.
import { z } from "zod";

/** Too young to have an account (COPPA): sign-up stops. */
export const minimumAge = 13;
/** Under this, a parent or guardian's details are asked too. */
export const adultAge = 18;

/**
 * Accounts made from this time on must give their details before using the
 * app or site; older ones are asked, and may wait.
 */
export const personalDetailsRequiredSince = "2026-11-14T00:00:00Z";

export const genders = ["woman", "man", "nonbinary", "unspecified"] as const;
export type Gender = (typeof genders)[number];
export const genderLabels: Record<Gender, string> = {
  woman: "Woman",
  man: "Man",
  nonbinary: "Non-binary",
  unspecified: "Prefer not to say",
};

export const personalLimits = {
  name: 60,
  phone: 30,
  email: 254,
  line: 100,
  city: 60,
  region: 60,
  postalCode: 20,
  relationship: 40,
} as const;

/** The message when someone under [minimumAge] tries to sign up. */
export const tooYoungMessage = `You must be ${minimumAge} or older to use Stall 10.`;

const text = (max: number, what: string) =>
  z
    .string()
    .trim()
    .min(1, `Enter ${what}.`)
    .max(max, `${what[0]!.toUpperCase()}${what.slice(1)} is too long.`);

/** 7 to 15 digits, with an optional leading + and the usual separators. */
export function phoneProblem(input: string): string | null {
  const s = input.trim();
  if (!/^\+?[0-9 ().-]+$/.test(s)) return "Use only digits, spaces, +, -, ( and ).";
  const digits = s.replace(/\D/g, "").length;
  if (digits < 7 || digits > 15) return "Enter a full phone number.";
  return null;
}

const phone = z
  .string()
  .trim()
  .min(1, "Enter a phone number.")
  .max(personalLimits.phone, "That phone number is too long.")
  .refine((s) => phoneProblem(s) === null, { message: "Enter a valid phone number." });

/** YYYY-MM-DD, a real calendar date. */
export function isCalendarDate(s: string): boolean {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s);
  if (!m) return false;
  const [y, mo, d] = [Number(m[1]), Number(m[2]), Number(m[3])];
  const date = new Date(Date.UTC(y, mo - 1, d));
  return date.getUTCFullYear() === y && date.getUTCMonth() === mo - 1 && date.getUTCDate() === d;
}

/**
 * Whole years from [birthDate] (YYYY-MM-DD) to [today]'s calendar date
 * (YYYY-MM-DD, or a Date read in UTC). Someone born on 29 February turns a
 * year older on 1 March in common years.
 */
export function ageOn(birthDate: string, today: string | Date): number {
  const t = typeof today === "string" ? today : today.toISOString().slice(0, 10);
  const [by, bm, bd] = birthDate.split("-").map(Number) as [number, number, number];
  const [ty, tm, td] = t.split("-").map(Number) as [number, number, number];
  let age = ty - by;
  if (tm < bm || (tm === bm && td < bd)) age--;
  return age;
}

/** What's wrong with [birthDate] on [today], or null; under 13 gives [tooYoungMessage]. */
export function birthDateProblem(birthDate: string, today: string | Date): string | null {
  if (!isCalendarDate(birthDate)) return "Enter your date of birth.";
  const age = ageOn(birthDate, today);
  if (age < 0) return "That date is in the future.";
  if (age > 120) return "Check the year of your date of birth.";
  if (age < minimumAge) return tooYoungMessage;
  return null;
}

export const addressSchema = z.strictObject({
  line1: text(personalLimits.line, "a street address"),
  line2: z.string().trim().max(personalLimits.line, "Address line 2 is too long.").default(""),
  city: text(personalLimits.city, "a city"),
  region: text(personalLimits.region, "a state or region"),
  postalCode: text(personalLimits.postalCode, "a ZIP or postal code"),
  /** ISO 3166-1 alpha-2, e.g. US. */
  country: z
    .string()
    .trim()
    .toUpperCase()
    .regex(/^[A-Z]{2}$/, "Choose a country.")
    .default("US"),
});
export type Address = z.output<typeof addressSchema>;

export const guardianSchema = z.strictObject({
  name: text(personalLimits.name, "your parent or guardian's name"),
  relationship: z.string().trim().max(personalLimits.relationship, "Relationship is too long.").default(""),
  email: z
    .string()
    .trim()
    .max(personalLimits.email, "That email is too long.")
    .pipe(z.email("Enter your parent or guardian's email.")),
  phone,
});
export type Guardian = z.output<typeof guardianSchema>;

/**
 * `PUT /v1/me/personal`: the whole record, replaced each time. The age
 * rules (13 and over; a guardian under 18) need today's date, so the API
 * checks them with [personalDetailsProblem] after this.
 */
export const personalDetailsSchema = z.strictObject({
  legalFirstName: text(personalLimits.name, "your legal first name"),
  legalLastName: text(personalLimits.name, "your legal last name"),
  /** YYYY-MM-DD. */
  birthDate: z.string().refine(isCalendarDate, { message: "Enter your date of birth." }),
  phone,
  gender: z.enum(genders, { message: "Choose an option." }),
  address: addressSchema,
  /** Required under 18; dropped at 18 and over. */
  guardian: guardianSchema.optional(),
});
export type PersonalDetails = z.output<typeof personalDetailsSchema>;
export type PersonalDetailsInput = z.input<typeof personalDetailsSchema>;

/**
 * The age rules on [today]: the field and message of the first problem,
 * or null. Clients show it before sending; the API enforces it.
 */
export function personalDetailsProblem(
  d: Pick<PersonalDetails, "birthDate" | "guardian">,
  today: string | Date,
): { field: string; message: string } | null {
  const birth = birthDateProblem(d.birthDate, today);
  if (birth) return { field: "birthDate", message: birth };
  if (ageOn(d.birthDate, today) < adultAge && !d.guardian) {
    return { field: "guardian", message: "Players under 18 need a parent or guardian's details." };
  }
  return null;
}

/** `GET /v1/me/personal/status`: whether they've given their details (nothing decrypted). */
export interface PersonalDetailsStatus {
  complete: boolean;
  /** Their account is new enough that the apps ask before anything else. */
  required: boolean;
}

/** `GET /v1/me/personal`: their own details, for editing. */
export interface PersonalDetailsResponse {
  details: PersonalDetails | null;
  /** The account's email (Firebase Auth), shown beside them. */
  email: string | null;
}
