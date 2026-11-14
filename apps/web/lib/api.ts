import type { ApiErrorBody } from "@stall10/shared";
import { notFound } from "next/navigation";

/**
 * The API's address for server-side fetches: API_BASE_URL (server only),
 * else the public one the browser uses.
 */
const base = process.env.API_BASE_URL || process.env.NEXT_PUBLIC_API_BASE_URL || "http://localhost:8787";

/** Shared secret so the API skips its per-visitor limit for this server (Vercel limits visitors). */
const webKey = process.env.WEB_SERVER_KEY;

/**
 * A public answer is reused for at most this long (seconds). The API
 * expires tagged answers the moment they change (app/api/revalidate), so
 * this is only the fallback, e.g. for changes the app writes directly.
 */
const revalidate = 60;

/** Cache tags for public reads; the API sends the same ones (apps/api/src/web/revalidate.ts). */
export const tags = {
  player: (uid: string) => `player:${uid}`,
  post: (id: string) => `post:${id}`,
  posts: "posts",
  feed: "feed",
  search: "search",
} as const;

export interface PublicOptions {
  /** Cache tags, so a change can expire this answer at once. */
  tags?: string[];
}

export class ApiUnavailable extends Error {}

/**
 * GETs a public API route (`/v1/public/...`) for a server component. A 404
 * shows the not-found page; other failures throw, so the error page shows.
 */
export async function getPublic<T>(
  path: string,
  params?: Record<string, string | number | undefined>,
  opts: PublicOptions = {},
): Promise<T> {
  const found = await getPublicOrNull<T>(path, params, opts);
  if (found === null) notFound();
  return found;
}

/** As [getPublic], but null for a 404 (e.g. a private player's post, which members may still see). */
export async function getPublicOrNull<T>(
  path: string,
  params?: Record<string, string | number | undefined>,
  opts: PublicOptions = {},
): Promise<T | null> {
  const url = new URL(path, base);
  for (const [k, v] of Object.entries(params ?? {})) if (v !== undefined && v !== "") url.searchParams.set(k, String(v));
  let res: Response;
  try {
    res = await fetch(url, {
      headers: webKey ? { "x-stall10-web-key": webKey } : {},
      next: { revalidate, ...(opts.tags && { tags: opts.tags }) },
    });
  } catch (e) {
    throw new ApiUnavailable(`Couldn't reach the API: ${(e as Error).message}`);
  }
  if (res.status === 404) return null;
  if (!res.ok) {
    const body = (await res.json().catch(() => null)) as ApiErrorBody | null;
    throw new ApiUnavailable(body?.error.message ?? `The API answered ${res.status}.`);
  }
  return (await res.json()) as T;
}
