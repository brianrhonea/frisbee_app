import type { FastifyInstance, FastifyRequest } from "fastify";
import { type Caller, requireCaller } from "../auth.js";
import { limited, type MemoryRateLimiter } from "../limits/memory.js";
import type { Limit } from "../limits/model.js";
import type { HubService } from "./service.js";

type TeamP = { Params: { teamId: string } };
type PostP = { Params: { teamId: string; postId: string } };
type EventP = { Params: { teamId: string; eventId: string } };
type RoomP = { Params: { teamId: string; roomId: string } };
type MessageP = { Params: { teamId: string; roomId: string; messageId: string } };

const minute = 60_000;
/** Per member, per instance: posts and events, chat messages, and quick responses. */
export const hubLimits = {
  write: { max: 30, windowMs: minute },
  chat: { max: 60, windowMs: minute },
  respond: { max: 120, windowMs: minute },
} satisfies Record<string, Limit>;

/** The team hub's writes, as the signed-in caller. */
export function hubRoutes(app: FastifyInstance, hub: HubService, limiter: MemoryRateLimiter) {
  const caller = (req: FastifyRequest, bucket: keyof typeof hubLimits): Caller => {
    const c = requireCaller(req);
    limited(limiter, `${bucket}:${c.uid}`, hubLimits[bucket]);
    return c;
  };

  app.post<TeamP>("/v1/teams/:teamId/posts", async (req, reply) =>
    reply.code(201).send(await hub.createPost(caller(req, "write"), req.params.teamId, req.body)),
  );
  app.patch<PostP>("/v1/teams/:teamId/posts/:postId", async (req) =>
    hub.editPost(caller(req, "write"), req.params.teamId, req.params.postId, req.body),
  );
  app.delete<PostP>("/v1/teams/:teamId/posts/:postId", async (req, reply) => {
    await hub.deletePost(caller(req, "write"), req.params.teamId, req.params.postId);
    return reply.code(204).send();
  });

  app.post<TeamP>("/v1/teams/:teamId/events", async (req, reply) =>
    reply.code(201).send(await hub.createEvent(caller(req, "write"), req.params.teamId, req.body)),
  );
  app.patch<EventP>("/v1/teams/:teamId/events/:eventId", async (req) =>
    hub.editEvent(caller(req, "write"), req.params.teamId, req.params.eventId, req.body, req.query),
  );
  app.delete<EventP>("/v1/teams/:teamId/events/:eventId", async (req, reply) => {
    await hub.deleteEvent(caller(req, "write"), req.params.teamId, req.params.eventId, req.query);
    return reply.code(204).send();
  });
  app.put<EventP>("/v1/teams/:teamId/events/:eventId/rsvp", async (req, reply) => {
    await hub.setRsvp(caller(req, "respond"), req.params.teamId, req.params.eventId, req.body);
    return reply.code(204).send();
  });
  app.put<EventP>("/v1/teams/:teamId/events/:eventId/reaction", async (req, reply) => {
    await hub.setEventReaction(caller(req, "respond"), req.params.teamId, req.params.eventId, req.body);
    return reply.code(204).send();
  });
  app.put<EventP>("/v1/teams/:teamId/events/:eventId/votes", async (req, reply) => {
    await hub.setEventVotes(caller(req, "respond"), req.params.teamId, req.params.eventId, req.body);
    return reply.code(204).send();
  });

  app.post<RoomP>("/v1/teams/:teamId/chats/:roomId/messages", async (req, reply) =>
    reply.code(201).send(await hub.sendMessage(caller(req, "chat"), req.params.teamId, req.params.roomId, req.body)),
  );
  app.put<RoomP>("/v1/teams/:teamId/chats/:roomId/read", async (req, reply) => {
    await hub.markRoomRead(caller(req, "respond"), req.params.teamId, req.params.roomId);
    return reply.code(204).send();
  });
  app.put<MessageP>("/v1/teams/:teamId/chats/:roomId/messages/:messageId/reaction", async (req, reply) => {
    await hub.setMessageReaction(caller(req, "respond"), req.params.teamId, req.params.roomId, req.params.messageId, req.body);
    return reply.code(204).send();
  });
  app.delete<MessageP>("/v1/teams/:teamId/chats/:roomId/messages/:messageId", async (req, reply) => {
    await hub.deleteMessage(caller(req, "chat"), req.params.teamId, req.params.roomId, req.params.messageId);
    return reply.code(204).send();
  });
}
