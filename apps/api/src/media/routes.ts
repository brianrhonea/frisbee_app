import type { FastifyInstance } from "fastify";
import { requireCaller } from "../auth.js";
import type { UploadService } from "./service.js";

/** Media uploads (ARCHITECTURE.md §6). */
export function uploadRoutes(app: FastifyInstance, uploads: UploadService) {
  app.post("/v1/uploads", async (req, reply) => {
    const body = await uploads.create(requireCaller(req), req.body);
    return reply.status(201).send(body);
  });
  app.post("/v1/uploads/:id/complete", async (req) =>
    uploads.complete(requireCaller(req), (req.params as { id: string }).id),
  );
}
