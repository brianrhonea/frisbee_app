import type { FastifyInstance, FastifyRequest } from "fastify";
import { requireCaller } from "../auth.js";
import { noRevalidate, type Revalidate, webTags } from "../web/revalidate.js";
import type { ProfileService } from "./service.js";

/** Open to a not-yet-complete account (the account gate): its own profile basics and username. */
const open = { config: { accountGate: "open" as const } };
/** Needs only the adult check (ageOk): a profile and username while the email or Terms are pending (F1). */
const age = { config: { accountGate: "age" as const } };

/** The caller's own profile and username. */
export function profileRoutes(app: FastifyInstance, profiles: ProfileService, revalidate: Revalidate = noRevalidate) {
  // What visitors see of the caller changed: their page, and search.
  const changed = (req: FastifyRequest, uid: string, ...more: string[]) =>
    revalidate([webTags.player(uid), webTags.search, ...more], req.log);

  app.post("/v1/me/username", age, async (req) => {
    const caller = requireCaller(req);
    const result = await profiles.claimUsername(caller, req.body);
    await changed(req, caller.uid, webTags.feed, webTags.posts);
    return result;
  });
  app.put("/v1/me/profile/details", age, async (req) => {
    const caller = requireCaller(req);
    await profiles.saveDetails(caller, req.body);
    await changed(req, caller.uid);
    return {};
  });
  app.put("/v1/me/profile/privacy", age, async (req) => {
    const caller = requireCaller(req);
    await profiles.setPrivate(caller, req.body);
    // Going private hides their posts everywhere visitors look too.
    await changed(req, caller.uid, webTags.feed, webTags.posts);
    return {};
  });
  app.get("/v1/me/message-policy", async (req, reply) =>
    reply.header("cache-control", "private, no-store").send(await profiles.messagePolicy(requireCaller(req))),
  );
  app.put("/v1/me/message-policy", open, async (req) => {
    await profiles.setMessagePolicy(requireCaller(req), req.body);
    return {};
  });
  app.put("/v1/me/profile/visibility", age, async (req) => {
    const caller = requireCaller(req);
    await profiles.saveVisibility(caller, req.body);
    await changed(req, caller.uid);
    return {};
  });
}
