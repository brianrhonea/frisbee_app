// Tells the website to drop its cached public pages the moment what they
// show changes (a profile goes private, a post is edited or deleted), so
// visitors never wait out the cache. The website's /api/revalidate expires
// the tagged answers at once (revalidateTag with expire 0).

import type { FastifyBaseLogger } from "fastify";

/** Cache tags of the website's public reads (apps/web/lib/api.ts uses the same). */
export const webTags = {
  player: (uid: string) => `player:${uid}`,
  post: (id: string) => `post:${id}`,
  /** Every post page: a profile going private hides all of its posts. */
  posts: "posts",
  feed: "feed",
  search: "search",
} as const;

/** Expires website cache tags; never throws (the write it follows already happened). */
export type Revalidate = (tags: string[], log?: FastifyBaseLogger) => Promise<void>;

/** Header carrying the shared WEB_SERVER_KEY (the same one /v1/public reads use). */
export const webKeyHeader = "x-stall10-web-key";

/**
 * Posts [tags] to `{siteUrl}/api/revalidate`. Awaited, with a short
 * timeout: Cloud Run throttles CPU after the reply, so a call left running
 * after it might never be made.
 */
export function webRevalidator(
  siteUrl: string,
  key: string,
  opts: { fetch?: typeof fetch; timeoutMs?: number } = {},
): Revalidate {
  const send = opts.fetch ?? fetch;
  const url = new URL("/api/revalidate", siteUrl).toString();
  const timeoutMs = opts.timeoutMs ?? 1500;
  return async (tags, log) => {
    const unique = [...new Set(tags)];
    if (unique.length === 0) return;
    try {
      const res = await send(url, {
        method: "POST",
        headers: { "content-type": "application/json", [webKeyHeader]: key },
        body: JSON.stringify({ tags: unique }),
        signal: AbortSignal.timeout(timeoutMs),
      });
      if (!res.ok) log?.warn({ status: res.status, tags: unique }, "Website revalidate refused");
    } catch (e) {
      log?.warn({ err: String(e), tags: unique }, "Website revalidate failed");
    }
  };
}

/** Does nothing: no website configured (local runs, tests). */
export const noRevalidate: Revalidate = async () => undefined;
