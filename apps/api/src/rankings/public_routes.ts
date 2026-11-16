// Visitors' rankings over HTTP (PublicRankingService): no token needed,
// limited per visitor like the other `/v1/public/*` reads, and cached
// publicly for a short time.
import type { FastifyInstance } from "fastify";
import { visitorAdmitter } from "../browse/admit.js";
import type { RateLimiter } from "../limits/limiter.js";
import type { PublicRankingService } from "./public_service.js";

export interface PublicRankingOptions {
  /** The visitors' limiter (the browse routes' one). */
  limiter: RateLimiter;
  /** The website server's shared secret (WEB_SERVER_KEY): its requests skip the per-visitor limit. */
  webServerKey?: string;
}

/** Rankings change nightly: a minute in browsers, five at the edge. */
export const publicRankingsCacheControl = "public, max-age=60, s-maxage=300, stale-while-revalidate=300";

export function publicRankingRoutes(app: FastifyInstance, svc: PublicRankingService, opts: PublicRankingOptions) {
  const admit = visitorAdmitter(opts);

  app.get("/v1/public/rankings", { config: { public: true } }, async (req, reply) => {
    await admit(req);
    return reply.header("cache-control", publicRankingsCacheControl).send(await svc.list());
  });
}
