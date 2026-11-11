import Fastify, { type FastifyInstance } from "fastify";
import { registerAuth, type TokenVerifier, type UserLookup } from "./auth.js";
import { errorHandler } from "./errors.js";
import type { BrowseRepository } from "./browse/repository.js";
import { browseRoutes } from "./browse/routes.js";
import { BrowseService } from "./browse/service.js";
import type { RateLimiter } from "./limits/limiter.js";
import type { TeamRepository } from "./teams/repository.js";
import { teamRoutes } from "./teams/routes.js";
import { TeamService } from "./teams/service.js";

export interface AppDeps {
  verifier: TokenVerifier;
  users: UserLookup;
  teams: TeamRepository;
  /** The website's public reads (`/v1/public/*`); off when not given. */
  browse?: {
    repo: BrowseRepository;
    limiter: RateLimiter;
    imageUrl: (path: string) => string;
    webServerKey?: string;
  };
  enforceAppCheck?: boolean;
  logger?: boolean;
  now?: () => number;
}

/** Builds the API. server.ts wires Firebase in; tests pass fakes. */
export function buildApp(deps: AppDeps): FastifyInstance {
  const app = Fastify({
    logger: deps.logger ?? false,
    // Requests are small JSON; media goes straight to Storage (signed URLs).
    bodyLimit: 64 * 1024,
  });
  app.setErrorHandler(errorHandler);
  app.setNotFoundHandler((_req, reply) =>
    reply.status(404).send({ error: { code: "not_found", message: "No such endpoint." } }),
  );
  registerAuth(app, deps.verifier, deps.enforceAppCheck ?? false);

  app.get("/health", async () => ({ ok: true }));
  teamRoutes(app, new TeamService(deps.teams, deps.users, deps.now));
  if (deps.browse) browseRoutes(app, new BrowseService(deps.browse.repo, deps.browse.imageUrl, deps.now), deps.browse);
  return app;
}
