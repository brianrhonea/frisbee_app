import type { FastifyInstance, FastifyRequest } from "fastify";
import { requireCaller } from "../auth.js";
import { noRevalidate, type Revalidate, webTags } from "../web/revalidate.js";
import type { AccountService } from "./service.js";

/** The caller's name, pictures and notification settings. */
export function accountRoutes(app: FastifyInstance, account: AccountService, revalidate: Revalidate = noRevalidate) {
  const changed = (req: FastifyRequest, uid: string) =>
    revalidate([webTags.player(uid), webTags.search, webTags.feed, webTags.posts], req.log);

  app.put("/v1/me/identity", async (req) => {
    const caller = requireCaller(req);
    const result = await account.saveIdentity(caller, req.body);
    await changed(req, caller.uid);
    return result;
  });
  // The Community Guidelines and Terms (agreements.ts in packages/shared).
  app.get("/v1/me/agreement", async (req, reply) =>
    reply.header("cache-control", "private, no-store").send(await account.agreement(requireCaller(req))),
  );
  app.put("/v1/me/agreement", async (req, reply) =>
    reply.header("cache-control", "private, no-store").send(await account.agree(requireCaller(req), req.body)),
  );
  app.put("/v1/me/read-receipts", async (req, reply) => {
    await account.setReadReceipts(requireCaller(req), req.body);
    return reply.code(204).send();
  });
  app.put("/v1/me/notification-settings/category", async (req, reply) => {
    await account.setCategory(requireCaller(req), req.body);
    return reply.code(204).send();
  });
  app.delete<{ Params: { teamId: string } }>("/v1/me/notification-settings/teams/:teamId", async (req, reply) => {
    await account.resetTeam(requireCaller(req), req.params.teamId);
    return reply.code(204).send();
  });
  app.put("/v1/me/notification-settings/mute", async (req, reply) => {
    await account.setMuted(requireCaller(req), req.body);
    return reply.code(204).send();
  });
}
