// Discord server template imports for the website: the discord-previewTemplate
// callable (firebase/functions/src/discord/functions.ts) as an API route,
// and applying a previewed plan with the writes the app's
// DiscordImportRepositoryFirebase makes. The Admin SDK skips
// firestore.rules, so each write checks what its rule checks:
//  - the team doc: setRoles() (the owner; roles and orgRoles maps of at most
//    50; memberRoles and memberPerms only for members; members unchanged);
//  - chatFolders and chats create: can(team, 'manageChats'), validFolder /
//    validRoom / validAccess, createdBy the caller, createdAt the server's;
//  - moving rooms out of a community: ChatAdmin's deleteRoom/deleteFolder.
import { randomInt } from "node:crypto";
import {
  chatRoomLimits,
  cleanMemberRoles,
  type DiscordImport,
  type DiscordImportResult,
  discordImportRequestSchema,
  discordPreviewRequestSchema,
  emptiedFolders,
  type ExistingFolder,
  type ExistingRoom,
  type ImportPlan,
  type ImportTeam,
  importIsEmpty,
  movingRooms,
  newRoleId,
  planFor,
  planImport,
  roleLimits,
  rolesData,
  splitPlan,
  splitTeams,
  storedAccess,
  teamChatImport,
  teamChatImportIsEmpty,
} from "@stall10/shared";
import type { FastifyInstance, FastifyRequest } from "fastify";
import { type Caller, requireCaller } from "../auth.js";
import { ApiError, parseBody } from "../errors.js";
import { accessFields, type ChatAdmin } from "../hub/rooms.js";
import { hubLimits } from "../hub/routes.js";
import { docIdParam } from "../ids.js";
import type { MemoryRateLimiter } from "../limits/memory.js";
import type { Limit } from "../limits/model.js";
import { type Data, type DocStore, serverTime } from "../store.js";
import { can, isOrg, isOwner, mapOf, strings } from "../teams/access.js";
import { type GuildTemplate, mapTemplate, templateCode } from "./template.js";

export type Fetch = (url: string, init: RequestInit) => Promise<Response>;

const minute = 60_000;

/** Previews call Discord, so they get their own small bucket. */
export const discordRouteLimits = {
  preview: { max: 10, windowMs: minute },
  import: hubLimits.write,
} satisfies Record<string, Limit>;

/** The only host the API fetches templates from. */
export const discordTemplateUrl = (code: string) => `https://discord.com/api/v10/guilds/templates/${encodeURIComponent(code)}`;
/** As the callable: 10 seconds, and (new here) at most 2 MB of JSON. */
export const discordFetchTimeoutMs = 10_000;
export const discordTemplateBytesMax = 2 * 1024 * 1024;

const p = {
  team: (t: string) => `teams/${t}`,
  room: (t: string, r: string) => `teams/${t}/chats/${r}`,
  rooms: (t: string) => `teams/${t}/chats`,
  folder: (t: string, f: string) => `teams/${t}/chatFolders/${f}`,
  folders: (t: string) => `teams/${t}/chatFolders`,
  /**
   * API-only (no rule lets clients near it): how many imports have written
   * to a team. Each import's transaction reads and bumps it, so two at once
   * can't both add rooms from the same look at what the team had.
   */
  mark: (t: string) => `discordImports/${t}`,
};

const ownerOnly = () => new ApiError("permission_denied", "Only the owner can import from Discord.");
const noTeam = () => new ApiError("not_found", "That team doesn't exist.");
const unreachable = () => new ApiError("unavailable", "Couldn't reach Discord. Try again in a moment.");

/** The response body as text, refusing more than [max] bytes. */
async function readCapped(res: Response, max: number): Promise<string> {
  const declared = Number(res.headers.get("content-length") ?? "");
  if (Number.isFinite(declared) && declared > max) throw new ApiError("failed_precondition", "That template is too big to import.");
  if (!res.body) return "";
  const reader = res.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > max) {
      await reader.cancel().catch(() => undefined);
      throw new ApiError("failed_precondition", "That template is too big to import.");
    }
    chunks.push(value);
  }
  return Buffer.concat(chunks).toString("utf8");
}

/** A team's folders and rooms, as an import compares them. */
function existing(docs: Array<{ id: string; data: Data }>): Array<ExistingFolder & ExistingRoom> {
  return docs.map((d) => ({
    id: d.id,
    name: typeof d.data.name === "string" ? d.data.name : "",
    position: typeof d.data.position === "number" ? d.data.position : 0,
    folderId: typeof d.data.folderId === "string" ? d.data.folderId : null,
  }));
}

/** The member→roles map as stored, lists of strings only. */
function memberRolesOf(team: Data): Record<string, string[]> {
  return Object.fromEntries(Object.entries(mapOf(team.memberRoles)).map(([uid, ids]) => [uid, strings(ids)]));
}

interface Chats {
  folders: ExistingFolder[];
  rooms: ExistingRoom[];
  /** discordImports/{teamId}'s count when they were read. */
  seq: number;
}

const seqOf = (mark: Data | null) => (typeof mark?.seq === "number" ? mark.seq : 0);

interface Applied {
  teamId: string;
  roles: number;
  folders: number;
  rooms: number;
}

export class DiscordService {
  constructor(
    private readonly store: DocStore,
    private readonly chats: Pick<ChatAdmin, "deleteRoom" | "deleteFolder">,
    private readonly fetchImpl: Fetch = (url, init) => fetch(url, init),
    private readonly newId: () => string = () => newRoleId(randomInt),
  ) {}

  /**
   * `POST /v1/teams/:teamId/discord/preview`: reads the template behind the
   * link and returns what importing it would create. The owner asks; this
   * writes nothing. No token or user data goes to Discord.
   */
  async preview(caller: Caller, rawTeam: unknown, body: unknown): Promise<ImportPlan> {
    const teamId = docIdParam(rawTeam);
    const { link } = parseBody(discordPreviewRequestSchema, body);
    const code = templateCode(link);
    if (code === null) throw new ApiError("invalid_argument", "Paste a server template link, like https://discord.new/abc123.");
    const team = await this.store.get(p.team(teamId));
    if (!team) throw noTeam();
    // The callable checks members[uid] == 'owner'.
    if (mapOf(team.members)[caller.uid] !== "owner") throw ownerOnly();

    let res: Response;
    try {
      res = await this.fetchImpl(discordTemplateUrl(code), {
        method: "GET",
        headers: { "User-Agent": "stall10-api (server template import)", Accept: "application/json" },
        redirect: "error",
        signal: AbortSignal.timeout(discordFetchTimeoutMs),
      });
    } catch {
      throw unreachable();
    }
    if (res.status === 404) throw new ApiError("not_found", "Discord doesn't know that template. Check the link, or make a new one.");
    if (res.status === 429) throw new ApiError("resource_exhausted", "Discord is busy. Try again in a minute.");
    if (!res.ok) throw new ApiError("unavailable", "Discord couldn't load that template. Try again in a moment.");
    let text: string;
    try {
      text = await readCapped(res, discordTemplateBytesMax);
    } catch (e) {
      if (e instanceof ApiError) throw e;
      throw unreachable();
    }
    let template: unknown;
    try {
      template = JSON.parse(text);
    } catch {
      throw new ApiError("internal", "Discord's answer made no sense.");
    }
    if (!template || typeof template !== "object") throw new ApiError("internal", "Discord's answer made no sense.");
    return mapTemplate(template as GuildTemplate);
  }

  /** The team's folders and rooms, with the import count read first (write() checks it). */
  private async chatsOf(teamId: string): Promise<Chats> {
    const mark = await this.store.get(p.mark(teamId));
    const [folders, rooms] = await Promise.all([
      this.store.list(p.folders(teamId), chatRoomLimits.folders * 4),
      this.store.list(p.rooms(teamId), chatRoomLimits.rooms * 2),
    ]);
    return { folders: existing(folders), rooms: existing(rooms), seq: seqOf(mark) };
  }

  /**
   * `POST /v1/teams/:teamId/discord/import`: applies a previewed plan, in
   * the app's order (DiscordImportViewModel._apply): each linked team's
   * share first (in a community with teams, for teams the caller also
   * owns), then the team's own, then rooms an earlier import put in the
   * community that now belong to a team, and folders that leaves empty.
   * The mapping (planImport and friends) runs here on the stored team, so
   * ids, positions and reuse never come from the client.
   */
  async apply(caller: Caller, rawTeam: unknown, body: unknown): Promise<DiscordImportResult> {
    const teamId = docIdParam(rawTeam);
    const req = parseBody(discordImportRequestSchema, body);
    const plan = req.plan as ImportPlan;
    const org = await this.store.get(p.team(teamId));
    if (!org) throw noTeam();
    if (!isOwner(org, caller.uid)) throw ownerOnly();
    const own = await this.chatsOf(teamId);
    const whole = planImport(plan, org as ImportTeam, own.folders, own.rooms, this.newId);

    // A community with teams: rooms only one team reads go to it.
    let split: ReturnType<typeof splitPlan> | null = null;
    const owned: Array<{ id: string; name: string }> = [];
    const linked = Object.keys(mapOf(org.linkedTeams));
    if (isOrg(org) && linked.length > 0) {
      const docs = await Promise.all(linked.map(async (id) => [id, await this.store.get(p.team(docIdParam(id)))] as const));
      for (const [id, t] of docs) if (t && isOwner(t, caller.uid)) owned.push({ id, name: String(t.name ?? "") });
      owned.sort((a, b) => a.name.toLowerCase().localeCompare(b.name.toLowerCase()));
      const overrides = new Map<number, string | null>();
      for (const d of req.destinations) if (d.room < plan.rooms.length) overrides.set(d.room, d.teamId);
      const first = splitPlan(plan, org as ImportTeam, whole.roleIdsByKey, overrides);
      // Rooms for teams the caller can't write to stay in the community.
      const mine = new Set(owned.map((t) => t.id));
      first.destinations.forEach((d, i) => {
        if (d !== null && !mine.has(d)) overrides.set(i, null);
      });
      split = splitPlan(plan, org as ImportTeam, whole.roleIdsByKey, overrides);
    }

    const applied: Applied[] = [];
    if (split) {
      const going = splitTeams(split);
      for (const t of owned) {
        if (!going.has(t.id)) continue;
        const chats = await this.chatsOf(t.id);
        const share = planFor(plan, split, t.id);
        const done = await this.write(caller, t.id, chats, (team) => {
          const x = teamChatImport(share, org as ImportTeam, t.id, team as ImportTeam, whole.roleIdsByKey, chats.folders, chats.rooms, this.newId);
          return teamChatImportIsEmpty(x, team as ImportTeam) ? null : { import: x.import, orgRoles: x.orgRoles };
        });
        if (done) applied.push(done);
      }
    }
    const mainPlan = split ? planFor(plan, split, null) : plan;
    const done = await this.write(caller, teamId, own, (team) => {
      const x = planImport(mainPlan, team as ImportTeam, own.folders, own.rooms, this.newId);
      return importIsEmpty(x) ? null : { import: x };
    });
    if (done) applied.push(done);

    const moving = split ? movingRooms(plan, split, own.folders, own.rooms) : [];
    const emptied = emptiedFolders(moving, own.folders, own.rooms);
    for (const r of moving) await this.chats.deleteRoom(caller, teamId, r.id);
    for (const f of emptied) await this.chats.deleteFolder(caller, teamId, f.id);
    return { teams: applied, movedRooms: moving.length, removedFolders: emptied.length };
  }

  /**
   * One team's import in one transaction (the app's one batch): the team
   * doc's roles (and orgRoles for a linked team), then the new folders and
   * rooms. [compute] maps the plan onto the team as read in the
   * transaction; null when there's nothing to add.
   */
  private async write(
    caller: Caller,
    teamId: string,
    chats: Chats,
    compute: (team: Data) => { import: DiscordImport; orgRoles?: Record<string, string> } | null,
  ): Promise<Applied | null> {
    return this.store.transact(async (tx) => {
      const [team, mark] = await Promise.all([tx.get(p.team(teamId)), tx.get(p.mark(teamId))]);
      if (!team) throw noTeam();
      // Another import wrote since [chats] were read: its rooms aren't in them.
      if (seqOf(mark) !== chats.seq) throw new ApiError("failed_precondition", "This team's rooms were just imported. Preview the template again.");
      // setRoles(): the owner. chats/chatFolders create: manageChats (the owner has it).
      if (!isOwner(team, caller.uid) || !can(team, caller.uid, "manageChats")) throw ownerOnly();
      const planned = compute(team);
      if (!planned) return null;
      const { import: i, orgRoles } = planned;
      if (Object.keys(i.roles).length > roleLimits.roles) throw new ApiError("failed_precondition", `A team can have up to ${roleLimits.roles} roles.`);
      if (orgRoles && Object.keys(orgRoles).length > roleLimits.roles) throw new ApiError("failed_precondition", `A team can copy up to ${roleLimits.roles} community roles.`);
      if (chats.rooms.length + i.rooms.length > chatRoomLimits.rooms) throw new ApiError("failed_precondition", `A team can have ${chatRoomLimits.rooms} rooms.`);
      if (chats.folders.length + i.folders.length > chatRoomLimits.folders) throw new ApiError("failed_precondition", `A team can have ${chatRoomLimits.folders} folders.`);
      const ids = new Set(strings(team.memberIds));
      const members = Object.keys(mapOf(team.members)).filter((u) => ids.has(u));
      const roles = rolesData(i.roles, cleanMemberRoles(memberRolesOf(team), i.roles, members));
      tx.update(p.team(teamId), { ...roles, ...(orgRoles && { orgRoles }) });
      tx.set(p.mark(teamId), { seq: chats.seq + 1, updatedAt: serverTime });
      for (const f of i.folders) {
        tx.create(p.folder(teamId, docIdParam(f.id)), {
          name: f.name.trim(),
          position: f.position,
          ...accessFields(team, storedAccess(f)),
          createdBy: caller.uid,
          createdAt: serverTime,
        });
      }
      for (const r of i.rooms) {
        tx.create(p.room(teamId, this.store.newId(p.rooms(teamId))), {
          name: r.name.trim(),
          kind: "text",
          ...accessFields(team, storedAccess(r)),
          folderId: r.folderId,
          position: r.position,
          createdBy: caller.uid,
          createdAt: serverTime,
        });
      }
      return { teamId, roles: i.newRoles.length, folders: i.folders.length, rooms: i.rooms.length };
    });
  }
}

/** The import routes, each on its own bucket. */
export function discordRoutes(app: FastifyInstance, discord: DiscordService, limiter: MemoryRateLimiter) {
  const caller = (req: FastifyRequest, bucket: keyof typeof discordRouteLimits): Caller => {
    const c = requireCaller(req);
    if (!limiter.admit(`discord-${bucket}:${c.uid}`, discordRouteLimits[bucket])) {
      throw new ApiError("resource_exhausted", "You're doing that too fast. Wait a minute and try again.");
    }
    return c;
  };
  type T = { Params: { teamId: string } };
  app.post<T>("/v1/teams/:teamId/discord/preview", async (req) => discord.preview(caller(req, "preview"), req.params.teamId, req.body));
  app.post<T>("/v1/teams/:teamId/discord/import", { bodyLimit: 512 * 1024 }, async (req) => discord.apply(caller(req, "import"), req.params.teamId, req.body));
}
