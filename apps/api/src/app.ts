import Fastify, { type FastifyInstance, type FastifyServerOptions } from "fastify";
import { registerAuth, type TokenVerifier, type UserLookup } from "./auth.js";
import { registerCors } from "./cors.js";
import { errorHandler } from "./errors.js";
import { type LoggerOptions, traceLoggerFactory } from "./logging.js";
import type { TeamRepository } from "./teams/repository.js";
import { teamRoutes } from "./teams/routes.js";
import { TeamService } from "./teams/service.js";

export interface AppDeps {
  verifier: TokenVerifier;
  users: UserLookup;
  teams: TeamRepository;
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

  app.get("/health", async () => ({ ok: true }));
  teamRoutes(app, new TeamService(deps.teams, deps.users, deps.now));
  return app;
}
