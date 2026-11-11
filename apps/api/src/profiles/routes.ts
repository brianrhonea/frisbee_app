import type { FastifyInstance } from "fastify";
import { requireCaller } from "../auth.js";
import type { ProfileService } from "./service.js";

/** The caller's own profile and username. */
export function profileRoutes(app: FastifyInstance, profiles: ProfileService) {
  app.post("/v1/me/username", async (req) => profiles.claimUsername(requireCaller(req), req.body));
  app.put("/v1/me/profile/details", async (req) => {
    await profiles.saveDetails(requireCaller(req), req.body);
    return {};
  });
  app.put("/v1/me/profile/privacy", async (req) => {
    await profiles.setPrivate(requireCaller(req), req.body);
    return {};
  });
  app.put("/v1/me/profile/visibility", async (req) => {
    await profiles.saveVisibility(requireCaller(req), req.body);
    return {};
  });
}
