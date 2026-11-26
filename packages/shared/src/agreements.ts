// Agreeing to the Community Guidelines and Terms of Service: every member
// does, once per version, before using Stall 10 (onboarding on new
// accounts; existing members see the same step on their next visit). The
// API records it in users/{uid}.agreedTerms. Bump [termsVersion] when the
// terms or guidelines change in a way members must agree to again.
import { z } from "zod";

/** The current version of the terms and guidelines members agree to. */
export const termsVersion = 1;

/** `GET` (status) and `PUT` (agree) the caller's agreement. */
export const agreementPath = "/v1/me/agreement";

/** `PUT /v1/me/agreement`: the version the member read and agreed to. */
export const agreementRequestSchema = z.object({ version: z.number().int().positive() }).strict();
export type AgreementRequest = z.infer<typeof agreementRequestSchema>;

/** `GET /v1/me/agreement`: whether they've agreed to the current version. */
export interface AgreementStatus {
  agreed: boolean;
  /** What they must agree to: [termsVersion]. */
  version: number;
  /** After `PUT`: the API changed this account's claims; call `getIdToken(true)` before the next write. */
  refreshToken?: true;
}

/** Whether a stored agreement (users/{uid}.agreedTerms) covers the current version. */
export function hasAgreed(stored: unknown): boolean {
  const v = (stored as { version?: unknown } | null | undefined)?.version;
  return typeof v === "number" && v >= termsVersion;
}

/** The step's summary of the guidelines, the same on both platforms. */
export const agreementPoints = [
  "Be respectful: no harassment, hate or threats.",
  "Keep it clean: no sexual, violent or illegal content, and nothing that puts a young player at risk.",
  "Be yourself: no impersonation, spam or scams.",
  "Report what breaks the rules; we and team admins review every report.",
] as const;
