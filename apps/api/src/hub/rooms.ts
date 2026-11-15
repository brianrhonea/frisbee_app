// A team's chat rooms and folders (teams/{id}/chats, chatFolders): ports of
// their rules. Members with manageChats make, edit, arrange and delete
// them; a room is deleted with its messages and files, and only by
// someone who can read it.
import {
  chatLayoutRequestSchema,
  chatRoomLimits,
  saveChatFolderRequestSchema,
  saveChatRoomRequestSchema,
} from "@stall10/shared";
import type { FastifyInstance, FastifyRequest } from "fastify";
import type { z } from "zod";
import { type Caller, requireCaller } from "../auth.js";
import { ApiError, parseBody } from "../errors.js";
import { docIdParam } from "../ids.js";
import { limited, type MemoryRateLimiter } from "../limits/memory.js";
import type { MediaStorage } from "../media/storage.js";
import { type Data, type DocStore, serverTime } from "../store.js";
import { can, isMember, strings } from "../teams/access.js";
import type { TeamRepository } from "../teams/repository.js";
import { canReadRoom } from "./access.js";
import { hubLimits } from "./routes.js";

const p = {
  team: (t: string) => `teams/${t}`,
  room: (t: string, r: string) => `teams/${t}/chats/${r}`,
  rooms: (t: string) => `teams/${t}/chats`,
  folder: (t: string, f: string) => `teams/${t}/chatFolders/${f}`,
  folders: (t: string) => `teams/${t}/chatFolders`,
};

/** The room every team keeps (ChatRoom.generalId). */
export const generalRoomId = "general";

const denied = () => new ApiError("permission_denied", "You can't manage this team's chats.");
const noTeam = () => new ApiError("not_found", "That team doesn't exist.");

/** The access lists as stored, with single members limited to the team's members. */
export function accessFields(team: Data, access: z.output<typeof saveChatRoomRequestSchema>["access"]) {
  const members = new Set(strings(team.memberIds));
  const sorted = (xs: string[]) => [...new Set(xs)].sort();
  return {
    readRoles: sorted(access.readRoles),
    writeRoles: sorted(access.writeRoles),
    readUsers: sorted(access.readUsers.filter((u) => members.has(u))),
    writeUsers: sorted(access.writeUsers.filter((u) => members.has(u))),
  };
}

export class ChatAdmin {
  constructor(
    private readonly store: DocStore,
    private readonly teams: Pick<TeamRepository, "deleteTree">,
    private readonly media: MediaStorage | undefined,
  ) {}

  /** The team, if the caller is a member who can manage its chats. */
  private async manager(teamId: string, caller: Caller): Promise<Data> {
    const team = await this.store.get(p.team(teamId));
    if (!team) throw noTeam();
    if (!isMember(team, caller.uid) || !can(team, caller.uid, "manageChats")) throw denied();
    return team;
  }

  async createRoom(caller: Caller, rawTeam: unknown, body: unknown): Promise<{ id: string }> {
    const teamId = docIdParam(rawTeam);
    const req = parseBody(saveChatRoomRequestSchema, body);
    const team = await this.manager(teamId, caller);
    const existing = await this.store.list(p.rooms(teamId), chatRoomLimits.rooms + 1);
    if (existing.length >= chatRoomLimits.rooms) throw new ApiError("failed_precondition", `A team can have ${chatRoomLimits.rooms} rooms.`);
    const id = this.store.newId(p.rooms(teamId));
    await this.store.transact(async (tx) => {
      const t = await tx.get(p.team(teamId));
      if (!t || !can(t, caller.uid, "manageChats")) throw denied();
      if (req.folderId && !(await tx.get(p.folder(teamId, req.folderId)))) throw new ApiError("not_found", "That folder doesn't exist.");
      tx.create(p.room(teamId, id), {
        name: req.name,
        kind: req.kind,
        ...accessFields(team, req.access),
        folderId: req.folderId,
        position: existing.length,
        createdBy: caller.uid,
        createdAt: serverTime,
      });
    });
    return { id };
  }

  /** Name, folder and access; the kind never changes. */
  async editRoom(caller: Caller, rawTeam: unknown, rawRoom: unknown, body: unknown): Promise<void> {
    const teamId = docIdParam(rawTeam);
    const roomId = docIdParam(rawRoom);
    const req = parseBody(saveChatRoomRequestSchema, body);
    const team = await this.manager(teamId, caller);
    await this.store.transact(async (tx) => {
      const [t, room, folder] = await Promise.all([
        tx.get(p.team(teamId)),
        tx.get(p.room(teamId, roomId)),
        req.folderId ? tx.get(p.folder(teamId, req.folderId)) : Promise.resolve(null),
      ]);
      if (!t || !can(t, caller.uid, "manageChats")) throw denied();
      if (!room) throw new ApiError("not_found", "That room doesn't exist.");
      if (req.folderId && !folder) throw new ApiError("not_found", "That folder doesn't exist.");
      if ((room.kind ?? "text") !== req.kind) throw new ApiError("invalid_argument", "A room's kind can't change.");
      tx.update(p.room(teamId, roomId), { name: req.name, ...accessFields(team, req.access), folderId: req.folderId });
    });
  }

  /** The room, its messages and its files; General stays. */
  async deleteRoom(caller: Caller, rawTeam: unknown, rawRoom: unknown): Promise<void> {
    const teamId = docIdParam(rawTeam);
    const roomId = docIdParam(rawRoom);
    if (roomId === generalRoomId) throw new ApiError("failed_precondition", "Every team keeps its General room.");
    const team = await this.manager(teamId, caller);
    const room = await this.store.get(p.room(teamId, roomId));
    if (!room) return;
    if (!canReadRoom(team, caller.uid, room)) throw denied();
    await this.teams.deleteTree(p.room(teamId, roomId));
    // Left behind, the files are unreadable (storage.rules need the room), so a failure is logged, not fatal.
    await this.media?.deletePrefix(`teams/${teamId}/chats/${roomId}/`).catch((e: unknown) => console.warn(`room ${teamId}/${roomId}: files not deleted`, e));
  }

  async createFolder(caller: Caller, rawTeam: unknown, body: unknown): Promise<{ id: string }> {
    const teamId = docIdParam(rawTeam);
    const req = parseBody(saveChatFolderRequestSchema, body);
    const team = await this.manager(teamId, caller);
    const existing = await this.store.list(p.folders(teamId), chatRoomLimits.folders + 1);
    if (existing.length >= chatRoomLimits.folders) throw new ApiError("failed_precondition", `A team can have ${chatRoomLimits.folders} folders.`);
    // Short ids: rooms store theirs in folderId (40 characters at most).
    const id = this.store.newId(p.folders(teamId)).slice(0, chatRoomLimits.folderId);
    await this.store.transact(async (tx) => {
      const t = await tx.get(p.team(teamId));
      if (!t || !can(t, caller.uid, "manageChats")) throw denied();
      tx.create(p.folder(teamId, id), {
        name: req.name,
        position: existing.length,
        ...accessFields(team, req.access),
        createdBy: caller.uid,
        createdAt: serverTime,
      });
    });
    return { id };
  }

  async editFolder(caller: Caller, rawTeam: unknown, rawFolder: unknown, body: unknown): Promise<void> {
    const teamId = docIdParam(rawTeam);
    const folderId = docIdParam(rawFolder);
    const req = parseBody(saveChatFolderRequestSchema, body);
    const team = await this.manager(teamId, caller);
    await this.store.transact(async (tx) => {
      const [t, folder] = await Promise.all([tx.get(p.team(teamId)), tx.get(p.folder(teamId, folderId))]);
      if (!t || !can(t, caller.uid, "manageChats")) throw denied();
      if (!folder) throw new ApiError("not_found", "That folder doesn't exist.");
      tx.update(p.folder(teamId, folderId), { name: req.name, ...accessFields(team, req.access) });
    });
  }

  /** The folder; its rooms move out of it. */
  async deleteFolder(caller: Caller, rawTeam: unknown, rawFolder: unknown): Promise<void> {
    const teamId = docIdParam(rawTeam);
    const folderId = docIdParam(rawFolder);
    await this.manager(teamId, caller);
    const rooms = (await this.store.list(p.rooms(teamId), chatRoomLimits.rooms * 2)).filter((r) => r.data.folderId === folderId);
    await this.store.transact(async (tx) => {
      const [t, folder] = await Promise.all([tx.get(p.team(teamId)), tx.get(p.folder(teamId, folderId))]);
      if (!t || !can(t, caller.uid, "manageChats")) throw denied();
      if (!folder) return;
      for (const r of rooms) tx.update(p.room(teamId, r.id), { folderId: null });
      tx.delete(p.folder(teamId, folderId));
    });
  }

  /** Folder and room order, and each room's folder. Unknown ids are refused. */
  async arrange(caller: Caller, rawTeam: unknown, body: unknown): Promise<void> {
    const teamId = docIdParam(rawTeam);
    const req = parseBody(chatLayoutRequestSchema, body);
    await this.manager(teamId, caller);
    await this.store.transact(async (tx) => {
      const t = await tx.get(p.team(teamId));
      if (!t || !can(t, caller.uid, "manageChats")) throw denied();
      const folderIds = new Set([...req.folders.map((f) => f.id), ...req.rooms.flatMap((r) => (r.folderId ? [r.folderId] : []))]);
      const [folders, rooms] = await Promise.all([
        Promise.all([...folderIds].map(async (id) => [id, await tx.get(p.folder(teamId, docIdParam(id)))] as const)),
        Promise.all(req.rooms.map((r) => tx.get(p.room(teamId, docIdParam(r.id))))),
      ]);
      const known = new Map(folders);
      for (const [id, f] of known) if (!f) throw new ApiError("not_found", `There's no folder ${id}.`);
      rooms.forEach((r, i) => {
        if (!r) throw new ApiError("not_found", `There's no room ${req.rooms[i]!.id}.`);
      });
      for (const f of req.folders) tx.update(p.folder(teamId, f.id), { position: f.position });
      for (const r of req.rooms) tx.update(p.room(teamId, r.id), { position: r.position, folderId: r.folderId });
    });
  }
}

/** The chat admin routes (manageChats), on the hub's write limit. */
export function chatAdminRoutes(app: FastifyInstance, chats: ChatAdmin, limiter: MemoryRateLimiter) {
  const caller = (req: FastifyRequest): Caller => {
    const c = requireCaller(req);
    limited(limiter, `write:${c.uid}`, hubLimits.write);
    return c;
  };
  type T = { Params: { teamId: string } };
  type R = { Params: { teamId: string; roomId: string } };
  type F = { Params: { teamId: string; folderId: string } };
  app.post<T>("/v1/teams/:teamId/chat-rooms", async (req, reply) => reply.code(201).send(await chats.createRoom(caller(req), req.params.teamId, req.body)));
  app.patch<R>("/v1/teams/:teamId/chat-rooms/:roomId", async (req, reply) => {
    await chats.editRoom(caller(req), req.params.teamId, req.params.roomId, req.body);
    return reply.code(204).send();
  });
  app.delete<R>("/v1/teams/:teamId/chat-rooms/:roomId", async (req, reply) => {
    await chats.deleteRoom(caller(req), req.params.teamId, req.params.roomId);
    return reply.code(204).send();
  });
  app.post<T>("/v1/teams/:teamId/chat-folders", async (req, reply) => reply.code(201).send(await chats.createFolder(caller(req), req.params.teamId, req.body)));
  app.patch<F>("/v1/teams/:teamId/chat-folders/:folderId", async (req, reply) => {
    await chats.editFolder(caller(req), req.params.teamId, req.params.folderId, req.body);
    return reply.code(204).send();
  });
  app.delete<F>("/v1/teams/:teamId/chat-folders/:folderId", async (req, reply) => {
    await chats.deleteFolder(caller(req), req.params.teamId, req.params.folderId);
    return reply.code(204).send();
  });
  app.put<T>("/v1/teams/:teamId/chat-layout", async (req, reply) => {
    await chats.arrange(caller(req), req.params.teamId, req.body);
    return reply.code(204).send();
  });
}
