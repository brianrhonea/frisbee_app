// Visitors' tournament pages over HTTP (PublicTournamentService): no token
// needed, limited per visitor like the other `/v1/public/*` reads, and
// cached publicly for a short time.
import type { FastifyInstance, FastifyReply } from "fastify";
import { visitorAdmitter } from "../browse/admit.js";
import type { RateLimiter } from "../limits/limiter.js";
import type { PublicTournamentService } from "./public_service.js";

export interface PublicTournamentOptions {
  /** The visitors' limiter (the browse routes' one). */
  limiter: RateLimiter;
  /** The website server's shared secret (WEB_SERVER_KEY): its requests skip the per-visitor limit. */
  webServerKey?: string;
}

/** Scores change during play, so only briefly cached; the website rereads them every minute. */
export const publicTournamentCacheControl = "public, max-age=30, s-maxage=30, stale-while-revalidate=30";

export function publicTournamentRoutes(app: FastifyInstance, svc: PublicTournamentService, opts: PublicTournamentOptions) {
  const admit = visitorAdmitter(opts);

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
