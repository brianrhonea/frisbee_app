import { tournamentChatPaths } from "@stall10/shared";
import type { FastifyInstance, FastifyRequest } from "fastify";
import { type Caller, requireCaller } from "../auth.js";
import { limited, type MemoryRateLimiter } from "../limits/memory.js";
import type { TournamentChatService } from "./service.js";

/** Each open re-reads the tournament's entries and teams. */
export const tournamentChatLimit = { max: 30, windowMs: 60_000 };

/** Opening a tournament's chats with its organizers (tournament_chats.ts). */
export function tournamentChatRoutes(app: FastifyInstance, chats: TournamentChatService, limiter: MemoryRateLimiter | undefined) {
  const caller = (req: FastifyRequest): Caller => {
    const c = requireCaller(req);
    limited(limiter, `tournament-chats:${c.uid}`, tournamentChatLimit);
    return c;
  };
  type Id = { Params: { id: string } };
  type Team = { Params: { id: string; teamId: string } };
  app.post<Id>(tournamentChatPaths.captains(":id"), async (req) => chats.captains(caller(req), req.params.id));
  app.post<Team>(tournamentChatPaths.team(":id", ":teamId"), async (req) => chats.team(caller(req), req.params.id, req.params.teamId));
}
