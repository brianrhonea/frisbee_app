import type { FastifyInstance } from "fastify";
import type { AccountGate } from "../account/gate.js";
import { requireCaller } from "../auth.js";
import type { PersonalService } from "./service.js";

/** Open to a not-yet-complete account: this is how a new account completes (the account gate). */
const open = { config: { accountGate: "open" as const } };

/** The caller's own personal details. Never cached anywhere. */
export function personalRoutes(app: FastifyInstance, personal: PersonalService, gate?: AccountGate) {
  // Saving a birth date (or asking for the status) may complete the account:
  // then the claims are set and the client must refresh its token.
  const refreshed = async (req: Parameters<typeof requireCaller>[0]) => ((await gate?.sync(requireCaller(req))) ? { refreshToken: true as const } : {});

  // The status is also the lazy migration for accounts made before the gate:
  // it sets any claim their records already earn.
  app.get("/v1/me/personal/status", async (req, reply) => {
    const status = await personal.status(requireCaller(req));
    return reply.header("cache-control", "private, no-store").send({ ...status, ...(await refreshed(req)) });
  });
  app.get("/v1/me/personal", async (req, reply) =>
    reply.header("cache-control", "private, no-store").send(await personal.get(requireCaller(req))),
  );
  app.put("/v1/me/personal", open, async (req, reply) => {
    await personal.save(requireCaller(req), req.body);
    return reply.header("cache-control", "private, no-store").send(await refreshed(req));
  });
  // Right after an email sign-up: just the birthday, until the full form.
  app.put("/v1/me/personal/birth-date", open, async (req, reply) => {
    await personal.saveSignUpBirthDate(requireCaller(req), req.body);
    return reply.header("cache-control", "private, no-store").send(await refreshed(req));
  });
}
