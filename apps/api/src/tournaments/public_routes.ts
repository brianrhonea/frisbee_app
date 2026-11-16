// Visitors' tournament pages over HTTP (PublicTournamentService): no token
// needed, limited per visitor like the other `/v1/public/*` reads, and
// cached publicly for a short time.
import { timingSafeEqual } from "node:crypto";
import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import { clientIp, visitorKey } from "../browse/model.js";
import { webKeyHeader } from "../browse/routes.js";
import { ApiError } from "../errors.js";
import type { RateLimiter } from "../limits/limiter.js";
import { MemoryRateLimiter } from "../limits/memory.js";
import { browseLimit } from "../limits/model.js";
import type { PublicTournamentService } from "./public_service.js";

export interface PublicTournamentOptions {
  /** The visitors' limiter (the browse routes' one). */
  limiter: RateLimiter;
  /** The website server's shared secret (WEB_SERVER_KEY): its requests skip the per-visitor limit. */
  webServerKey?: string;
}

/** Scores change during play, so only briefly cached; the website rereads them every minute. */
export const publicTournamentCacheControl = "public, max-age=30, s-maxage=30, stale-while-revalidate=30";

function sameSecret(a: string, b: string): boolean {
  const x = Buffer.from(a);
  const y = Buffer.from(b);
  return x.length === y.length && timingSafeEqual(x, y);
}

export function publicTournamentRoutes(app: FastifyInstance, svc: PublicTournamentService, opts: PublicTournamentOptions) {
  // Members are counted in memory, as on the browse routes: the shared
  // limiter's mute would also stop their chat and posts.
  const members = new MemoryRateLimiter();
  const tooMany = () => new ApiError("resource_exhausted", "Too many requests. Try again in a few minutes.");

  async function admit(req: FastifyRequest) {
    const sent = req.headers[webKeyHeader];
    if (opts.webServerKey && typeof sent === "string" && sameSecret(sent, opts.webServerKey)) return;
    if (req.caller) {
      if (!members.admit(req.caller.uid, browseLimit)) throw tooMany();
      return;
    }
    if (!(await opts.limiter.admit(visitorKey(clientIp(req.headers["x-forwarded-for"], req.ip)), browseLimit))) throw tooMany();
  }

  const send = (reply: FastifyReply, body: unknown) => reply.header("cache-control", publicTournamentCacheControl).send(body);
  const config = { public: true };
  type Q = { Querystring: Record<string, string | undefined>; Params: Record<string, string> };

  app.get<Q>("/v1/public/tournaments", { config }, async (req, reply) => {
    await admit(req);
    return send(reply, await svc.list());
  });

  app.get<Q>("/v1/public/tournaments/:id", { config }, async (req, reply) => {
    await admit(req);
    return send(reply, await svc.page(req.params.id, req.query));
  });

  app.get<Q>("/v1/public/group-tournaments/:groupId/:id", { config }, async (req, reply) => {
    await admit(req);
    return send(reply, await svc.groupTournament(req.params.groupId, req.params.id));
  });
}
