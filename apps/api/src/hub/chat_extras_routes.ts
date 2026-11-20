import type { FastifyInstance, FastifyRequest } from "fastify";
import { type Caller, requireCaller } from "../auth.js";
import { limited, type MemoryRateLimiter } from "../limits/memory.js";
import type { ChatExtrasService } from "./chat_extras.js";
import { hubLimits } from "./routes.js";

type RoomP = { Params: { teamId: string; roomId: string } };
type MessageP = { Params: { teamId: string; roomId: string; messageId: string } };

/** Pins, event cards and polls in team rooms (redesign F2, F3, F33), as the signed-in caller. */
export function chatExtrasRoutes(app: FastifyInstance, extras: ChatExtrasService, limiter: MemoryRateLimiter) {
  const caller = (req: FastifyRequest, bucket: keyof typeof hubLimits): Caller => {
    const c = requireCaller(req);
    limited(limiter, `${bucket}:${c.uid}`, hubLimits[bucket]);
    return c;
  };
  const pinPath = "/v1/teams/:teamId/chats/:roomId/messages/:messageId/pin";
  app.put<MessageP>(pinPath, async (req, reply) => {
    await extras.pin(caller(req, "respond"), req.params.teamId, req.params.roomId, req.params.messageId, req.body);
    return reply.code(204).send();
  });
  app.delete<MessageP>(pinPath, async (req, reply) => {
    await extras.unpin(caller(req, "respond"), req.params.teamId, req.params.roomId, req.params.messageId);
    return reply.code(204).send();
  });
  app.post<RoomP>("/v1/teams/:teamId/chats/:roomId/event-shares", async (req, reply) =>
    reply.code(201).send(await extras.shareEvent(caller(req, "chat"), req.params.teamId, req.params.roomId, req.body)),
  );
  app.post<RoomP>("/v1/teams/:teamId/chats/:roomId/polls", async (req, reply) =>
    reply.code(201).send(await extras.createPoll(caller(req, "chat"), req.params.teamId, req.params.roomId, req.body)),
  );
  app.put<MessageP>("/v1/teams/:teamId/chats/:roomId/messages/:messageId/vote", async (req, reply) => {
    await extras.vote(caller(req, "respond"), req.params.teamId, req.params.roomId, req.params.messageId, req.body);
    return reply.code(204).send();
  });
  app.post<MessageP>("/v1/teams/:teamId/chats/:roomId/messages/:messageId/close-poll", async (req, reply) => {
    await extras.closePoll(caller(req, "respond"), req.params.teamId, req.params.roomId, req.params.messageId);
    return reply.code(204).send();
  });
}
