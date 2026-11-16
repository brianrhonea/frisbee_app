import { teamSearchQuerySchema } from "@stall10/shared";
import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import { requireCaller } from "../auth.js";
import { ApiError } from "../errors.js";
import type { RateLimiter } from "../limits/limiter.js";
import { MemoryRateLimiter } from "../limits/memory.js";
import { browseLimit } from "../limits/model.js";
import { visitorAdmitter, webKeyHeader } from "./admit.js";
import type { RosterService } from "../teams/roster.js";
import type { BrowseService } from "./service.js";

/** Header the website's server sends with [BrowseOptions.webServerKey]. */
export { webKeyHeader };

export interface BrowseOptions {
  limiter: RateLimiter;
  /**
   * Shared secret of the website's server (WEB_SERVER_KEY). Its requests
   * skip the per-visitor limit: they all come from Vercel's addresses, and
   * visitors are limited at Vercel's firewall, where their IP is known.
   */
  webServerKey?: string;
  /** Adult teams' rosters for anyone (`/v1/public/teams/:id/roster`); off when not given. */
  roster?: RosterService;
}

/** Short shared caching: a profile turned private drops out within a minute. */
const cacheControl = "public, max-age=30, s-maxage=60, stale-while-revalidate=60";
// Behind a sign-in: never cached, so a second account in the same browser
// can't be shown the first one's answer.
const memberCacheControl = "private, no-store";

export function browseRoutes(app: FastifyInstance, browse: BrowseService, opts: BrowseOptions) {
  // Members are counted in memory: the shared limiter's mute
  // (limits/{uid}.mutedUntil) would also stop their chat and posts.
  const members = new MemoryRateLimiter();
  const tooMany = () => new ApiError("resource_exhausted", "Too many requests. Try again in a few minutes.");

  const admit = visitorAdmitter(opts);

  /**
   * Signed-in members only, with App Check as on other member routes (visitors don't see players): player
   * profiles and search across players and teams. Each member
   * is limited by uid, so the website's server key doesn't let anyone in.
   */
  async function admitMember(req: FastifyRequest) {
    if (!members.admit(requireCaller(req).uid, browseLimit)) throw tooMany();
  }

  const send = (reply: FastifyReply, body: unknown) => reply.header("cache-control", cacheControl).send(body);
  const sendPrivate = (reply: FastifyReply, body: unknown) => reply.header("cache-control", memberCacheControl).send(body);
  const config = { public: true };
  type Q = { Querystring: Record<string, string | undefined>; Params: Record<string, string> };

  app.get<Q>("/v1/public/feed", { config }, async (req, reply) => {
    await admit(req);
    return send(reply, await browse.feed());
  });

  // Members page through the community feed (visitors get one page above).
  app.get<Q>("/v1/feed", async (req, reply) => {
    requireCaller(req);
    const before = req.query.before === undefined ? undefined : Number(req.query.before);
    return reply.header("cache-control", "private, no-store").send(await browse.feedPage(before));
  });

  app.get<Q>("/v1/public/posts/:id", { config }, async (req, reply) => {
    await admit(req);
    return send(reply, await browse.onePost(req.params.id));
  });

  app.get<Q>("/v1/public/players/:uid", async (req, reply) => {
    await admitMember(req);
    return sendPrivate(reply, await browse.profile(req.params.uid));
  });

  // The team finder: listings only, never players.
  app.get<Q>("/v1/public/teams", { config }, async (req, reply) => {
    await admit(req);
    const query = teamSearchQuerySchema.safeParse({ q: req.query.q });
    if (!query.success) throw new ApiError("invalid_argument", query.error.issues[0]?.message ?? "Invalid search.");
    return send(reply, await browse.teams(query.data.q));
  });

  app.get<Q>("/v1/public/teams/:id", { config }, async (req, reply) => {
    await admit(req);
    return send(reply, await browse.team(req.params.id));
  });

  const roster = opts.roster;
  if (roster) {
    app.get<Q>("/v1/public/teams/:id/roster", { config }, async (req, reply) => {
      await admit(req);
      return send(reply, await roster.publicRoster(req.params.id));
    });
  }

  // Public team events and group tournaments, as team pages show them to visitors.
  app.get<Q>("/v1/public/events", { config }, async (req, reply) => {
    await admit(req);
    return send(reply, await browse.events());
  });

  app.get<Q>("/v1/public/search", async (req, reply) => {
    await admitMember(req);
    return sendPrivate(reply, await browse.search(req.query.q));
  });
}
