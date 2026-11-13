import type { ApiErrorBody } from "@stall10/shared";
import { notFound } from "next/navigation";

/**
 * The API's address for server-side fetches: API_BASE_URL (server only),
 * else the public one the browser uses.
 */
const base = process.env.API_BASE_URL || process.env.NEXT_PUBLIC_API_BASE_URL || "http://localhost:8787";

/** Shared secret so the API skips its per-visitor limit for this server (Vercel limits visitors). */
const webKey = process.env.WEB_SERVER_KEY;

/** A public answer is reused for this long (seconds), as the API's Cache-Control allows. */
const revalidate = 60;

export class ApiUnavailable extends Error {}

/**
 * GETs a public API route (`/v1/public/...`) for a server component. A 404
 * shows the not-found page; other failures throw, so the error page shows.
 */
export async function getPublic<T>(path: string, params?: Record<string, string | number | undefined>): Promise<T> {
  const url = new URL(path, base);
  for (const [k, v] of Object.entries(params ?? {})) if (v !== undefined && v !== "") url.searchParams.set(k, String(v));
  let res: Response;
  try {
    res = await fetch(url, {
      headers: webKey ? { "x-stall10-web-key": webKey } : {},
      next: { revalidate },
    });
  } catch (e) {
    throw new ApiUnavailable(`Couldn't reach the API: ${(e as Error).message}`);
  }
  if (res.status === 404) notFound();
  if (!res.ok) {
    const body = (await res.json().catch(() => null)) as ApiErrorBody | null;
    throw new ApiUnavailable(body?.error.message ?? `The API answered ${res.status}.`);
  }
  return (await res.json()) as T;
}
