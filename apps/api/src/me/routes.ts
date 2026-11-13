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
}
