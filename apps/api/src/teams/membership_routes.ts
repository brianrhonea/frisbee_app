import type { JoinByCodeResponse } from "@stall10/shared";
import type { FastifyInstance, FastifyRequest } from "fastify";
import { requireCaller } from "../auth.js";
import { docIdParam } from "../ids.js";
import type { MembershipService } from "./membership.js";

type Params = { teamId: string; uid: string; orgId: string };
/** The path's ids, each checked to be one document id. */
const params = (req: FastifyRequest) => {
  const raw = req.params as Record<string, unknown>;
  return Object.fromEntries(Object.entries(raw).map(([k, v]) => [k, docIdParam(v)])) as Params;
};

/** Team membership and management (MembershipService). Answers {} unless noted. */
export function membershipRoutes(app: FastifyInstance, m: MembershipService) {
  const ok = {};

  // Joining
  app.post("/v1/teams/join", async (req) => {
    const teamId = await m.joinByCode(requireCaller(req), req.body);
    return { teamId } satisfies JoinByCodeResponse;
  });
  app.post("/v1/teams/:teamId/members", async (req) => {
    await m.joinGroup(requireCaller(req), params(req).teamId);
    return ok;
  });
  app.post("/v1/teams/:teamId/join-requests", async (req) => {
    await m.requestToJoin(requireCaller(req), params(req).teamId);
    return ok;
  });
  app.delete("/v1/teams/:teamId/join-requests/:uid", async (req) => {
    const { teamId, uid } = params(req);
    await m.deleteJoinRequest(requireCaller(req), teamId, uid);
    return ok;
  });
  app.post("/v1/teams/:teamId/join-requests/:uid/approve", async (req) => {
    const { teamId, uid } = params(req);
    await m.approveJoinRequest(requireCaller(req), teamId, uid);
    return ok;
  });
  app.post("/v1/teams/:teamId/invites", async (req) => {
    await m.invite(requireCaller(req), params(req).teamId, req.body);
    return ok;
  });
  app.post("/v1/me/team-invites/:teamId/accept", async (req) => {
    await m.acceptInvite(requireCaller(req), params(req).teamId);
    return ok;
  });
  app.delete("/v1/me/team-invites/:teamId", async (req) => {
    await m.declineInvite(requireCaller(req), params(req).teamId);
    return ok;
  });

  // Members
  app.delete("/v1/teams/:teamId/members/:uid", async (req) => {
    const { teamId, uid } = params(req);
    await m.removeMember(requireCaller(req), teamId, uid);
    return ok;
  });
  app.put("/v1/teams/:teamId/members/:uid/role", async (req) => {
    const { teamId, uid } = params(req);
    await m.setMemberRole(requireCaller(req), teamId, uid, req.body);
    return ok;
  });
  app.put("/v1/teams/:teamId/members/:uid/stat-keeper", async (req) => {
    const { teamId, uid } = params(req);
    await m.setStatKeeper(requireCaller(req), teamId, uid, req.body);
    return ok;
  });
  app.post("/v1/teams/:teamId/owner", async (req) => {
    await m.transferOwnership(requireCaller(req), params(req).teamId, req.body);
    return ok;
  });
  // Roles for every member of a big team can outgrow the usual 64 KB.
  app.put("/v1/teams/:teamId/roles", { bodyLimit: 512 * 1024 }, async (req) => {
    await m.saveRoles(requireCaller(req), params(req).teamId, req.body);
    return ok;
  });

  // Details
  app.patch("/v1/teams/:teamId", async (req) => {
    await m.editTeam(requireCaller(req), params(req).teamId, req.body);
    return ok;
  });
  app.put("/v1/teams/:teamId/listing", async (req) => {
    await m.publishListing(requireCaller(req), params(req).teamId);
    return ok;
  });
  app.post("/v1/invite-codes", async (req, reply) => {
    const body = await m.createInviteCode(requireCaller(req), req.body);
    return reply.status(201).send(body);
  });

  // Communities
  app.put("/v1/teams/:teamId/community", async (req) => {
    await m.requestCommunityLink(requireCaller(req), params(req).teamId, req.body);
    return ok;
  });
  app.delete("/v1/teams/:teamId/community", async (req) => {
    await m.leaveCommunity(requireCaller(req), params(req).teamId);
    return ok;
  });
  app.post("/v1/teams/:orgId/link-requests/:teamId/accept", async (req) => {
    const { orgId, teamId } = params(req);
    await m.acceptLinkRequest(requireCaller(req), orgId, teamId, req.body);
    return ok;
  });
  app.delete("/v1/teams/:orgId/link-requests/:teamId", async (req) => {
    const { orgId, teamId } = params(req);
    await m.declineLinkRequest(requireCaller(req), orgId, teamId);
    return ok;
  });
  app.put("/v1/teams/:orgId/linked-teams/:teamId", async (req) => {
    const { orgId, teamId } = params(req);
    await m.saveLinkedTeam(requireCaller(req), orgId, teamId, req.body);
    return ok;
  });
  app.delete("/v1/teams/:orgId/linked-teams/:teamId", async (req) => {
    const { orgId, teamId } = params(req);
    await m.unlinkTeam(requireCaller(req), orgId, teamId);
    return ok;
  });
  app.post("/v1/teams/:orgId/linked-teams", async (req, reply) => {
    const id = await m.createTeamInCommunity(requireCaller(req), params(req).orgId, req.body);
    return reply.status(201).send({ id });
  });
}
