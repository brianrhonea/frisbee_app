import type { FastifyInstance, FastifyRequest } from "fastify";
import { type Caller, requireCaller } from "../auth.js";
import { limited, type MemoryRateLimiter } from "../limits/memory.js";
import type { MeService } from "./service.js";

/**
 * Per member, per instance: the home feed fans out to many queries (up to
 * 300 follows of each kind), so its reads are capped like writes are.
 */
export const meReadLimits = {
  home: { max: 60, windowMs: 60_000 },
  page: { max: 120, windowMs: 60_000 },
};

export function meRoutes(app: FastifyInstance, me: MeService, limiter?: MemoryRateLimiter) {
  const caller = (req: FastifyRequest, bucket: keyof typeof meReadLimits): Caller => {
    const c = requireCaller(req);
    limited(limiter, `me-${bucket}:${c.uid}`, meReadLimits[bucket]);
    return c;
  };
  app.get<{ Querystring: { before?: string } }>("/v1/me/home", async (req, reply) => {
    const c = caller(req, "home");
    const before = req.query.before === undefined ? undefined : Number(req.query.before);
    // Per person: never stored by a shared cache.
    return reply.header("cache-control", "private, no-store").send(await me.home(c, before));
  });
  // Others' pages as this member sees them (a private profile they follow
  // in full); the website reads these live, so never cached.
  app.get<{ Params: { uid: string }; Querystring: { before?: string } }>("/v1/players/:uid", async (req, reply) => {
    const c = caller(req, "page");
    const before = req.query.before === undefined ? undefined : Number(req.query.before);
    return reply.header("cache-control", "private, no-store").send(await me.player(c, req.params.uid, before));
  });
  app.get<{ Params: { id: string } }>("/v1/posts/:id", async (req, reply) => {
    const c = caller(req, "page");
    return reply.header("cache-control", "private, no-store").send(await me.onePost(c, req.params.id));
  });
}
