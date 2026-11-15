// Team stats and roster spots, as the signed-in caller. Stats writes get
// their own bucket: a stats keeper tracking a game live saves often.
import type { FastifyInstance, FastifyRequest } from "fastify";
import { type Caller, requireCaller } from "../auth.js";
import { ApiError } from "../errors.js";
import type { MemoryRateLimiter } from "../limits/memory.js";
import type { Limit } from "../limits/model.js";
import type { StatsService } from "./service.js";

const minute = 60_000;
/**
 * Per member, per instance. The website's tracker sends at most one save
 * a second (trackerSaveTimings in @stall10/shared), so a minute of the
 * fastest tracking is 60 writes: under this and the 120 every write gets.
 */
export const statsLimits = {
  write: { max: 90, windowMs: minute },
} satisfies Record<string, Limit>;

type TeamP = { Params: { teamId: string } };
type GameP = { Params: { teamId: string; gameId: string } };
type TournamentP = { Params: { teamId: string; tournamentId: string } };
type PlayerP = { Params: { teamId: string; playerId: string } };

export function statsRoutes(app: FastifyInstance, stats: StatsService, limiter: MemoryRateLimiter) {
  const caller = (req: FastifyRequest): Caller => {
    const c = requireCaller(req);
    if (!limiter.admit(`stats:${c.uid}`, statsLimits.write)) {
      throw new ApiError("resource_exhausted", "You're doing that too fast. Wait a minute and try again.");
    }
    return c;
  };

  app.post<TeamP>("/v1/teams/:teamId/stats-games", async (req, reply) =>
    reply.code(201).send(await stats.createGame(caller(req), req.params.teamId, req.body)),
  );
  app.put<GameP>("/v1/teams/:teamId/stats-games/:gameId", async (req, reply) => {
    await stats.saveGame(caller(req), req.params.teamId, req.params.gameId, req.body);
    return reply.code(204).send();
  });
  app.delete<GameP>("/v1/teams/:teamId/stats-games/:gameId", async (req, reply) => {
    await stats.deleteGame(caller(req), req.params.teamId, req.params.gameId);
    return reply.code(204).send();
  });

  app.post<TeamP>("/v1/teams/:teamId/stats-tournaments", async (req, reply) =>
    reply.code(201).send(await stats.createTournament(caller(req), req.params.teamId, req.body)),
  );
  app.put<TournamentP>("/v1/teams/:teamId/stats-tournaments/:tournamentId", async (req, reply) => {
    await stats.saveTournament(caller(req), req.params.teamId, req.params.tournamentId, req.body);
    return reply.code(204).send();
  });
  app.delete<TournamentP>("/v1/teams/:teamId/stats-tournaments/:tournamentId", async (req, reply) => {
    await stats.deleteTournament(caller(req), req.params.teamId, req.params.tournamentId);
    return reply.code(204).send();
  });

  app.post<TeamP>("/v1/teams/:teamId/roster-players", async (req, reply) =>
    reply.code(201).send(await stats.savePlayer(caller(req), req.params.teamId, undefined, req.body)),
  );
  app.put<PlayerP>("/v1/teams/:teamId/roster-players/:playerId", async (req, reply) => {
    await stats.savePlayer(caller(req), req.params.teamId, req.params.playerId, req.body);
    return reply.code(204).send();
  });
  app.delete<PlayerP>("/v1/teams/:teamId/roster-players/:playerId", async (req, reply) => {
    await stats.deletePlayer(caller(req), req.params.teamId, req.params.playerId);
    return reply.code(204).send();
  });
  app.put<PlayerP>("/v1/teams/:teamId/roster-players/:playerId/link", async (req, reply) => {
    await stats.linkPlayer(caller(req), req.params.teamId, req.params.playerId, req.body);
    return reply.code(204).send();
  });
}
