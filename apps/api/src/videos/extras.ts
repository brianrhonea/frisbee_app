// Team video extras (redesign F4, F5, F6): notes, clips and comments on a
// video (teams/{id}/videos/{videoId}/comments), and tagging a video to one
// of the team's events (`eventId` on the video). API-only: firestore.rules
// lets members read comments but no client create them, and keeps
// `eventId` out of the video's create and update keys, so these checks are
// the only ones. (Managers may delete comments directly, only so the app's
// own video removal can clear them.)
import { tagVideoEventRequestSchema, videoCommentRequestSchema, videoLimits } from "@stall10/shared";
import type { FastifyInstance, FastifyRequest } from "fastify";
import { type Caller, requireCaller, type UserLookup } from "../auth.js";
import { ApiError, parseBody } from "../errors.js";
import { hubLimits } from "../hub/routes.js";
import { docIdParam } from "../ids.js";
import { limited, type MemoryRateLimiter } from "../limits/memory.js";
import { authorOf, checkNotMuted } from "../posts/author.js";
import type { DocQueries } from "../queries.js";
import { type Data, type DocStore, deleteField, serverTime } from "../store.js";
import { can, clip, isMember, isOrg, strings } from "../teams/access.js";

const p = {
  team: (t: string) => `teams/${t}`,
  event: (t: string, e: string) => `teams/${t}/events/${e}`,
  video: (t: string, v: string) => `teams/${t}/videos/${v}`,
  comments: (t: string, v: string) => `teams/${t}/videos/${v}/comments`,
  comment: (t: string, v: string, c: string) => `teams/${t}/videos/${v}/comments/${c}`,
};

/** Comments deleted per transaction when a video goes. */
export const commentChunk = 400;

const noTeam = () => new ApiError("not_found", "That team doesn't exist.");
const noVideo = () => new ApiError("not_found", "That video doesn't exist anymore.");

/** Who manages the team's videos (the videos rules' can(team(), 'manageTeam'), as a member). */
const manages = (team: Data, uid: string) => isMember(team, uid) && can(team, uid, "manageTeam");

/**
 * An event every member who watches the video may see: any team or group
 * event, and a community's events for everyone (as chat event cards).
 */
const seenByAll = (team: Data, event: Data) => !isOrg(team) || strings(event.audience).includes("everyone");

/** Deletes a removed video's notes and comments, a chunk at a time (VideoService.remove). */
export async function clearVideoComments(store: DocStore, queries: DocQueries, teamId: string, videoId: string): Promise<void> {
  for (;;) {
    const ids = await queries.ids(p.comments(teamId, videoId), commentChunk);
    if (ids.length === 0) return;
    await store.transact(async (tx) => {
      for (const id of ids) tx.delete(p.comment(teamId, videoId, docIdParam(id)));
    });
  }
}

export class VideoExtrasService {
  constructor(
    private readonly store: DocStore,
    private readonly users: UserLookup,
    private readonly now: () => number = Date.now,
  ) {}

  /** `POST .../videos/:videoId/comments`: any member adds a comment, a note at a time, or a clip. */
  async addComment(caller: Caller, rawTeam: unknown, rawVideo: unknown, body: unknown): Promise<{ id: string }> {
    const teamId = docIdParam(rawTeam);
    const videoId = docIdParam(rawVideo);
    const req = parseBody(videoCommentRequestSchema, body);
    await checkNotMuted(this.store, caller.uid, this.now());
    const me = await authorOf(this.store, this.users, caller);
    const id = this.store.newId(p.comments(teamId, videoId));
    await this.store.transact(async (tx) => {
      const [team, video] = await Promise.all([tx.get(p.team(teamId)), tx.get(p.video(teamId, videoId))]);
      if (!team) throw noTeam();
      if (!isMember(team, caller.uid)) throw new ApiError("permission_denied", "Only the team's members comment on its videos.");
      if (!video) throw noVideo();
      tx.create(p.comment(teamId, videoId, id), {
        authorId: caller.uid,
        authorName: clip(me.name, videoLimits.authorName),
        body: req.body,
        ...(req.atMs !== undefined && { atMs: req.atMs }),
        ...(req.endMs !== undefined && { endMs: req.endMs }),
        createdAt: serverTime,
      });
    });
    return { id };
  }

  /** `DELETE .../comments/:commentId`: its author, or a manager. Already gone: a no-op. */
  async removeComment(caller: Caller, rawTeam: unknown, rawVideo: unknown, rawComment: unknown): Promise<void> {
    const teamId = docIdParam(rawTeam);
    const videoId = docIdParam(rawVideo);
    const id = docIdParam(rawComment);
    await this.store.transact(async (tx) => {
      const [team, comment] = await Promise.all([tx.get(p.team(teamId)), tx.get(p.comment(teamId, videoId, id))]);
      if (!team) throw noTeam();
      if (!isMember(team, caller.uid)) throw new ApiError("permission_denied", "Only the team's members comment on its videos.");
      if (!comment) return;
      if (comment.authorId !== caller.uid && !manages(team, caller.uid)) {
        throw new ApiError("permission_denied", "Only its author or the team's admins can delete it.");
      }
      tx.delete(p.comment(teamId, videoId, id));
    });
  }

  /** `PUT .../videos/:videoId/event`: managers tag the video to a team event, or untag it (null). */
  async tagEvent(caller: Caller, rawTeam: unknown, rawVideo: unknown, body: unknown): Promise<void> {
    const teamId = docIdParam(rawTeam);
    const videoId = docIdParam(rawVideo);
    const req = parseBody(tagVideoEventRequestSchema, body);
    const eventId = req.eventId === null ? null : docIdParam(req.eventId);
    await this.store.transact(async (tx) => {
      const [team, video, event] = await Promise.all([
        tx.get(p.team(teamId)),
        tx.get(p.video(teamId, videoId)),
        eventId ? tx.get(p.event(teamId, eventId)) : Promise.resolve(null),
      ]);
      if (!team) throw noTeam();
      if (!manages(team, caller.uid)) throw new ApiError("permission_denied", "Only the team's admins can change its videos.");
      if (!video) throw noVideo();
      if (eventId === null) {
        if (video.eventId !== undefined) tx.update(p.video(teamId, videoId), { eventId: deleteField });
        return;
      }
      if (!event) throw new ApiError("not_found", "That event was deleted.");
      if (!seenByAll(team, event)) throw new ApiError("failed_precondition", "Only events for everyone in the community can be tagged.");
      if (video.eventId !== eventId) tx.update(p.video(teamId, videoId), { eventId });
    });
  }

}

type V = { Params: { teamId: string; videoId: string } };
type C = { Params: { teamId: string; videoId: string; commentId: string } };

/** Notes, comments and event tags on team videos (redesign F4–F6), as the signed-in caller. */
export function videoExtrasRoutes(app: FastifyInstance, extras: VideoExtrasService, limiter: MemoryRateLimiter) {
  const caller = (req: FastifyRequest, bucket: keyof typeof hubLimits): Caller => {
    const c = requireCaller(req);
    limited(limiter, `${bucket}:${c.uid}`, hubLimits[bucket]);
    return c;
  };
  app.post<V>("/v1/teams/:teamId/videos/:videoId/comments", async (req, reply) =>
    reply.code(201).send(await extras.addComment(caller(req, "chat"), req.params.teamId, req.params.videoId, req.body)),
  );
  app.delete<C>("/v1/teams/:teamId/videos/:videoId/comments/:commentId", async (req, reply) => {
    await extras.removeComment(caller(req, "respond"), req.params.teamId, req.params.videoId, req.params.commentId);
    return reply.code(204).send();
  });
  app.put<V>("/v1/teams/:teamId/videos/:videoId/event", async (req, reply) => {
    await extras.tagEvent(caller(req, "write"), req.params.teamId, req.params.videoId, req.body);
    return reply.code(204).send();
  });
}
