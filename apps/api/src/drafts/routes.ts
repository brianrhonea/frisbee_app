import { draftPaths } from "@stall10/shared";
import type { FastifyInstance, FastifyRequest } from "fastify";
import { type Caller, requireCaller } from "../auth.js";
import { ApiError } from "../errors.js";
import type { MemoryRateLimiter } from "../limits/memory.js";
import { countFailedWrite } from "../limits/writes.js";
import type { Limit } from "../limits/model.js";
import type { DraftService } from "./service.js";

const minute = 60_000;
/**
 * Per caller, per instance. Picks and the host's controls skip the global
 * write cap (anyWriteLimit, 120 a minute; ownBucket in limits/writes.ts)
 * and get this roomier bucket instead, so a host can auto-pick a whole
 * draft in a minute. A pick or control that fails (someone who isn't the
 * host's manager or the captain on the clock) still counts against the
 * global cap, so strangers are bounded by it. The host's decisions on signups
 * (accept, waitlist, decline, mark paid: two a player) get room to work
 * down a long list; signing up, saving teams, starting, finishing and
 * creating league teams share a tighter bucket.
 */
export const draftLimits = {
  pick: { max: 240, windowMs: minute },
  decide: { max: 120, windowMs: minute },
  write: { max: 30, windowMs: minute },
} satisfies Record<string, Limit>;

type T = { Params: { tournamentId: string } };
type U = { Params: { tournamentId: string; uid: string } };
type D = { Params: { tournamentId: string; divisionId: string } };

// The paths in packages/shared (draftPaths), as Fastify routes.
const route = (path: string) => path.replace(/%3A/g, ":");
const r = {
  mySignup: route(draftPaths.mySignup(":tournamentId")),
  signupStatus: route(draftPaths.signupStatus(":tournamentId", ":uid")),
  signupPayment: route(draftPaths.signupPayment(":tournamentId", ":uid")),
  draftedTeams: route(draftPaths.draftedTeams(":tournamentId", ":divisionId")),
  leagueTeams: route(draftPaths.leagueTeams(":tournamentId", ":divisionId")),
  draft: route(draftPaths.draft(":tournamentId", ":divisionId")),
  picks: route(draftPaths.draftPicks(":tournamentId", ":divisionId")),
  control: route(draftPaths.draftControl(":tournamentId", ":divisionId")),
  finish: route(draftPaths.draftFinish(":tournamentId", ":divisionId")),
};

/** Signups, drafted teams, the captains' draft and league teams, as the signed-in caller. */
export function draftRoutes(app: FastifyInstance, drafts: DraftService, limiter: MemoryRateLimiter) {
  const caller = (req: FastifyRequest, bucket: keyof typeof draftLimits): Caller => {
    const c = requireCaller(req);
    if (!limiter.admit(`draft-${bucket}:${c.uid}`, draftLimits[bucket])) {
      throw new ApiError("resource_exhausted", "You're doing that too fast. Wait a minute and try again.");
    }
    return c;
  };
  /** Runs an exempt draft write; a failure counts against the global write cap. */
  const exempt = async (c: Caller, run: () => Promise<void>) => {
    try {
      await run();
    } catch (e) {
      if (!(e instanceof ApiError && e.code === "resource_exhausted") && !countFailedWrite(limiter, c.uid)) {
        throw new ApiError("resource_exhausted", "You're doing that too fast. Wait a minute and try again.");
      }
      throw e;
    }
  };

  app.put<T>(r.mySignup, async (req) => drafts.saveMySignup(caller(req, "write"), req.params.tournamentId, req.body));
  app.put<U>(r.signupStatus, async (req, reply) => {
    await drafts.setSignupStatus(caller(req, "decide"), req.params.tournamentId, req.params.uid, req.body);
    return reply.code(204).send();
  });
  app.put<U>(r.signupPayment, async (req, reply) => {
    await drafts.setSignupPayment(caller(req, "decide"), req.params.tournamentId, req.params.uid, req.body);
    return reply.code(204).send();
  });
  app.put<D>(r.draftedTeams, async (req, reply) => {
    await drafts.saveDraftedTeams(caller(req, "write"), req.params.tournamentId, req.params.divisionId, req.body);
    return reply.code(204).send();
  });
  app.post<D>(r.leagueTeams, async (req) => drafts.createLeagueTeams(caller(req, "write"), req.params.tournamentId, req.params.divisionId));
  app.post<D>(r.draft, async (req, reply) =>
    reply.code(201).send(await drafts.startDraft(caller(req, "write"), req.params.tournamentId, req.params.divisionId, req.body)),
  );
  app.post<D>(r.picks, async (req, reply) => {
    const c = caller(req, "pick");
    await exempt(c, () => drafts.pick(c, req.params.tournamentId, req.params.divisionId, req.body));
    return reply.code(204).send();
  });
  app.post<D>(r.control, async (req, reply) => {
    const c = caller(req, "pick");
    await exempt(c, () => drafts.control(c, req.params.tournamentId, req.params.divisionId, req.body));
    return reply.code(204).send();
  });
  app.post<D>(r.finish, async (req) => drafts.finishDraft(caller(req, "write"), req.params.tournamentId, req.params.divisionId));
}
