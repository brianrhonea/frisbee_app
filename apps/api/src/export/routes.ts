import { dataExportFileName } from "@stall10/shared";
import type { FastifyInstance } from "fastify";
import { requireCaller } from "../auth.js";
import type { ExportService } from "./service.js";

/** "Download your data": the caller's data as a JSON file (ExportService). */
export function exportRoutes(app: FastifyInstance, exports: ExportService) {
  app.get("/v1/me/export", async (req, reply) => {
    const data = await exports.export(requireCaller(req));
    return reply
      .header("cache-control", "private, no-store")
      .header("content-type", "application/json; charset=utf-8")
      .header("content-disposition", `attachment; filename="${dataExportFileName(new Date(data.exportedAt))}"`)
      .send(JSON.stringify(data, null, 2));
  });
}
