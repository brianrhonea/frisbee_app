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
  "resource_exhausted",
  "internal",
] as const;
export type ApiErrorCode = (typeof apiErrorCodes)[number];

export const apiErrorStatus: Record<ApiErrorCode, number> = {
  invalid_argument: 400,
  unauthenticated: 401,
  permission_denied: 403,
  not_found: 404,
  already_exists: 409,
  failed_precondition: 412,
  resource_exhausted: 429,
  internal: 500,
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
