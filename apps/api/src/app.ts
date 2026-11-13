import Fastify, { type FastifyInstance, type FastifyServerOptions } from "fastify";
import { registerAuth, type TokenVerifier, type UserLookup } from "./auth.js";
import { registerCors } from "./cors.js";
import { errorHandler } from "./errors.js";
import type { BrowseRepository } from "./browse/repository.js";
import { browseRoutes } from "./browse/routes.js";
import { BrowseService } from "./browse/service.js";
import type { MeRepository } from "./me/repository.js";
import { meRoutes } from "./me/routes.js";
import { MeService } from "./me/service.js";
import type { RateLimiter } from "./limits/limiter.js";
import { type LoggerOptions, traceLoggerFactory } from "./logging.js";
import type { HeicDecoder } from "./media/image.js";
import { uploadRoutes } from "./media/routes.js";
import { type TranscodeQueue, UploadService } from "./media/service.js";
import type { MediaStorage } from "./media/storage.js";
import { followRoutes } from "./follows/routes.js";
import { FollowService } from "./follows/service.js";
import { PostEditor } from "./posts/editor.js";
import { postEditorRoutes, postRoutes } from "./posts/routes.js";
import { PostService } from "./posts/service.js";
import { profileRoutes } from "./profiles/routes.js";
import { ProfileService } from "./profiles/service.js";
import type { DocStore } from "./store.js";
import { MembershipService } from "./teams/membership.js";
import { membershipRoutes } from "./teams/membership_routes.js";
import type { TeamRepository } from "./teams/repository.js";
import { teamRoutes } from "./teams/routes.js";
import { TeamService } from "./teams/service.js";
import { apiVersion, versionHeader } from "./version.js";

export interface AppDeps {
  verifier: TokenVerifier;
  users: UserLookup;
  teams: TeamRepository;
  /** The website's public reads (`/v1/public/*`); off when not given. */
  /** The signed-in member's dashboard (`/v1/me/home`); off when not given. */
  me?: { repo: MeRepository; imageUrl: (path: string) => string };
  browse?: {
    repo: BrowseRepository;
    limiter: RateLimiter;
    imageUrl: (path: string) => string;
    webServerKey?: string;
  };
  /** Transactional document access; enables the membership, profile and post routes. */
  store?: DocStore;
  /** Cloud Storage; with [store], enables /v1/uploads. */
  media?: MediaStorage;
  heic?: HeicDecoder;
  transcodeQueue?: TranscodeQueue;
  enforceAppCheck?: boolean;
  /** true for Fastify's default logger, or pino options (cloudLoggingOptions). */
  logger?: boolean | LoggerOptions;
  now?: () => number;
  /** Origins browsers may call from (CORS_ORIGINS); none when omitted. */
  corsOrigins?: string[];
  /** Fastify's trustProxy; on Cloud Run, [trustHops] (server.ts). */
  trustProxy?: FastifyServerOptions["trustProxy"];
  /** Throws while the instance can't serve; GET /ready then answers 503. */
  ready?: () => Promise<void>;
  /** Groups request logs by Cloud Trace (X-Cloud-Trace-Context) when set. */
  traceProjectId?: string;
}

/**
 * Trusts the last [hops] entries of X-Forwarded-For. Fastify's own
 * hop-count setting trusts nothing (it can't check the peer), but a Cloud
 * Run instance is only reachable through Google's front end, which appends
 * the caller's address: one hop. Anything left of it came from the client.
 */
export function trustHops(hops: number): (address: string, hop: number) => boolean {
  return (_address, hop) => hop < hops;
}

/** Builds the API. server.ts wires Firebase in; tests pass fakes. */
export function buildApp(deps: AppDeps): FastifyInstance {
  const app = Fastify({
    logger: deps.logger ?? false,
    trustProxy: deps.trustProxy ?? false,
    ...(deps.traceProjectId && { childLoggerFactory: traceLoggerFactory(deps.traceProjectId) }),
    // Requests are small JSON; media goes straight to Storage (signed URLs).
    bodyLimit: 64 * 1024,
  });
  app.setErrorHandler(errorHandler);
  app.setNotFoundHandler((_req, reply) =>
    reply.status(404).send({ error: { code: "not_found", message: "No such endpoint." } }),
  );

  // onRequest hooks run in the order they're added, and one that answers
  // ends the request: readiness probes and CORS preflights never reach auth.
  app.addHook("onRequest", async (req, reply) => {
    if (req.method !== "GET" || req.url !== "/ready") return;
    try {
      await deps.ready?.();
      return reply.send({ ok: true });
    } catch (err) {
      req.log.warn({ err }, "not ready");
      return reply.status(503).send({ ok: false });
    }
  });
  registerCors(app, deps.corsOrigins ?? []);
  registerAuth(app, deps.verifier, deps.enforceAppCheck ?? false);

  // Every answer says which API version gave it, for tracking changes.
  app.addHook("onSend", async (_req, reply) => {
    reply.header(versionHeader, apiVersion);
  });
  app.get("/health", async () => ({ ok: true, version: apiVersion }));
  teamRoutes(app, new TeamService(deps.teams, deps.users, deps.now));
  if (deps.me) meRoutes(app, new MeService(deps.me.repo, deps.me.imageUrl, deps.now));
  if (deps.browse) browseRoutes(app, new BrowseService(deps.browse.repo, deps.browse.imageUrl, deps.now), deps.browse);
  if (deps.store) {
    membershipRoutes(app, new MembershipService(deps.store, deps.users, deps.teams, deps.now));
    profileRoutes(app, new ProfileService(deps.store, deps.users));
    postRoutes(app, new PostService(deps.store, deps.users, deps.now));
    postEditorRoutes(app, new PostEditor(deps.store, deps.users, deps.media, deps.now));
    followRoutes(app, new FollowService(deps.store, deps.users, deps.now));
    if (deps.media) {
      const uploads = new UploadService(deps.store, deps.media, { heic: deps.heic, queue: deps.transcodeQueue, now: deps.now });
      uploadRoutes(app, uploads);
    }
  }
  return app;
}
