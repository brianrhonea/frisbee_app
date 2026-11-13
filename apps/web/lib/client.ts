"use client";
import { type ApiErrorBody, appCheckHeader } from "@stall10/shared";
import type { User } from "firebase/auth";
import { appCheckToken } from "./firebase";

/** The API as the browser reaches it (CORS_ORIGINS on the API must list this site). */
const base = process.env.NEXT_PUBLIC_API_BASE_URL || "http://localhost:8787";

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

/** GETs a public API route (`/v1/public/...`) from the browser; null if it fails. */
export async function getPublicInBrowser<T>(path: string): Promise<T | null> {
  try {
    const res = await fetch(new URL(path, base));
    return res.ok ? ((await res.json()) as T) : null;
  } catch {
    return null;
  }
}

/**
 * Calls the API as the signed-in [user]: their Firebase ID token, and an
 * App Check token when this site has one. Answers are never cached.
 */
export async function callApi<T>(user: User, path: string, init: { method?: string; body?: unknown } = {}): Promise<T> {
  const headers: Record<string, string> = { authorization: `Bearer ${await user.getIdToken()}` };
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
  return (await res.json()) as T;
}
