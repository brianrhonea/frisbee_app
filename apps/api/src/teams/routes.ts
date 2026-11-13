import type { CreateTeamResponse } from "@stall10/shared";
import type { FastifyInstance } from "fastify";
import { requireCaller } from "../auth.js";
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
