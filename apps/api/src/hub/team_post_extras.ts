// Team feed extras (redesign F24): pinned team posts and comments on team
// posts (teams/{id}/posts/{postId}/comments). API-only: firestore.rules
// keeps pinnedAt, pinnedBy and commentCount out of a team post's keys and
// lets members only read comments, so these checks are the only ones. The
// post's commentCount is kept by the follows-teamPostCommentCount function
// (as people's posts' counts are), which also counts comments that go with
// a deleted account; follows-teamPostDeleted clears a deleted post's
// comments.
import {
  pinTeamPostRequestSchema,
  teamPostCommentLimits,
  teamPostCommentRequestSchema,
  teamPostPinsFullMessage,
  teamPostPinsMax,
} from "@stall10/shared";
import type { FastifyInstance, FastifyRequest } from "fastify";
import { type Caller, requireCaller, type UserLookup } from "../auth.js";
import { ApiError, parseBody } from "../errors.js";
import { docIdParam } from "../ids.js";
import { limited, type MemoryRateLimiter } from "../limits/memory.js";
import { authorOf, checkNotMuted } from "../posts/author.js";
import { type Data, type DocStore, deleteField, serverTime } from "../store.js";
import { can, clip, isMember, strings } from "../teams/access.js";
import { hubLimits } from "./routes.js";

const p = {
  team: (t: string) => `teams/${t}`,
  post: (t: string, id: string) => `teams/${t}/posts/${id}`,
  comments: (t: string, id: string) => `teams/${t}/posts/${id}/comments`,
  comment: (t: string, id: string, c: string) => `teams/${t}/posts/${id}/comments/${c}`,
  /** Server-only: the pinned posts' ids, newest first, to hold the limit. */
  pins: (t: string) => `teams/${t}/feed/pins`,
};

const denied = (m: string) => new ApiError("permission_denied", m);
const noTeam = () => new ApiError("not_found", "That team doesn't exist anymore.");
const noPost = () => new ApiError("not_found", "This post was deleted.");

/** Who pins and moderates comments: the team's admins (manageTeam), as for its posts. */
export const managesFeed = (team: Data, uid: string) => isMember(team, uid) && can(team, uid, "manageTeam");

export class TeamPostExtrasService {
  constructor(
    private readonly store: DocStore,
    private readonly users: UserLookup,
    private readonly now: () => number = Date.now,
  ) {}

  /**
   * Pins a post (again: a no-op). A full feed refuses unless [unpin] names
   * one of its pins to take down in the same write. Pins whose posts were
   * deleted don't count.
   */
  async pin(caller: Caller, rawTeam: unknown, rawPost: unknown, body: unknown): Promise<void> {
    const teamId = docIdParam(rawTeam);
    const id = docIdParam(rawPost);
    const { unpin } = parseBody(pinTeamPostRequestSchema, body ?? {});
    const swap = unpin === undefined ? undefined : docIdParam(unpin);
    await this.store.transact(async (tx) => {
      const [team, post, state] = await Promise.all([tx.get(p.team(teamId)), tx.get(p.post(teamId, id)), tx.get(p.pins(teamId))]);
      if (!team) throw noTeam();
      if (!managesFeed(team, caller.uid)) throw denied("Only the team's admins pin posts.");
      if (!post) throw noPost();
      const stored = strings(state?.ids)
        .filter((x) => x !== id)
        .slice(0, teamPostPinsMax * 2);
      const there = await Promise.all(stored.map((x) => tx.get(p.post(teamId, x))));
      let pins = stored.filter((_, i) => there[i] !== null);
      if (swap !== undefined && pins.includes(swap)) {
        pins = pins.filter((x) => x !== swap);
        tx.update(p.post(teamId, swap), { pinnedAt: deleteField, pinnedBy: deleteField });
      }
      if (pins.length >= teamPostPinsMax) throw new ApiError("failed_precondition", teamPostPinsFullMessage);
      tx.set(p.pins(teamId), { ids: [id, ...pins] });
      if (!post.pinnedAt) tx.update(p.post(teamId, id), { pinnedAt: serverTime, pinnedBy: caller.uid });
    });
  }

  /** Unpins a post (one that's gone, or never pinned: a no-op). */
  async unpin(caller: Caller, rawTeam: unknown, rawPost: unknown): Promise<void> {
    const teamId = docIdParam(rawTeam);
    const id = docIdParam(rawPost);
    await this.store.transact(async (tx) => {
      const [team, post, state] = await Promise.all([tx.get(p.team(teamId)), tx.get(p.post(teamId, id)), tx.get(p.pins(teamId))]);
      if (!team) throw noTeam();
      if (!managesFeed(team, caller.uid)) throw denied("Only the team's admins unpin posts.");
      const pins = strings(state?.ids);
      if (pins.includes(id)) tx.set(p.pins(teamId), { ids: pins.filter((x) => x !== id) });
      if (post?.pinnedAt) tx.update(p.post(teamId, id), { pinnedAt: deleteField, pinnedBy: deleteField });
    });
  }

  /** `POST .../posts/:postId/comments`: any member comments on any of the team's posts. */
  async addComment(caller: Caller, rawTeam: unknown, rawPost: unknown, body: unknown): Promise<{ id: string }> {
    const teamId = docIdParam(rawTeam);
    const postId = docIdParam(rawPost);
    const req = parseBody(teamPostCommentRequestSchema, body);
    await checkNotMuted(this.store, caller.uid, this.now());
    const me = await authorOf(this.store, this.users, caller);
    const id = this.store.newId(p.comments(teamId, postId));
    await this.store.transact(async (tx) => {
      const [team, post] = await Promise.all([tx.get(p.team(teamId)), tx.get(p.post(teamId, postId))]);
      if (!team) throw noTeam();
      if (!isMember(team, caller.uid)) throw denied("Only the team's members comment on its posts.");
      if (!post) throw noPost();
      tx.create(p.comment(teamId, postId, id), {
        authorId: caller.uid,
        authorName: clip(me.name, teamPostCommentLimits.authorName),
        body: req.body,
        createdAt: serverTime,
      });
    });
    return { id };
  }

  /** `DELETE .../comments/:commentId`: its author, or a team admin. Already gone: a no-op. */
  async removeComment(caller: Caller, rawTeam: unknown, rawPost: unknown, rawComment: unknown): Promise<void> {
    const teamId = docIdParam(rawTeam);
    const postId = docIdParam(rawPost);
    const id = docIdParam(rawComment);
    await this.store.transact(async (tx) => {
      const [team, comment] = await Promise.all([tx.get(p.team(teamId)), tx.get(p.comment(teamId, postId, id))]);
      if (!team) throw noTeam();
      if (!isMember(team, caller.uid)) throw denied("Only the team's members comment on its posts.");
      if (!comment) return;
      if (comment.authorId !== caller.uid && !managesFeed(team, caller.uid)) {
        throw denied("Only its author or the team's admins can delete it.");
      }
      tx.delete(p.comment(teamId, postId, id));
    });
  }
}

type P = { Params: { teamId: string; postId: string } };
type C = { Params: { teamId: string; postId: string; commentId: string } };

/** Pinned team posts and comments on them (redesign F24), as the signed-in caller. */
export function teamPostExtrasRoutes(app: FastifyInstance, extras: TeamPostExtrasService, limiter: MemoryRateLimiter) {
  const caller = (req: FastifyRequest, bucket: keyof typeof hubLimits): Caller => {
    const c = requireCaller(req);
    limited(limiter, `${bucket}:${c.uid}`, hubLimits[bucket]);
    return c;
  };
  const pinPath = "/v1/teams/:teamId/posts/:postId/pin";
  app.put<P>(pinPath, async (req, reply) => {
    await extras.pin(caller(req, "respond"), req.params.teamId, req.params.postId, req.body);
    return reply.code(204).send();
  });
  app.delete<P>(pinPath, async (req, reply) => {
    await extras.unpin(caller(req, "respond"), req.params.teamId, req.params.postId);
    return reply.code(204).send();
  });
  app.post<P>("/v1/teams/:teamId/posts/:postId/comments", async (req, reply) =>
    reply.code(201).send(await extras.addComment(caller(req, "chat"), req.params.teamId, req.params.postId, req.body)),
  );
  app.delete<C>("/v1/teams/:teamId/posts/:postId/comments/:commentId", async (req, reply) => {
    await extras.removeComment(caller(req, "respond"), req.params.teamId, req.params.postId, req.params.commentId);
    return reply.code(204).send();
  });
}
