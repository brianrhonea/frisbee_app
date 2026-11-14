import type { FastifyInstance } from "fastify";
import { requireCaller } from "../auth.js";
import type { PersonalService } from "./service.js";

/** The caller's own personal details. Never cached anywhere. */
export function personalRoutes(app: FastifyInstance, personal: PersonalService) {
  app.get("/v1/me/personal/status", async (req, reply) =>
    reply.header("cache-control", "private, no-store").send(await personal.status(requireCaller(req))),
  );
  app.get("/v1/me/personal", async (req, reply) =>
    reply.header("cache-control", "private, no-store").send(await personal.get(requireCaller(req))),
  );
  app.put("/v1/me/personal", async (req, reply) => {
    await personal.save(requireCaller(req), req.body);
    return reply.header("cache-control", "private, no-store").send({});
  });
}
