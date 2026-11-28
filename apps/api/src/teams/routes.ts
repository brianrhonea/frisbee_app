import type { CreateTeamResponse } from "@stall10/shared";
import type { FastifyInstance } from "fastify";
import { requireCaller } from "../auth.js";
import type { MemoryRateLimiter } from "../limits/memory.js";
import { readCaller } from "../limits/reads.js";
import type { TeamHistoryService } from "./history.js";
import type { RosterService } from "./roster.js";
import type { TeamService } from "./service.js";

export function teamRoutes(app: FastifyInstance, teams: TeamService) {
  /** Creates a team or group with the caller as its owner. */
  app.post("/v1/teams", async (req, reply) => {
    const caller = requireCaller(req);
    const id = await teams.createTeam(caller, req.body);
    const body: CreateTeamResponse = { id };
    return reply.status(201).send(body);
  });
}

/** Who's on a team, for anyone signed in (RosterService). */
export function rosterRoutes(app: FastifyInstance, roster: RosterService, limiter?: MemoryRateLimiter) {
  const caller = readCaller(limiter);
  app.get("/v1/teams/:teamId/roster", async (req) =>
    roster.roster(caller(req, "roster"), (req.params as { teamId?: unknown }).teamId),
  );
  /** Edit lines: O-line, D-line or both for each spot named (admins). */
  app.put("/v1/teams/:teamId/roster-lines", async (req, reply) => {
    await roster.setLines(requireCaller(req), (req.params as { teamId?: unknown }).teamId, req.body);
    return reply.code(204).send();
  });
}

/** A player's roster history, for anyone signed in (TeamHistoryService decides what they see). */
export function teamHistoryRoutes(app: FastifyInstance, history: TeamHistoryService, limiter?: MemoryRateLimiter) {
  const caller = readCaller(limiter);
  app.get("/v1/players/:uid/team-history", async (req, reply) =>
    reply
      .header("cache-control", "private, no-store")
      .send(await history.history(caller(req, "teamHistory"), (req.params as { uid?: unknown }).uid)),
  );
}
