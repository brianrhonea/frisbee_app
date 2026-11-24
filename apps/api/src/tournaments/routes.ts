// Hosted tournaments and leagues over HTTP (TournamentService), as the
// signed-in caller, under the hub's write limit.
import { liveLimits, type TeamTournamentInvitesResult } from "@stall10/shared";
import type { FastifyInstance, FastifyRequest } from "fastify";
import { type Caller, requireCaller } from "../auth.js";
import { hubLimits } from "../hub/routes.js";
import { limited, type MemoryRateLimiter } from "../limits/memory.js";
import type { TournamentService } from "./service.js";

/**
 * A published schedule's body: up to tournamentLimits.maxGames (2,100)
 * games of at most about 900 bytes of JSON each (two 128-character team
 * ids and sources, a 60-character label), past the API's 64 KB default.
 */
const scheduleBodyLimit = 2 * 1024 * 1024;

/** Running-score updates per caller per minute (liveLimits.perMinute). */
const liveLimit = { max: liveLimits.perMinute, windowMs: 60_000 };

export function tournamentRoutes(app: FastifyInstance, svc: TournamentService, limiter: MemoryRateLimiter) {
  const caller = (req: FastifyRequest): Caller => {
    const c = requireCaller(req);
    limited(limiter, `write:${c.uid}`, hubLimits.write);
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
  // Every division at once, for seeds the host confirmed.
  app.put<T>(`${base}/schedule`, { bodyLimit: scheduleBodyLimit * 2 }, async (req, reply) => {
    await svc.publishAll(caller(req), req.params.id, req.body);
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
  // The running score: its own bucket, so a busy point-by-point game
  // doesn't use up the caller's other writes.
  const liveCaller = (req: FastifyRequest): Caller => {
    const c = requireCaller(req);
    limited(limiter, `live:${c.uid}`, liveLimit);
    return c;
  };
  app.post<G>(`${game}/live`, async (req, reply) => {
    await svc.setLive(liveCaller(req), req.params.id, req.params.divisionId, req.params.gameId, req.body);
    return reply.code(204).send();
  });
  app.delete<G>(`${game}/live`, async (req, reply) => {
    await svc.clearLive(liveCaller(req), req.params.id, req.params.divisionId, req.params.gameId);
    return reply.code(204).send();
  });
  app.put<G>(`${game}/score`, async (req, reply) => {
    await svc.setScore(caller(req), req.params.id, req.params.divisionId, req.params.gameId, req.body);
    return reply.code(204).send();
  });

  // Answers the entry's status: an invite taken up is accepted (or waitlisted when full).
  app.put<E>(`${base}/entries/:teamId`, async (req) => svc.putEntry(caller(req), req.params.id, req.params.teamId, req.body));
  app.put<E>(`${base}/entries/:teamId/roster`, async (req, reply) => {
    await svc.putRoster(caller(req), req.params.id, req.params.teamId, req.body);
    return reply.code(204).send();
  });
  app.post<E>(`${base}/entries/:teamId/invite`, async (req, reply) => {
    await svc.invite(caller(req), req.params.id, req.params.teamId, req.body);
    return reply.code(204).send();
  });
  // Its open invites, and its entries still missing a roster or fee.
  app.get<{ Params: { teamId: string } }>("/v1/teams/:teamId/tournament-invites", async (req): Promise<TeamTournamentInvitesResult> => {
    const c = caller(req);
    const [invites, toFinish] = await Promise.all([svc.teamInvites(c, req.params.teamId), svc.teamEntriesToFinish(c, req.params.teamId)]);
    return { invites, toFinish };
  });
  app.put<E>(`${base}/entries/:teamId/status`, async (req, reply) => {
    await svc.setEntryStatus(caller(req), req.params.id, req.params.teamId, req.body);
    return reply.code(204).send();
  });
}
