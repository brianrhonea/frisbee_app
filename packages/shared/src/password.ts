// The rules for new passwords (the app's PasswordPolicy,
// apps/mobile/lib/utils/password_policy.dart), checked on sign-up and on
// changing a password before Firebase sees them. Keep the two in step.

export const passwordMinLength = 8;

/** Long enough for a passphrase; Firebase allows more, but nobody types it. */
export const passwordMaxLength = 128;

export type PasswordStrength = "weak" | "fair" | "good" | "strong";

export const passwordStrengthLabels: Record<PasswordStrength, string> = {
  weak: "Weak",
  fair: "Fair",
  good: "Good",
  strong: "Strong",
};

const letter = /[A-Za-z]/;
const lower = /[a-z]/;
const upper = /[A-Z]/;
const digit = /[0-9]/;
const symbol = /[^A-Za-z0-9]/;

/** Passwords people pick first; never more than weak. */
const common = new Set([
  "password",
  "password1",
  "password123",
  "passw0rd",
  "qwerty123",
  "abc12345",
  "abcd1234",
  "iloveyou1",
  "letmein1",
  "welcome1",
  "frisbee1",
  "ultimate1",
  "12345678a",
  "a12345678",
]);

/** The requirements, each with whether [password] meets it, for the checklist under the field. */
export function passwordChecklist(password: string): Array<{ label: string; met: boolean }> {
  return [
    { label: `${passwordMinLength}+ characters`, met: password.length >= passwordMinLength },
    { label: "A letter", met: letter.test(password) },
    { label: "A number", met: digit.test(password) },
  ];
}

/** What's wrong with [password], or null when it's acceptable. */
export function passwordProblem(password: string): string | null {
  if (password.length < passwordMinLength) return `At least ${passwordMinLength} characters`;
  if (password.length > passwordMaxLength) return `At most ${passwordMaxLength} characters`;
  if (password.trim() !== password) return "Can't start or end with a space";
  if (!letter.test(password) || !digit.test(password)) return "Use at least one letter and one number";
  if (common.has(password.toLowerCase())) return "Too common. Pick something harder to guess";
  return null;
}

/** A rough strength from length and variety. Anything that fails [passwordProblem] is weak. */
export function passwordStrength(password: string): PasswordStrength {
  if (passwordProblem(password) !== null) return "weak";
  let score = 0;
  if (password.length >= 12) score++;
  if (password.length >= 16) score++;
  if (lower.test(password) && upper.test(password)) score++;
  if (symbol.test(password)) score++;
  // The same character over and over adds little.
  if (new Set(password.split("")).size < password.length / 2) score--;
  return score <= 0 ? "fair" : score <= 2 ? "good" : "strong";
}
