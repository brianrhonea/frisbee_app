import { reportsPerDay } from "@stall10/shared";
import type { FastifyInstance } from "fastify";
import { requireCaller } from "../auth.js";
import { limited, type MemoryRateLimiter } from "../limits/memory.js";
import { noRevalidate, type Revalidate, webTags } from "../web/revalidate.js";
import type { ModerationService } from "./service.js";

const day = 24 * 60 * 60 * 1000;
const minute = 60 * 1000;

type Uid = { Params: { uid: string } };
type TeamP = { Params: { teamId: string } };
type TeamReportP = { Params: { teamId: string; reportId: string } };
type ReportP = { Params: { reportId: string } };

/** Reports, blocks and the review queues (team admins, Stall 10 staff). */
export function moderationRoutes(
  app: FastifyInstance,
  mod: ModerationService,
  limiter?: MemoryRateLimiter,
  revalidate: Revalidate = noRevalidate,
) {
  app.post("/v1/reports", async (req, reply) => {
    const c = requireCaller(req);
    limited(limiter, `reports:${c.uid}`, { max: reportsPerDay, windowMs: day });
    return reply.code(201).send(await mod.report(c, req.body));
  });

  app.get("/v1/me/blocks", async (req) => mod.blocks(requireCaller(req)));
  app.put<Uid>("/v1/me/blocks/:uid", async (req, reply) => {
    const c = requireCaller(req);
    limited(limiter, `blocks:${c.uid}`, { max: 30, windowMs: minute });
    await mod.block(c, req.params.uid);
    return reply.code(204).send();
  });
  app.delete<Uid>("/v1/me/blocks/:uid", async (req, reply) => {
    await mod.unblock(requireCaller(req), req.params.uid);
    return reply.code(204).send();
  });

  app.get("/v1/me/moderation", async (req) => mod.access(requireCaller(req)));

  app.get<TeamP>("/v1/teams/:teamId/reports", async (req) => mod.teamReports(requireCaller(req), req.params.teamId));
  app.post<TeamReportP>("/v1/teams/:teamId/reports/:reportId", async (req, reply) => {
    await mod.resolveTeamReport(requireCaller(req), req.params.teamId, req.params.reportId, req.body);
    await revalidate([webTags.feed, webTags.posts], req.log);
    return reply.code(204).send();
  });

  app.get("/v1/staff/reports", async (req) => mod.staffReports(requireCaller(req)));
  app.post<ReportP>("/v1/staff/reports/:reportId", async (req, reply) => {
    await mod.staffAction(requireCaller(req), req.params.reportId, req.body);
    await revalidate([webTags.feed, webTags.posts], req.log);
    return reply.code(204).send();
  });
}
