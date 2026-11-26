import type { FastifyInstance, FastifyRequest } from "fastify";
import { requireCaller } from "../auth.js";
import type { AccountGate } from "./gate.js";
import { noRevalidate, type Revalidate, webTags } from "../web/revalidate.js";
import type { AccountService } from "./service.js";

/** The caller's name, pictures and notification settings. */
/** Open to a not-yet-complete account (the account gate): onboarding and own settings. */
const open = { config: { accountGate: "open" as const } };
/** Needs only the adult check (ageOk): a profile and username while the email or Terms are pending (F1). */
const age = { config: { accountGate: "age" as const } };

export function accountRoutes(app: FastifyInstance, account: AccountService, revalidate: Revalidate = noRevalidate, gate?: AccountGate) {
  const changed = (req: FastifyRequest, uid: string) =>
    revalidate([webTags.player(uid), webTags.search, webTags.feed, webTags.posts], req.log);

  app.put("/v1/me/identity", age, async (req) => {
    const caller = requireCaller(req);
    const result = await account.saveIdentity(caller, req.body);
    await changed(req, caller.uid);
    return result;
  });
  // The Community Guidelines and Terms (agreements.ts in packages/shared).
  app.get("/v1/me/agreement", async (req, reply) =>
    reply.header("cache-control", "private, no-store").send(await account.agreement(requireCaller(req))),
  );
  app.put("/v1/me/agreement", open, async (req, reply) => {
    const caller = requireCaller(req);
    const status = await account.agree(caller, req.body);
    // Agreeing may complete the account: set the claim, and tell the client to refresh its token.
    const refresh = (await gate?.sync(caller, req.log)) ? { refreshToken: true as const } : {};
    return reply.header("cache-control", "private, no-store").send({ ...status, ...refresh });
  });
  app.put("/v1/me/read-receipts", open, async (req, reply) => {
    await account.setReadReceipts(requireCaller(req), req.body);
    return reply.code(204).send();
  });
  app.put("/v1/me/notification-settings/category", open, async (req, reply) => {
    await account.setCategory(requireCaller(req), req.body);
    return reply.code(204).send();
  });
  app.delete<{ Params: { teamId: string } }>("/v1/me/notification-settings/teams/:teamId", open, async (req, reply) => {
    await account.resetTeam(requireCaller(req), req.params.teamId);
    return reply.code(204).send();
  });
  app.put("/v1/me/notification-settings/mute", open, async (req, reply) => {
    await account.setMuted(requireCaller(req), req.body);
    return reply.code(204).send();
  });
}
