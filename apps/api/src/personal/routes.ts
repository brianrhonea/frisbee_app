import type { FastifyInstance, FastifyRequest } from "fastify";
import type { AccountGate } from "../account/gate.js";
import { requireCaller } from "../auth.js";
import { limited, type MemoryRateLimiter } from "../limits/memory.js";
import type { Limit } from "../limits/model.js";
import type { PersonalService } from "./service.js";

/** Open to a not-yet-complete account: this is how a new account completes (the account gate). */
const open = { config: { accountGate: "open" as const } };

/**
 * The status call is never gated and may decrypt the birth date (KMS) while
 * a token lacks `ageOk`, and GETs skip the any-write limit, so it has its
 * own per-caller caps (F4): clients call it at sign-in and after a 403.
 */
export const statusLimits: Limit[] = [
  { max: 10, windowMs: 60_000 },
  { max: 200, windowMs: 24 * 60 * 60_000 },
];

/** The caller's own personal details. Never cached anywhere. */
export function personalRoutes(app: FastifyInstance, personal: PersonalService, gate?: AccountGate, limiter?: MemoryRateLimiter) {
  // Saving a birth date (or asking for the status) may complete the account:
  // then the claims are set and the client must refresh its token.
  const refreshed = async (req: FastifyRequest) => ((await gate?.sync(requireCaller(req), req.log)) ? { refreshToken: true as const } : {});

  // The status is also the lazy migration for accounts made before the gate:
  // it sets any claim their records already earn.
  app.get("/v1/me/personal/status", async (req, reply) => {
    const caller = requireCaller(req);
    statusLimits.forEach((limit, i) => limited(limiter, `personal-status#${i}:${caller.uid}`, limit));
    const status = await personal.status(caller);
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
