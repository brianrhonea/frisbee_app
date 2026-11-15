import type { FastifyInstance } from "fastify";
import { type Caller, requireCaller } from "../auth.js";
import { ApiError } from "../errors.js";
import { docIdParam } from "../ids.js";
import type { MediaStorage } from "../media/storage.js";
import type { DocQueries } from "../queries.js";
import { type Data, type DocStore, serverTime } from "../store.js";
import type { TeamRepository } from "./repository.js";

/** A stored id that is safe to put in a path, or null. */
function safeId(v: unknown): string | null {
  if (typeof v !== "string" || !v) return null;
  try {
    return docIdParam(v);
  } catch {
    return null;
  }
}

/** Hosted events read to find an unfinished one (a team hosts few). */
const hostedReadLimit = 1000;

const mapOf = (v: unknown): Data => (v && typeof v === "object" && !Array.isArray(v) && !(v instanceof Date) ? (v as Data) : {});

/**
 * Deleting a team, group or community (the owner only; teams delete rule),
 * as the app's deleteTeam: `deletingAt` first so the notification
 * functions stay quiet about the cascade, then every document under the
 * team, its files in Storage and its listings. The API also unhooks it
 * from communities: a team leaves its community's list (and any pending
 * request), and a community's teams forget it.
 *
 * A team that hosts a tournament or league that hasn't finished can't be
 * deleted: its managers are the only ones who can run, edit or delete it
 * (manages(t) reads the host team). Finished ones are kept, read-only, as
 * results: their entries, games and placements stay readable (visible(t)
 * needs no host once published), and nobody can edit them any more.
 */
export class TeamDeletion {
  constructor(
    private readonly store: DocStore,
    private readonly teams: Pick<TeamRepository, "deleteTeamTree">,
    private readonly media: MediaStorage | undefined,
    private readonly queries: DocQueries,
  ) {}

  async deleteTeam(caller: Caller, rawTeam: unknown, body: unknown): Promise<void> {
    const teamId = docIdParam(rawTeam);
    const typed = typeof (body as { name?: unknown } | null)?.name === "string" ? String((body as { name: string }).name).trim() : null;
    // Only the owner gets as far as the query (checked again below).
    const first = await this.store.get(`teams/${teamId}`);
    if (!first) throw new ApiError("not_found", "That team doesn't exist.");
    if (first.ownerId !== caller.uid) throw new ApiError("permission_denied", "Only the owner can delete it.");
    // Hosted events (tournaments and leagues) can't be read in the
    // transaction; one made while it's being deleted fails without its host.
    const hosted = await this.queries.fields("tournaments", ["status"], hostedReadLimit, { hostId: teamId });
    const hostsUnfinished = hosted.some((t) => t.data.status !== "finished");
    await this.store.transact(async (tx) => {
      const team = await tx.get(`teams/${teamId}`);
      if (!team) throw new ApiError("not_found", "That team doesn't exist.");
      if (team.ownerId !== caller.uid) throw new ApiError("permission_denied", "Only the owner can delete it.");
      // soleOwner(): the owner removes everyone else or hands it on first, so no one's team vanishes.
      const memberIds = Array.isArray(team.memberIds) ? team.memberIds : [];
      if (memberIds.length !== 1 || memberIds[0] !== caller.uid) {
        throw new ApiError("failed_precondition", "Remove everyone else or hand it on before deleting it.");
      }
      // inActiveLeague(): a league's games and standings refer to its teams until it's final.
      const leagueId = safeId(team.leagueId);
      if (team.leagueId != null && !leagueId) throw new ApiError("failed_precondition", "It plays in a league, so it can't be deleted yet.");
      if (leagueId) {
        const league = await tx.get(`tournaments/${leagueId}`);
        if (league && league.status !== "finished") {
          throw new ApiError("failed_precondition", "It plays in a league that hasn't finished, so it can't be deleted yet.");
        }
      }
      if (hostsUnfinished) {
        throw new ApiError("failed_precondition", "It hosts a tournament or league that hasn't finished. Finish or delete it first.");
      }
      // The client asks them to type the name; checked here too, so a stray request can't do it.
      if (typed === null || typed.toLowerCase() !== String(team.name ?? "").trim().toLowerCase()) {
        throw new ApiError("invalid_argument", "Type the name exactly to delete it.");
      }
      const orgId = safeId(team.orgId);
      const linked = Object.keys(mapOf(team.linkedTeams)).filter((id) => safeId(id) !== null).slice(0, 50);
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
    // Left behind, the files are unreadable (storage.rules need the team), so a failure is logged, not fatal.
    await this.media?.deletePrefix(`teams/${teamId}/`).catch((e: unknown) => console.warn(`team ${teamId}: files not deleted`, e));
  }
}

export function teamDeletionRoutes(app: FastifyInstance, deletion: TeamDeletion) {
  app.delete<{ Params: { teamId: string } }>("/v1/teams/:teamId", async (req, reply) => {
    await deletion.deleteTeam(requireCaller(req), req.params.teamId, req.body);
    return reply.code(204).send();
  });
}
