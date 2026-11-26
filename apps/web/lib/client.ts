"use client";
import { type ApiErrorBody, appCheckHeader, type PersonalDetailsStatus } from "@stall10/shared";
import type { User } from "firebase/auth";
import { announceIncomplete, missingFields } from "./accountGate";
import { appCheckToken } from "./firebase";

/** The API as the browser reaches it (CORS_ORIGINS on the API must list this site). */
export const apiBase = process.env.NEXT_PUBLIC_API_BASE_URL || "http://localhost:8787";
const base = apiBase;

export class ApiError extends Error {
  constructor(
    message: string,
    readonly status: number,
    readonly code?: string,
    readonly fields?: Record<string, string>,
  ) {
    super(message);
  }
}

/**
 * The text to show for a failed call: the API's own message, or [fallback]
 * for anything else (a thrown bug, a Firestore error).
 */
export function problem(e: unknown, fallback = "Something went wrong. Try again."): string {
  return e instanceof ApiError ? e.message : fallback;
}

const offline = () => new ApiError("Couldn't reach Stall 10. Check your connection and try again.", 0);

const statusPath = "/v1/me/personal/status";

/** The API changed this account's claims: get a token that carries them before the next write. */
async function refreshClaims(user: User): Promise<void> {
  try {
    await user.getIdToken(true);
  } catch {
    // Offline or expired: the next write is refused again and takes the retry path.
  }
}

const isIncomplete = (e: unknown): e is ApiError => e instanceof ApiError && e.status === 403 && e.code === "account_incomplete";

/**
 * Calls the API as the signed-in [user]: their Firebase ID token, and an
 * App Check token when this site has one. Answers are never cached.
 *
 * Account gate (account-gate.md section 2): a write refused with 403
 * `account_incomplete` asks the status route once; if that says the claims
 * changed, the token is refreshed and the call retried once. If it is still
 * refused, the first missing requirement is announced (lib/accountGate.ts;
 * PersonalGate shows that step) and the error is thrown. No loops: one
 * status call and one retry per call. Any answer carrying
 * `refreshToken: true` refreshes the token.
 */
export async function callApi<T>(user: User, path: string, init: { method?: string; body?: unknown } = {}): Promise<T> {
  try {
    return await callOnce<T>(user, path, init);
  } catch (e) {
    if (!isIncomplete(e) || path === statusPath) throw e;
    let told = false;
    try {
      const s = await callOnce<PersonalDetailsStatus>(user, statusPath, {});
      told = s?.refreshToken === true;
    } catch {
      // Can't tell: show the step instead.
    }
    if (told) {
      try {
        return await callOnce<T>(user, path, init);
      } catch (again) {
        if (isIncomplete(again)) announceIncomplete(missingFields(again.fields));
        throw again;
      }
    }
    announceIncomplete(missingFields(e.fields));
    throw e;
  }
}

async function callOnce<T>(user: User, path: string, init: { method?: string; body?: unknown }): Promise<T> {
  let token: string;
  try {
    token = await user.getIdToken();
  } catch (e) {
    // Offline, an expired token can't be refreshed: that's the connection, not the account.
    if ((e as { code?: string }).code === "auth/network-request-failed") throw offline();
    throw e;
  }
  const headers: Record<string, string> = { authorization: `Bearer ${token}` };
  const check = await appCheckToken();
  if (check) headers[appCheckHeader] = check;
  if (init.body !== undefined) headers["content-type"] = "application/json";
  let res: Response;
  try {
    res = await fetch(new URL(path, base), {
      method: init.method ?? "GET",
      headers,
      body: init.body === undefined ? undefined : JSON.stringify(init.body),
      cache: "no-store",
    });
  } catch {
    throw new ApiError("Couldn't reach Stall 10. Check your connection and try again.", 0);
  }
  if (!res.ok) {
    const body = (await res.json().catch(() => null)) as ApiErrorBody | null;
    throw new ApiError(body?.error.message ?? "Something went wrong. Try again.", res.status, body?.error.code, body?.error.fields);
  }
  if (res.status === 204) return undefined as T;
  const json = (await res.json()) as T;
  if (json && typeof json === "object" && (json as { refreshToken?: unknown }).refreshToken === true) await refreshClaims(user);
  return json;
}

/**
 * GETs a public route (`/v1/public/...`) from the browser: as [user] when
 * signed in (members are limited by uid, in the API's memory), else with
 * no token, as a visitor (limited by IP). The answers don't depend on who
 * asks; only the limit does.
 */
export async function getPublicApi<T>(user: User | null, path: string): Promise<T> {
  if (user) return callApi<T>(user, path);
  let res: Response;
  try {
    res = await fetch(new URL(path, base), { cache: "no-store" });
  } catch {
    throw new ApiError("Couldn't reach Stall 10. Check your connection and try again.", 0);
  }
  if (!res.ok) {
    const body = (await res.json().catch(() => null)) as ApiErrorBody | null;
    throw new ApiError(body?.error.message ?? "Something went wrong. Try again.", res.status, body?.error.code, body?.error.fields);
  }
  return (await res.json()) as T;
}
