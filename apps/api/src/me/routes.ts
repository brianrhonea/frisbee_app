import type { FastifyInstance } from "fastify";
import { requireCaller } from "../auth.js";
import type { MeService } from "./service.js";

export function meRoutes(app: FastifyInstance, me: MeService) {
  app.get<{ Querystring: { before?: string } }>("/v1/me/home", async (req, reply) => {
    const caller = requireCaller(req);
    const before = req.query.before === undefined ? undefined : Number(req.query.before);
    // Per person: never stored by a shared cache.
    return reply.header("cache-control", "private, no-store").send(await me.home(caller, before));
  });
  // Others' pages as this member sees them (a private profile they follow
  // in full); the website reads these live, so never cached.
  app.get<{ Params: { uid: string }; Querystring: { before?: string } }>("/v1/players/:uid", async (req, reply) => {
    const caller = requireCaller(req);
    const before = req.query.before === undefined ? undefined : Number(req.query.before);
    return reply.header("cache-control", "private, no-store").send(await me.player(caller, req.params.uid, before));
  });
  app.get<{ Params: { id: string } }>("/v1/posts/:id", async (req, reply) => {
    const caller = requireCaller(req);
    return reply.header("cache-control", "private, no-store").send(await me.onePost(caller, req.params.id));
  });
}
