import type { FastifyInstance, FastifyRequest } from "fastify";
import { type Caller, requireCaller } from "../auth.js";
import { ApiError } from "../errors.js";
import { hubLimits } from "../hub/routes.js";
import type { MemoryRateLimiter } from "../limits/memory.js";
import type { ConversationService } from "./service.js";

type Conv = { Params: { id: string } };
type Msg = { Params: { id: string; messageId: string } };
type Member = { Params: { id: string; uid: string } };

/** Direct and group messages, as the signed-in caller. */
export function conversationRoutes(app: FastifyInstance, convs: ConversationService, limiter: MemoryRateLimiter) {
  const caller = (req: FastifyRequest, bucket: keyof typeof hubLimits): Caller => {
    const c = requireCaller(req);
    if (!limiter.admit(`dm-${bucket}:${c.uid}`, hubLimits[bucket])) {
      throw new ApiError("resource_exhausted", "You're doing that too fast. Wait a minute and try again.");
    }
    return c;
  };
  const done = <T>(reply: { code(n: number): { send(b?: unknown): T } }) => reply.code(204).send();

  app.post("/v1/conversations", async (req) => convs.open(caller(req, "write"), req.body));
  app.post("/v1/conversations/groups", async (req, reply) => reply.code(201).send(await convs.createGroup(caller(req, "write"), req.body)));
  app.patch<Conv>("/v1/conversations/:id", async (req, reply) => {
    await convs.rename(caller(req, "write"), req.params.id, req.body);
    return done(reply);
  });
  app.post<Conv>("/v1/conversations/:id/members", async (req) => convs.addMembers(caller(req, "write"), req.params.id, req.body));
  app.delete<Member>("/v1/conversations/:id/members/:uid", async (req, reply) => {
    await convs.removeMember(caller(req, "write"), req.params.id, req.params.uid);
    return done(reply);
  });
  app.post<Conv>("/v1/conversations/:id/messages", async (req, reply) =>
    reply.code(201).send(await convs.send(caller(req, "chat"), req.params.id, req.body)),
  );
  app.put<Msg>("/v1/conversations/:id/messages/:messageId/reaction", async (req, reply) => {
    await convs.react(caller(req, "respond"), req.params.id, req.params.messageId, req.body);
    return done(reply);
  });
  app.delete<Msg>("/v1/conversations/:id/messages/:messageId", async (req, reply) => {
    await convs.deleteMessage(caller(req, "chat"), req.params.id, req.params.messageId);
    return done(reply);
  });
  app.post<Conv>("/v1/conversations/:id/read", async (req, reply) => {
    await convs.markRead(caller(req, "respond"), req.params.id);
    return done(reply);
  });
  app.put<Conv>("/v1/conversations/:id/request", async (req, reply) => {
    await convs.answer(caller(req, "respond"), req.params.id, req.body);
    return done(reply);
  });
  app.put<Conv>("/v1/conversations/:id/typing", async (req, reply) => {
    await convs.setTyping(caller(req, "respond"), req.params.id, req.body);
    return done(reply);
  });
  app.put<Conv>("/v1/conversations/:id/archive", async (req, reply) => {
    await convs.archive(caller(req, "respond"), req.params.id, req.body);
    return done(reply);
  });
  app.post<Conv>("/v1/conversations/:id/clear", async (req, reply) => {
    await convs.clear(caller(req, "respond"), req.params.id);
    return done(reply);
  });
}
