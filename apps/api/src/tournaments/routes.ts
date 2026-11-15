// Hosted tournaments and leagues over HTTP (TournamentService), as the
// signed-in caller, under the hub's write limit.
import type { FastifyInstance, FastifyRequest } from "fastify";
import { type Caller, requireCaller } from "../auth.js";
import { ApiError } from "../errors.js";
import { hubLimits } from "../hub/routes.js";
import type { MemoryRateLimiter } from "../limits/memory.js";
import type { TournamentService } from "./service.js";

/**
 * A published schedule's body: up to tournamentLimits.maxGames (2,100)
 * games of at most about 900 bytes of JSON each (two 128-character team
 * ids and sources, a 60-character label), past the API's 64 KB default.
 */
const scheduleBodyLimit = 2 * 1024 * 1024;

export function tournamentRoutes(app: FastifyInstance, svc: TournamentService, limiter: MemoryRateLimiter) {
  const caller = (req: FastifyRequest): Caller => {
    const c = requireCaller(req);
    if (!limiter.admit(`write:${c.uid}`, hubLimits.write)) {
      throw new ApiError("resource_exhausted", "You're doing that too fast. Wait a minute and try again.");
    }
    return c;
  };
  type T = { Params: { id: string } };
  type D = { Params: { id: string; divisionId: string } };
  type E = { Params: { id: string; teamId: string } };
  type G = { Params: { id: string; divisionId: string; gameId: string } };
  const base = "/v1/tournaments/:id";
  const div = `${base}/divisions/:divisionId`;
  const game = `${div}/games/:gameId`;

  app.post("/v1/tournaments", async (req, reply) => reply.code(201).send(await svc.create(caller(req), req.body)));
  app.patch<T>(base, async (req, reply) => {
    await svc.save(caller(req), req.params.id, req.body);
    return reply.code(204).send();
  });
  app.delete<T>(base, async (req, reply) => {
    await svc.remove(caller(req), req.params.id);
    return reply.code(204).send();
  });
  app.put<T>(`${base}/status`, async (req, reply) => {
    await svc.setStatus(caller(req), req.params.id, req.body);
    return reply.code(204).send();
  });

  app.delete<D>(div, async (req, reply) => {
    await svc.removeDivision(caller(req), req.params.id, req.params.divisionId);
    return reply.code(204).send();
  });
  app.put<D>(`${div}/seeds`, async (req, reply) => {
    await svc.saveSeeds(caller(req), req.params.id, req.params.divisionId, req.body);
    return reply.code(204).send();
  });
  app.put<D>(`${div}/schedule`, { bodyLimit: scheduleBodyLimit }, async (req, reply) => {
    await svc.publish(caller(req), req.params.id, req.params.divisionId, req.body);
    return reply.code(204).send();
  });
  app.post<D>(`${div}/seed-bracket`, async (req, reply) => {
    await svc.seedBracket(caller(req), req.params.id, req.params.divisionId);
    return reply.code(204).send();
  });
  app.post<D>(`${div}/reconcile`, async (req) => svc.reconcile(caller(req), req.params.id, req.params.divisionId));

  app.post<G>(`${game}/report`, async (req, reply) => {
    await svc.report(caller(req), req.params.id, req.params.divisionId, req.params.gameId, req.body);
    return reply.code(204).send();
  });
  app.post<G>(`${game}/confirm`, async (req, reply) => {
    await svc.confirm(caller(req), req.params.id, req.params.divisionId, req.params.gameId, req.body);
    return reply.code(204).send();
  });
  app.put<G>(`${game}/score`, async (req, reply) => {
    await svc.setScore(caller(req), req.params.id, req.params.divisionId, req.params.gameId, req.body);
    return reply.code(204).send();
  });

  app.put<E>(`${base}/entries/:teamId`, async (req, reply) => {
    await svc.putEntry(caller(req), req.params.id, req.params.teamId, req.body);
    return reply.code(204).send();
  });
  app.post<E>(`${base}/entries/:teamId/invite`, async (req, reply) => {
    await svc.invite(caller(req), req.params.id, req.params.teamId, req.body);
    return reply.code(204).send();
  });
  app.put<E>(`${base}/entries/:teamId/status`, async (req, reply) => {
    await svc.setEntryStatus(caller(req), req.params.id, req.params.teamId, req.body);
    return reply.code(204).send();
  });
}
