import { draftPaths } from "@stall10/shared";
import type { FastifyInstance, FastifyRequest } from "fastify";
import { type Caller, requireCaller } from "../auth.js";
import { ApiError } from "../errors.js";
import type { MemoryRateLimiter } from "../limits/memory.js";
import type { Limit } from "../limits/model.js";
import type { DraftService } from "./service.js";

const minute = 60_000;
/**
 * Per caller, per instance. Picks and the host's controls get their own
 * bucket, roomier than the global write cap (anyWriteLimit, 120 a minute),
 * so the global cap is what bounds them; signups, saving teams, starting,
 * finishing and creating league teams share a tighter one.
 */
export const draftLimits = {
  pick: { max: 240, windowMs: minute },
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

  app.put<T>(r.mySignup, async (req) => drafts.saveMySignup(caller(req, "write"), req.params.tournamentId, req.body));
  app.put<U>(r.signupStatus, async (req, reply) => {
    await drafts.setSignupStatus(caller(req, "write"), req.params.tournamentId, req.params.uid, req.body);
    return reply.code(204).send();
  });
  app.put<U>(r.signupPayment, async (req, reply) => {
    await drafts.setSignupPayment(caller(req, "write"), req.params.tournamentId, req.params.uid, req.body);
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
    await drafts.pick(caller(req, "pick"), req.params.tournamentId, req.params.divisionId, req.body);
    return reply.code(204).send();
  });
  app.post<D>(r.control, async (req, reply) => {
    await drafts.control(caller(req, "pick"), req.params.tournamentId, req.params.divisionId, req.body);
    return reply.code(204).send();
  });
  app.post<D>(r.finish, async (req) => drafts.finishDraft(caller(req, "write"), req.params.tournamentId, req.params.divisionId));
}
