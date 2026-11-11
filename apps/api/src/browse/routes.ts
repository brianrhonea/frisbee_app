import { timingSafeEqual } from "node:crypto";
import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import { ApiError } from "../errors.js";
import type { RateLimiter } from "../limits/limiter.js";
import { browseLimit } from "../limits/model.js";
import { clientIp, visitorKey } from "./model.js";
import type { BrowseService } from "./service.js";

/** Header the website's server sends with [BrowseOptions.webServerKey]. */
export const webKeyHeader = "x-stall10-web-key";

export interface BrowseOptions {
  limiter: RateLimiter;
  /**
   * Shared secret of the website's server (WEB_SERVER_KEY). Its requests
   * skip the per-visitor limit: they all come from Vercel's addresses, and
   * visitors are limited at Vercel's firewall, where their IP is known.
   */
  webServerKey?: string;
}

/** Short shared caching: a profile turned private drops out within a minute. */
const cacheControl = "public, max-age=30, s-maxage=60, stale-while-revalidate=60";

function sameSecret(a: string, b: string): boolean {
  const x = Buffer.from(a);
  const y = Buffer.from(b);
  return x.length === y.length && timingSafeEqual(x, y);
}

export function browseRoutes(app: FastifyInstance, browse: BrowseService, opts: BrowseOptions) {
  async function admit(req: FastifyRequest) {
    const sent = req.headers[webKeyHeader];
    if (opts.webServerKey && typeof sent === "string" && sameSecret(sent, opts.webServerKey)) return;
    const key = req.caller?.uid ?? visitorKey(clientIp(req.headers["x-forwarded-for"], req.ip));
    if (!(await opts.limiter.admit(key, browseLimit))) {
      throw new ApiError("resource_exhausted", "Too many requests. Try again in a few minutes.");
    }
  }

  const send = (reply: FastifyReply, body: unknown) => reply.header("cache-control", cacheControl).send(body);
  const config = { public: true };
  type Q = { Querystring: Record<string, string | undefined>; Params: Record<string, string> };

  app.get<Q>("/v1/public/feed", { config }, async (req, reply) => {
    await admit(req);
    return send(reply, await browse.feed());
  });

  app.get<Q>("/v1/public/posts/:id", { config }, async (req, reply) => {
    await admit(req);
    return send(reply, await browse.onePost(req.params.id));
  });

  app.get<Q>("/v1/public/players/:uid", { config }, async (req, reply) => {
    await admit(req);
    return send(reply, await browse.profile(req.params.uid));
  });

  app.get<Q>("/v1/public/teams/:id", { config }, async (req, reply) => {
    await admit(req);
    return send(reply, await browse.team(req.params.id));
  });

  app.get<Q>("/v1/public/events", { config }, async (req, reply) => {
    await admit(req);
    return send(reply, await browse.events());
  });

  app.get<Q>("/v1/public/search", { config }, async (req, reply) => {
    await admit(req);
    return send(reply, await browse.search(req.query.q));
  });
}
