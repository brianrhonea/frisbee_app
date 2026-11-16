// Who may read a `/v1/public/*` route, shared by the browse and the public
// tournament routes: the website's server (its shared key), a signed-in
// member (counted in memory by uid) or a visitor (counted by IP).
import { timingSafeEqual } from "node:crypto";
import type { FastifyRequest } from "fastify";
import { ApiError } from "../errors.js";
import type { RateLimiter } from "../limits/limiter.js";
import { MemoryRateLimiter } from "../limits/memory.js";
import { browseLimit } from "../limits/model.js";
import { visitorKey } from "./model.js";

/** Header the website's server sends with its shared secret (WEB_SERVER_KEY). */
export const webKeyHeader = "x-stall10-web-key";

function sameSecret(a: string, b: string): boolean {
  const x = Buffer.from(a);
  const y = Buffer.from(b);
  return x.length === y.length && timingSafeEqual(x, y);
}

/**
 * A visitor's IP: Fastify's `req.ip`, which trusts only the proxies in
 * front of the API (TRUST_PROXY_HOPS, so on Cloud Run the address its
 * front end appended). Never the first X-Forwarded-For hop: the client
 * writes that, and could take a fresh bucket per request or spend
 * someone else's.
 */
export const visitorIp = (req: FastifyRequest): string => req.ip || "unknown";

export const tooManyRequests = () => new ApiError("resource_exhausted", "Too many requests. Try again in a few minutes.");

export function visitorAdmitter(opts: { limiter: RateLimiter; webServerKey?: string }) {
  // Members are counted in memory: the shared limiter's mute
  // (limits/{uid}.mutedUntil) would also stop their chat and posts.
  const members = new MemoryRateLimiter();
  return async function admit(req: FastifyRequest): Promise<void> {
    const sent = req.headers[webKeyHeader];
    if (opts.webServerKey && typeof sent === "string" && sameSecret(sent, opts.webServerKey)) return;
    if (req.caller) {
      if (!members.admit(req.caller.uid, browseLimit)) throw tooManyRequests();
      return;
    }
    if (!(await opts.limiter.admit(visitorKey(visitorIp(req)), browseLimit))) throw tooManyRequests();
  };
}
