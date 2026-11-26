// The API's wire contract shared by apps/api, apps/web and (by hand)
// apps/mobile/lib/data/services/api_client.dart.

/** Machine-readable error codes. The app shows `message` as-is. */
export const apiErrorCodes = [
  "invalid_argument",
  "unauthenticated",
  "permission_denied",
  "not_found",
  "already_exists",
  "failed_precondition",
  /**
   * The account can read but not write yet: its email isn't verified, no
   * adult birth date is saved, or the Terms aren't agreed
   * (account_gate.ts; `fields` names what is missing).
   */
  "account_incomplete",
  "resource_exhausted",
  "internal",
  /** A service the API depends on (Discord, say) can't be reached; try again later. */
  "unavailable",
] as const;
export type ApiErrorCode = (typeof apiErrorCodes)[number];

export const apiErrorStatus: Record<ApiErrorCode, number> = {
  invalid_argument: 400,
  unauthenticated: 401,
  permission_denied: 403,
  not_found: 404,
  already_exists: 409,
  failed_precondition: 412,
  account_incomplete: 403,
  resource_exhausted: 429,
  internal: 500,
  unavailable: 503,
};

/** Every non-2xx response body. */
export interface ApiErrorBody {
  error: {
    code: ApiErrorCode;
    message: string;
    /** Per-field messages for invalid_argument. */
    fields?: Record<string, string>;
  };
}

/** Header carrying the Firebase App Check token, as callables use. */
export const appCheckHeader = "x-firebase-appcheck";
