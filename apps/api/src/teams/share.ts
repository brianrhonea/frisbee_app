// Splitting a team fee (packages/shared/src/team_share.ts): an admin who
// paid for the whole team sets each member's share and how to pay them,
// and marks who has paid. Stored at teams/{id}/private/share, which the
// rules keep from every client; members read it through here. No money
// passes through Stall 10.
import {
  markSharePaidRequestSchema,
  setTeamShareRequestSchema,
  type TeamShareMember,
  type TeamShareView,
} from "@stall10/shared";
import type { FastifyInstance } from "fastify";
import { type Caller, requireCaller } from "../auth.js";
import { ApiError, parseBody } from "../errors.js";
import { docIdParam } from "../ids.js";
import { type Data, type DocStore, serverTime } from "../store.js";
import { can, isGroup, isMember, mapOf, strings } from "./access.js";

const sharePath = (teamId: string) => `teams/${teamId}/private/share`;
const str = (v: unknown) => (typeof v === "string" ? v : "");

export class TeamShareService {
  constructor(private readonly store: DocStore) {}

  /** The team, for a member of a team (not a group). */
  private async teamFor(caller: Caller, teamId: string): Promise<Data> {
    const team = await this.store.get(`teams/${teamId}`);
    if (!team || !isMember(team, caller.uid)) throw new ApiError("not_found", "That team doesn't exist, or you're not on it.");
    if (isGroup(team)) throw new ApiError("failed_precondition", "Only a team can split a fee.");
    return team;
  }

  async view(caller: Caller, rawTeamId: unknown): Promise<TeamShareView> {
    const teamId = docIdParam(rawTeamId);
    const team = await this.teamFor(caller, teamId);
    const doc = await this.store.get(sharePath(teamId));
    return viewOf(team, doc, caller.uid);
  }

  /** Starts or changes the split; whoever sets it collects it. Paid marks are kept. */
  async set(caller: Caller, rawTeamId: unknown, body: unknown): Promise<TeamShareView> {
    const teamId = docIdParam(rawTeamId);
    const input = parseBody(setTeamShareRequestSchema, body);
    return this.store.transact(async (tx) => {
      const team = await tx.get(`teams/${teamId}`);
      if (!team || !isMember(team, caller.uid)) throw new ApiError("not_found", "That team doesn't exist, or you're not on it.");
      if (isGroup(team)) throw new ApiError("failed_precondition", "Only a team can split a fee.");
      if (!can(team, caller.uid, "manageTeam")) throw new ApiError("permission_denied", "Only the team's admins can split a fee.");
      const before = await tx.get(sharePath(teamId));
      const doc: Data = {
        amountCents: input.amountCents,
        currency: input.currency,
        note: input.note,
        collectorId: str(before?.collectorId) || caller.uid,
        paid: mapOf(before?.paid),
        updatedAt: serverTime,
        updatedBy: caller.uid,
      };
      tx.set(sharePath(teamId), doc);
      return viewOf(team, doc, caller.uid);
    });
  }

  /** Stops splitting the fee (paid marks go with it). */
  async clear(caller: Caller, rawTeamId: unknown): Promise<void> {
    const teamId = docIdParam(rawTeamId);
    const team = await this.teamFor(caller, teamId);
    if (!can(team, caller.uid, "manageTeam")) throw new ApiError("permission_denied", "Only the team's admins can split a fee.");
    await this.store.transact(async (tx) => {
      if (await tx.get(sharePath(teamId))) tx.delete(sharePath(teamId));
    });
  }

  /** Marks [uid] paid or not: the collector, or an admin with Manage team. */
  async markPaid(caller: Caller, rawTeamId: unknown, rawUid: unknown, body: unknown): Promise<TeamShareView> {
    const teamId = docIdParam(rawTeamId);
    const uid = docIdParam(rawUid);
    const { paid } = parseBody(markSharePaidRequestSchema, body);
    return this.store.transact(async (tx) => {
      const [team, doc] = await Promise.all([tx.get(`teams/${teamId}`), tx.get(sharePath(teamId))]);
      if (!team || !isMember(team, caller.uid)) throw new ApiError("not_found", "That team doesn't exist, or you're not on it.");
      if (!doc) throw new ApiError("failed_precondition", "This team isn't splitting a fee.");
      if (!manages(team, doc, caller.uid)) throw new ApiError("permission_denied", "Only the person collecting can mark shares paid.");
      if (!isMember(team, uid) || uid === str(doc.collectorId)) throw new ApiError("not_found", "They don't owe a share.");
      const marks = { ...mapOf(doc.paid) };
      if (paid) marks[uid] = true;
      else delete marks[uid];
      const next = { ...doc, paid: marks, updatedAt: serverTime, updatedBy: caller.uid };
      tx.set(sharePath(teamId), next);
      return viewOf(team, next, caller.uid);
    });
  }
}

const manages = (team: Data, doc: Data, uid: string) => uid === str(doc.collectorId) || can(team, uid, "manageTeam");

/** What [uid] sees: their own share; the whole list if they manage it. */
export function viewOf(team: Data, doc: Data | null, uid: string): TeamShareView {
  const canManage = can(team, uid, "manageTeam");
  if (!doc) return { share: null, manages: canManage, mine: null, members: [] };
  const collectorId = str(doc.collectorId);
  const names = mapOf(team.memberNames);
  const marks = mapOf(doc.paid);
  const owing: TeamShareMember[] = strings(team.memberIds)
    .filter((m) => m !== collectorId)
    .map((m) => ({ uid: m, name: str(names[m]) || "Member", paid: marks[m] === true }))
    .sort((a, b) => Number(a.paid) - Number(b.paid) || a.name.localeCompare(b.name));
  const runs = manages(team, doc, uid);
  return {
    share: {
      amountCents: typeof doc.amountCents === "number" ? doc.amountCents : 0,
      currency: str(doc.currency) || "usd",
      note: str(doc.note),
      collectorId,
      collectorName: str(names[collectorId]) || "the team's admin",
    },
    manages: runs,
    mine: uid === collectorId ? null : { paid: marks[uid] === true },
    members: runs ? owing : [],
  };
}

export function teamShareRoutes(app: FastifyInstance, shares: TeamShareService) {
  type P = { teamId?: unknown; uid?: unknown };
  const noStore = { "cache-control": "no-store" };
  app.get("/v1/teams/:teamId/share", async (req, reply) =>
    reply.headers(noStore).send(await shares.view(requireCaller(req), (req.params as P).teamId)),
  );
  app.put("/v1/teams/:teamId/share", async (req) => shares.set(requireCaller(req), (req.params as P).teamId, req.body));
  app.delete("/v1/teams/:teamId/share", async (req, reply) => {
    await shares.clear(requireCaller(req), (req.params as P).teamId);
    return reply.code(204).send();
  });
  app.put("/v1/teams/:teamId/share/members/:uid", async (req) =>
    shares.markPaid(requireCaller(req), (req.params as P).teamId, (req.params as P).uid, req.body),
  );
}
