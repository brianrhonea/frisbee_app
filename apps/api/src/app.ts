import Fastify, { type FastifyInstance } from "fastify";
import { registerAuth, type TokenVerifier, type UserLookup } from "./auth.js";
import { errorHandler } from "./errors.js";
import type { HeicDecoder } from "./media/image.js";
import { uploadRoutes } from "./media/routes.js";
import { type TranscodeQueue, UploadService } from "./media/service.js";
import type { MediaStorage } from "./media/storage.js";
import { profileRoutes } from "./profiles/routes.js";
import { ProfileService } from "./profiles/service.js";
import type { DocStore } from "./store.js";
import { MembershipService } from "./teams/membership.js";
import { membershipRoutes } from "./teams/membership_routes.js";
import type { TeamRepository } from "./teams/repository.js";
import { teamRoutes } from "./teams/routes.js";
import { TeamService } from "./teams/service.js";

export interface AppDeps {
  verifier: TokenVerifier;
  users: UserLookup;
  teams: TeamRepository;
  /** Transactional document access; enables the membership and profile routes. */
  store?: DocStore;
  /** Cloud Storage; with [store], enables /v1/uploads. */
  media?: MediaStorage;
  heic?: HeicDecoder;
  transcodeQueue?: TranscodeQueue;
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
  if (deps.store) {
    membershipRoutes(app, new MembershipService(deps.store, deps.users, deps.teams, deps.now));
    profileRoutes(app, new ProfileService(deps.store, deps.users));
    if (deps.media) {
      const uploads = new UploadService(deps.store, deps.media, { heic: deps.heic, queue: deps.transcodeQueue, now: deps.now });
      uploadRoutes(app, uploads);
    }
  }
  return app;
}
