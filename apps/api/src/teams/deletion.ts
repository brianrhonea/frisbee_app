import type { FastifyInstance } from "fastify";
import { type Caller, requireCaller } from "../auth.js";
import { ApiError } from "../errors.js";
import { docIdParam } from "../ids.js";
import type { MediaStorage } from "../media/storage.js";
import { type Data, type DocStore, serverTime } from "../store.js";
import type { TeamRepository } from "./repository.js";

const mapOf = (v: unknown): Data => (v && typeof v === "object" && !Array.isArray(v) && !(v instanceof Date) ? (v as Data) : {});

/**
 * Deleting a team, group or community (the owner only; teams delete rule),
 * as the app's deleteTeam: `deletingAt` first so the notification
 * functions stay quiet about the cascade, then every document under the
 * team, its files in Storage and its listings. The API also unhooks it
 * from communities: a team leaves its community's list (and any pending
 * request), and a community's teams forget it.
 */
export class TeamDeletion {
  constructor(
    private readonly store: DocStore,
    private readonly teams: Pick<TeamRepository, "deleteTeamTree">,
    private readonly media: MediaStorage | undefined,
  ) {}

  async deleteTeam(caller: Caller, rawTeam: unknown, body: unknown): Promise<void> {
    const teamId = docIdParam(rawTeam);
    const typed = typeof (body as { name?: unknown } | null)?.name === "string" ? String((body as { name: string }).name).trim() : null;
    await this.store.transact(async (tx) => {
      const team = await tx.get(`teams/${teamId}`);
      if (!team) throw new ApiError("not_found", "That team doesn't exist.");
      if (team.ownerId !== caller.uid && mapOf(team.members)[caller.uid] !== "owner") {
        throw new ApiError("permission_denied", "Only the owner can delete it.");
      }
      // The client asks them to type the name; checked here too, so a stray request can't do it.
      if (typed === null || typed.toLowerCase() !== String(team.name ?? "").trim().toLowerCase()) {
        throw new ApiError("invalid_argument", "Type the name exactly to delete it.");
      }
      const orgId = typeof team.orgId === "string" && team.orgId ? team.orgId : null;
      const linked = Object.keys(mapOf(team.linkedTeams)).slice(0, 50);
      const [org, request, ...members] = await Promise.all([
        orgId ? tx.get(`teams/${orgId}`) : Promise.resolve(null),
        orgId ? tx.get(`teams/${orgId}/linkRequests/${teamId}`) : Promise.resolve(null),
        ...linked.map((id) => tx.get(`teams/${id}`)),
      ]);
      tx.update(`teams/${teamId}`, { deletingAt: serverTime });
      if (org && Object.hasOwn(mapOf(org.linkedTeams), teamId)) {
        const rest = { ...mapOf(org.linkedTeams) };
        delete rest[teamId];
        tx.update(`teams/${orgId}`, { linkedTeams: rest });
      }
      if (request) tx.delete(`teams/${orgId}/linkRequests/${teamId}`);
      linked.forEach((id, i) => {
        if (members[i]?.orgId === teamId) tx.update(`teams/${id}`, { orgId: null, orgName: "", orgLinked: false });
      });
    });
    await this.teams.deleteTeamTree(teamId);
    await this.media?.deletePrefix(`teams/${teamId}/`).catch(() => undefined);
  }
}

export function teamDeletionRoutes(app: FastifyInstance, deletion: TeamDeletion) {
  app.delete<{ Params: { teamId: string } }>("/v1/teams/:teamId", async (req, reply) => {
    await deletion.deleteTeam(requireCaller(req), req.params.teamId, req.body);
    return reply.code(204).send();
  });
}
