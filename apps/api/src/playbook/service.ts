// A team's plays (teams/{id}/plays): the plays rule ported. Members who
// manage the team save and delete them; every field is checked whole
// (savePlayRequestSchema), and updatedBy is the caller.
import { type SavePlayInput, savePlayRequestSchema } from "@stall10/shared";
import type { FastifyInstance, FastifyRequest } from "fastify";
import type { z } from "zod";
import { type Caller, requireCaller } from "../auth.js";
import { ApiError, fromZod } from "../errors.js";
import { hubLimits } from "../hub/routes.js";
import { docIdParam } from "../ids.js";
import type { MemoryRateLimiter } from "../limits/memory.js";
import { type DocStore, serverTime } from "../store.js";
import { can, isMember } from "../teams/access.js";

function parse<S extends z.ZodType>(schema: S, body: unknown): z.output<S> {
  const r = schema.safeParse(body ?? {});
  if (!r.success) throw fromZod(r.error);
  return r.data;
}

const denied = () => new ApiError("permission_denied", "Only the team's admins can change the playbook.");

/** The play as stored (Play.toMap), with who saved it. */
function playFields(p: SavePlayInput, uid: string) {
  return {
    name: p.name,
    category: p.category,
    notes: p.notes,
    elements: p.elements.map((e) => ({ id: e.id, kind: e.kind, position: { x: e.position.x, y: e.position.y }, label: e.label })),
    arrows: p.arrows.map((a) => ({ id: a.id, kind: a.kind, points: a.points.map((q) => ({ x: q.x, y: q.y })) })),
    steps: p.steps.map((s) => ({
      id: s.id,
      note: s.note,
      paths: Object.fromEntries(Object.entries(s.paths).map(([id, pts]) => [id, pts.map((q) => ({ x: q.x, y: q.y }))])),
    })),
    updatedAt: serverTime,
    updatedBy: uid,
  };
}

export class PlaybookService {
  constructor(private readonly store: DocStore) {}

  private async editor(teamId: string, caller: Caller) {
    const team = await this.store.get(`teams/${teamId}`);
    if (!team) throw new ApiError("not_found", "That team doesn't exist.");
    if (!isMember(team, caller.uid) || !can(team, caller.uid, "manageTeam")) throw denied();
  }

  async create(caller: Caller, rawTeam: unknown, body: unknown): Promise<{ id: string }> {
    const teamId = docIdParam(rawTeam);
    const play = parse(savePlayRequestSchema, body);
    await this.editor(teamId, caller);
    const id = this.store.newId(`teams/${teamId}/plays`);
    await this.store.transact(async (tx) => {
      tx.create(`teams/${teamId}/plays/${id}`, playFields(play, caller.uid));
    });
    return { id };
  }

  async save(caller: Caller, rawTeam: unknown, rawPlay: unknown, body: unknown): Promise<void> {
    const teamId = docIdParam(rawTeam);
    const id = docIdParam(rawPlay);
    const play = parse(savePlayRequestSchema, body);
    await this.editor(teamId, caller);
    await this.store.transact(async (tx) => {
      if (!(await tx.get(`teams/${teamId}/plays/${id}`))) throw new ApiError("not_found", "That play doesn't exist.");
      tx.set(`teams/${teamId}/plays/${id}`, playFields(play, caller.uid));
    });
  }

  async remove(caller: Caller, rawTeam: unknown, rawPlay: unknown): Promise<void> {
    const teamId = docIdParam(rawTeam);
    const id = docIdParam(rawPlay);
    await this.editor(teamId, caller);
    await this.store.transact(async (tx) => {
      tx.delete(`teams/${teamId}/plays/${id}`);
    });
  }
}

export function playbookRoutes(app: FastifyInstance, plays: PlaybookService, limiter: MemoryRateLimiter) {
  const caller = (req: FastifyRequest): Caller => {
    const c = requireCaller(req);
    if (!limiter.admit(`write:${c.uid}`, hubLimits.write)) {
      throw new ApiError("resource_exhausted", "You're doing that too fast. Wait a minute and try again.");
    }
    return c;
  };
  type T = { Params: { teamId: string } };
  type P = { Params: { teamId: string; playId: string } };
  app.post<T>("/v1/teams/:teamId/plays", async (req, reply) => reply.code(201).send(await plays.create(caller(req), req.params.teamId, req.body)));
  app.put<P>("/v1/teams/:teamId/plays/:playId", async (req, reply) => {
    await plays.save(caller(req), req.params.teamId, req.params.playId, req.body);
    return reply.code(204).send();
  });
  app.delete<P>("/v1/teams/:teamId/plays/:playId", async (req, reply) => {
    await plays.remove(caller(req), req.params.teamId, req.params.playId);
    return reply.code(204).send();
  });
}
