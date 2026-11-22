// A team's Videos section (teams/{id}/videos and videoFolders): the
// `match /videos/{videoId}` and `match /videoFolders/{folderId}` rules
// ported. Members who manage the team add YouTube videos, edit, file and
// remove videos, and manage folders. validVideo and validFile run on the
// whole document each write leaves, as the rules do. Uploading files stays
// in the app until the transcode job runs (ARCHITECTURE.md §10, Media).
import {
  createVideoRequestSchema,
  editVideoRequestSchema,
  saveVideoFolderRequestSchema,
  videoFileContentTypes,
  videoLimits,
  youtubeIdPattern,
} from "@stall10/shared";
import type { FastifyInstance, FastifyRequest } from "fastify";
import { type Caller, requireCaller, type UserLookup } from "../auth.js";
import { ApiError, parseBody } from "../errors.js";
import { hubLimits } from "../hub/routes.js";
import { docIdParam } from "../ids.js";
import { limited, type MemoryRateLimiter } from "../limits/memory.js";
import type { MediaStorage } from "../media/storage.js";
import { authorOf } from "../posts/author.js";
import type { DocQueries } from "../queries.js";
import { type Data, type DocStore, serverTime } from "../store.js";
import { can, clip, isMap, isMember } from "../teams/access.js";
import { clearVideoComments } from "./extras.js";

const p = {
  team: (t: string) => `teams/${t}`,
  videos: (t: string) => `teams/${t}/videos`,
  video: (t: string, v: string) => `teams/${t}/videos/${v}`,
  folders: (t: string) => `teams/${t}/videoFolders`,
  folder: (t: string, f: string) => `teams/${t}/videoFolders/${f}`,
};

/** Videos unsorted per transaction, as the app's batches (400). */
export const unsortChunk = 400;

const denied = () => new ApiError("permission_denied", "Only the team's admins can change its videos.");
const noTeam = () => new ApiError("not_found", "That team doesn't exist.");
const noVideo = () => new ApiError("not_found", "That video doesn't exist anymore.");
const noFolder = () => new ApiError("not_found", "That folder doesn't exist anymore.");

/** Firestore rules count characters, not UTF-16 units. */
const chars = (s: string) => [...s].length;
const validString = (v: unknown, max: number): v is string => typeof v === "string" && chars(v) <= max;
const escape = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

/** Where an uploaded file may live: `teams/{teamId}/videos/{videoId}/[^/]+`. */
export function filePathOk(path: unknown, teamId: string, videoId: string): path is string {
  return typeof path === "string" && new RegExp(`^teams/${escape(teamId)}/videos/${escape(videoId)}/[^/]+$`).test(path);
}

/** validFile(f) in firestore.rules; the problem, or null. */
export function fileProblem(f: unknown, teamId: string, videoId: string): string | null {
  if (!isMap(f)) return "The video's file isn't valid.";
  if (!Object.keys(f).every((k) => ["path", "name", "size", "contentType"].includes(k))) return "The video's file has unexpected fields.";
  if (!filePathOk(f.path, teamId, videoId)) return "The video's file is in the wrong place.";
  if (!validString(f.name, videoLimits.fileName) || f.name.length === 0) return "The video's file name isn't valid.";
  if (typeof f.size !== "number" || !Number.isInteger(f.size) || f.size <= 0 || f.size > videoLimits.fileBytes) return "The video's file size isn't valid.";
  if (typeof f.contentType !== "string" || !videoFileContentTypes.includes(f.contentType)) return "The video's file type isn't one we can play.";
  return null;
}

/** validVideo(v) in firestore.rules, on the whole document; the problem, or null. */
export function videoProblem(v: Data, teamId: string, videoId: string): string | null {
  const file = v.file ?? null;
  const folder = v.folderId ?? "";
  if (typeof folder !== "string" || chars(folder) > videoLimits.folderId) return "That folder isn't valid.";
  if (typeof v.title !== "string" || v.title.length === 0 || chars(v.title) > videoLimits.title) return "Give the video a title of up to 100 characters.";
  if (!validString(v.description, videoLimits.description)) return "The description can be up to 2000 characters.";
  if (typeof v.youtubeId !== "string") return "Paste a YouTube link.";
  if (file === null) return youtubeIdPattern.test(v.youtubeId) ? null : "Paste a YouTube link.";
  if (v.youtubeId !== "") return "An uploaded video can't also be a YouTube link.";
  return fileProblem(file, teamId, videoId);
}

export class VideoService {
  constructor(
    private readonly store: DocStore,
    private readonly users: UserLookup,
    private readonly media: MediaStorage | undefined,
    private readonly queries: DocQueries,
  ) {}

  /** can(team(), 'manageTeam'), as a member (like the playbook). */
  private check(team: Data | null, caller: Caller): Data {
    if (!team) throw noTeam();
    if (!isMember(team, caller.uid) || !can(team, caller.uid, "manageTeam")) throw denied();
    return team;
  }

  /** `POST /v1/teams/:teamId/videos`: a YouTube video. */
  async create(caller: Caller, rawTeam: unknown, body: unknown): Promise<{ id: string }> {
    const teamId = docIdParam(rawTeam);
    const req = parseBody(createVideoRequestSchema, body);
    const folderId = req.folderId ? docIdParam(req.folderId) : "";
    this.check(await this.store.get(p.team(teamId)), caller);
    const me = await authorOf(this.store, this.users, caller);
    const id = this.store.newId(p.videos(teamId));
    await this.store.transact(async (tx) => {
      const [team, folder] = await Promise.all([tx.get(p.team(teamId)), folderId ? tx.get(p.folder(teamId, folderId)) : Promise.resolve(null)]);
      this.check(team, caller);
      if (folderId && !folder) throw noFolder();
      // Exactly the create rule's keys (TeamVideo.toCreateMap and _created).
      const doc: Data = {
        youtubeId: req.youtubeId,
        file: null,
        folderId,
        title: req.title,
        description: req.description,
        authorId: caller.uid,
        authorName: clip(me.name, videoLimits.authorName),
        createdAt: serverTime,
        updatedAt: serverTime,
      };
      const problem = videoProblem(doc, teamId, id);
      if (problem) throw new ApiError("invalid_argument", problem);
      tx.create(p.video(teamId, id), doc);
    });
    return { id };
  }

  /** `PATCH /v1/teams/:teamId/videos/:videoId`: edit, or move to a folder. */
  async edit(caller: Caller, rawTeam: unknown, rawVideo: unknown, body: unknown): Promise<void> {
    const teamId = docIdParam(rawTeam);
    const videoId = docIdParam(rawVideo);
    const req = parseBody(editVideoRequestSchema, body);
    const folderId = req.folderId ? docIdParam(req.folderId) : req.folderId;
    await this.store.transact(async (tx) => {
      const [team, video] = await Promise.all([tx.get(p.team(teamId)), tx.get(p.video(teamId, videoId))]);
      this.check(team, caller);
      if (!video) throw noVideo();
      const moving = folderId !== undefined && folderId !== "" && folderId !== video.folderId;
      if (moving && !(await tx.get(p.folder(teamId, folderId)))) throw noFolder();
      // changed().hasOnly(['youtubeId', 'folderId', 'title', 'description', 'updatedAt']).
      const changes: Data = { updatedAt: serverTime };
      if (req.youtubeId !== undefined) changes.youtubeId = req.youtubeId;
      if (folderId !== undefined) changes.folderId = folderId;
      if (req.title !== undefined) changes.title = req.title;
      if (req.description !== undefined) changes.description = req.description;
      const problem = videoProblem({ ...video, ...changes }, teamId, videoId);
      if (problem) throw new ApiError("invalid_argument", problem);
      tx.update(p.video(teamId, videoId), changes);
    });
  }

  /**
   * `DELETE /v1/teams/:teamId/videos/:videoId`. The listing goes first, so a
   * failed file delete never leaves a video pointing at nothing; then its
   * notes and comments, and its uploaded file, if it's where uploads live.
   */
  async remove(caller: Caller, rawTeam: unknown, rawVideo: unknown): Promise<void> {
    const teamId = docIdParam(rawTeam);
    const videoId = docIdParam(rawVideo);
    const gone = await this.store.transact(async (tx) => {
      const [team, video] = await Promise.all([tx.get(p.team(teamId)), tx.get(p.video(teamId, videoId))]);
      this.check(team, caller);
      if (!video) return null;
      tx.delete(p.video(teamId, videoId));
      const file = isMap(video.file) ? video.file : null;
      return { path: file && filePathOk(file.path, teamId, videoId) ? file.path : null };
    });
    if (!gone) return;
    const { path } = gone;
    // Its notes and comments (F4, F5) go with it.
    await clearVideoComments(this.store, this.queries, teamId, videoId).catch((e: unknown) => console.warn(`video ${teamId}/${videoId}: comments not all deleted`, e));
    // The video is gone either way; a file left behind is only logged.
    if (path && this.media) await this.media.delete(path).catch((e: unknown) => console.warn(`video ${teamId}/${videoId}: file ${path} not deleted`, e));
  }

  /** `POST /v1/teams/:teamId/video-folders`. */
  async createFolder(caller: Caller, rawTeam: unknown, body: unknown): Promise<{ id: string }> {
    const teamId = docIdParam(rawTeam);
    const req = parseBody(saveVideoFolderRequestSchema, body);
    const id = this.store.newId(p.folders(teamId)).slice(0, videoLimits.folderId);
    await this.store.transact(async (tx) => {
      this.check(await tx.get(p.team(teamId)), caller);
      // keys().hasOnly(['name', 'createdAt']), createdAt == request.time.
      tx.create(p.folder(teamId, id), { name: req.name, createdAt: serverTime });
    });
    return { id };
  }

  /** `PATCH /v1/teams/:teamId/video-folders/:folderId`: renames it. */
  async renameFolder(caller: Caller, rawTeam: unknown, rawFolder: unknown, body: unknown): Promise<void> {
    const teamId = docIdParam(rawTeam);
    const folderId = docIdParam(rawFolder);
    const req = parseBody(saveVideoFolderRequestSchema, body);
    await this.store.transact(async (tx) => {
      const [team, folder] = await Promise.all([tx.get(p.team(teamId)), tx.get(p.folder(teamId, folderId))]);
      this.check(team, caller);
      if (!folder) throw noFolder();
      tx.update(p.folder(teamId, folderId), { name: req.name });
    });
  }

  /**
   * `DELETE /v1/teams/:teamId/video-folders/:folderId`. As the app does,
   * its videos are unsorted first (folderId '', in chunks), so none is left
   * in a missing folder, then the folder goes.
   */
  async deleteFolder(caller: Caller, rawTeam: unknown, rawFolder: unknown): Promise<void> {
    const teamId = docIdParam(rawTeam);
    const folderId = docIdParam(rawFolder);
    this.check(await this.store.get(p.team(teamId)), caller);
    // A page of the folder's video ids at a time, until none are left in it.
    for (;;) {
      const ids = (await this.queries.ids(p.videos(teamId), unsortChunk, { folderId })).map((id) => docIdParam(id));
      if (ids.length === 0) break;
      const moved = await this.store.transact(async (tx) => {
        const [team, ...videos] = await Promise.all([tx.get(p.team(teamId)), ...ids.map((id) => tx.get(p.video(teamId, id)))]);
        this.check(team, caller);
        const moves: string[] = [];
        for (const [j, video] of videos.entries()) {
          const id = ids[j]!;
          // Gone, or moved since the ids were read.
          if (!video || video.folderId !== folderId) continue;
          const problem = videoProblem({ ...video, folderId: "" }, teamId, id);
          if (problem) throw new ApiError("failed_precondition", `A video in this folder can't be changed: ${problem}`);
          moves.push(id);
        }
        for (const id of moves) tx.update(p.video(teamId, id), { folderId: "", updatedAt: serverTime });
        return moves.length;
      });
      // Nothing moved: the query only saw videos already moved on.
      if (moved === 0) break;
    }
    await this.store.transact(async (tx) => {
      const [team, folder] = await Promise.all([tx.get(p.team(teamId)), tx.get(p.folder(teamId, folderId))]);
      this.check(team, caller);
      if (folder) tx.delete(p.folder(teamId, folderId));
    });
  }
}

/** The video routes (manageTeam), on the hub's write limit. */
export function videoRoutes(app: FastifyInstance, videos: VideoService, limiter: MemoryRateLimiter) {
  const caller = (req: FastifyRequest): Caller => {
    const c = requireCaller(req);
    limited(limiter, `write:${c.uid}`, hubLimits.write);
    return c;
  };
  type T = { Params: { teamId: string } };
  type V = { Params: { teamId: string; videoId: string } };
  type F = { Params: { teamId: string; folderId: string } };
  app.post<T>("/v1/teams/:teamId/videos", async (req, reply) => reply.code(201).send(await videos.create(caller(req), req.params.teamId, req.body)));
  app.patch<V>("/v1/teams/:teamId/videos/:videoId", async (req, reply) => {
    await videos.edit(caller(req), req.params.teamId, req.params.videoId, req.body);
    return reply.code(204).send();
  });
  app.delete<V>("/v1/teams/:teamId/videos/:videoId", async (req, reply) => {
    await videos.remove(caller(req), req.params.teamId, req.params.videoId);
    return reply.code(204).send();
  });
  app.post<T>("/v1/teams/:teamId/video-folders", async (req, reply) => reply.code(201).send(await videos.createFolder(caller(req), req.params.teamId, req.body)));
  app.patch<F>("/v1/teams/:teamId/video-folders/:folderId", async (req, reply) => {
    await videos.renameFolder(caller(req), req.params.teamId, req.params.folderId, req.body);
    return reply.code(204).send();
  });
  app.delete<F>("/v1/teams/:teamId/video-folders/:folderId", async (req, reply) => {
    await videos.deleteFolder(caller(req), req.params.teamId, req.params.folderId);
    return reply.code(204).send();
  });
}
