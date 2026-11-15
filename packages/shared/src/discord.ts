// Importing a Discord server template into a team's roles, chat folders and
// rooms (the app's DiscordImportViewModel and lib/domain/models/
// discord_import.dart). The API reads the template from Discord
// (apps/api/src/discord, a port of the discord-previewTemplate callable)
// and returns an ImportPlan; the plan is mapped onto a team here, as pure
// functions both the website's preview and the API's apply run, so the
// two always agree. Keep in step with discord_import.dart.
import { z } from "zod";
import { roleLimits, teamPermissions, type TeamPermission } from "./membership.js";

/** A role from the template (PlannedRole). */
export interface PlannedRole {
  /** The template's role id; rooms' access lists refer to it. */
  key: string;
  name: string;
  /** ARGB, 0 for none, as CustomRole stores it. */
  color: number;
  position: number;
  perms: TeamPermission[];
}

/** "everyone" or plan role keys. */
export interface PlannedAccess {
  readRoles: string[];
  writeRoles: string[];
}

export interface PlannedFolder extends PlannedAccess {
  key: string;
  name: string;
  position: number;
}

export interface PlannedRoom extends PlannedAccess {
  name: string;
  /** Key of the folder it goes in, or null. */
  folderKey: string | null;
  position: number;
}

export interface SkippedChannel {
  name: string;
  reason: string;
}

/** What a server template holds, ready to import (ImportPlan in template.ts). */
export interface ImportPlan {
  serverName: string;
  /** Highest role first. */
  roles: PlannedRole[];
  folders: PlannedFolder[];
  rooms: PlannedRoom[];
  skipped: SkippedChannel[];
  /** Roles left out because a team holds at most [discordLimits.roles]. */
  skippedRoles: string[];
}

/** Limits from template.ts, the app and firestore.rules. */
export const discordLimits = {
  roles: roleLimits.roles,
  roleName: roleLimits.roleName,
  chatName: 60,
  rooms: 200,
  /** Categories a plan may carry (Discord allows 500 channels in all). */
  folders: 200,
  serverName: 100,
  /** Longest link pasted into the preview. */
  link: 500,
} as const;

/** The audience id every member is in (ChatAudience.everyone). */
export const everyoneAudience = "everyone";

// Requests ----------------------------------------------------------------

/** `POST /v1/teams/:teamId/discord/preview`: a template link (https://discord.new/…) or code. */
export const discordPreviewRequestSchema = z.strictObject({
  link: z.string().trim().min(1, "Paste a server template link.").max(discordLimits.link),
});
export type DiscordPreviewRequest = z.input<typeof discordPreviewRequestSchema>;

const planKey = z.string().min(1).max(64).regex(/^[^/]+$/);
const accessKeys = z.array(planKey).max(discordLimits.roles + 1);
const planAccess = { readRoles: accessKeys, writeRoles: accessKeys };

/** An ImportPlan sent back to apply, checked whole (names at the rules' lengths). */
export const importPlanSchema = z.strictObject({
  serverName: z.string().max(discordLimits.serverName),
  roles: z
    .array(
      z.strictObject({
        key: planKey,
        name: z.string().trim().min(1).max(discordLimits.roleName),
        color: z.number().int().min(0).max(0xffffffff),
        position: z.number().int().min(0).max(10_000),
        perms: z.array(z.enum(teamPermissions)).max(teamPermissions.length),
      }),
    )
    .max(discordLimits.roles),
  folders: z
    .array(
      z.strictObject({
        key: planKey,
        name: z.string().trim().min(1).max(discordLimits.chatName),
        position: z.number().int().min(0).max(10_000),
        ...planAccess,
      }),
    )
    .max(discordLimits.folders),
  rooms: z
    .array(
      z.strictObject({
        name: z.string().trim().min(1).max(discordLimits.chatName),
        folderKey: planKey.nullable(),
        position: z.number().int().min(0).max(10_000),
        ...planAccess,
      }),
    )
    .max(discordLimits.rooms),
  skipped: z.array(z.strictObject({ name: z.string().max(discordLimits.chatName), reason: z.string().max(100) })).max(500),
  skippedRoles: z.array(z.string().max(discordLimits.roleName)).max(500),
});

/**
 * `POST /v1/teams/:teamId/discord/import`: the previewed plan, and in a
 * community with teams, the rooms the owner sent somewhere other than
 * where the plan suggests (room index → a linked team id, or null for the
 * community's own chat).
 */
export const discordImportRequestSchema = z.strictObject({
  plan: importPlanSchema,
  destinations: z
    .array(z.strictObject({ room: z.number().int().min(0).max(discordLimits.rooms), teamId: planKey.nullable() }))
    .max(discordLimits.rooms)
    .default([]),
});
export type DiscordImportRequest = z.input<typeof discordImportRequestSchema>;

/** After an import: what was added, by team. */
export interface DiscordImportResult {
  teams: Array<{ teamId: string; roles: number; folders: number; rooms: number }>;
  /** Rooms moved out of the community's chat to a team's, and folders that left empty. */
  movedRooms: number;
  removedFolders: number;
}

// Mapping a plan onto a team (DiscordImport.of) -----------------------------

/** A custom role as the team doc stores it (CustomRole.toMap). */
export interface StoredRole {
  name: string;
  color: number;
  position: number;
  perms: TeamPermission[];
}

/** The team doc fields an import reads. */
export interface ImportTeam {
  roles?: Record<string, Partial<StoredRole> | undefined>;
  /** Team role id → the community role it copies (Team.orgRoles). */
  orgRoles?: Record<string, string>;
  /** A community's teams and the roles that get on them (LinkedTeam). */
  linkedTeams?: Record<string, { name?: string; roles?: string[] } | undefined>;
}

/** Existing folders and rooms, as far as an import cares. */
export interface ExistingFolder {
  id: string;
  name: string;
  position?: number;
}
export interface ExistingRoom {
  id: string;
  name: string;
  folderId?: string | null;
  position?: number;
}

export interface NewFolder extends PlannedAccess {
  id: string;
  name: string;
  position: number;
}
export interface NewRoom extends PlannedAccess {
  name: string;
  folderId: string | null;
  position: number;
}

/** The plan turned into this team's roles, folders and rooms (DiscordImport). */
export interface DiscordImport {
  /** Plan role keys → this team's role ids (new or reused). */
  roleIdsByKey: Record<string, string>;
  /** Every custom role the team will have: its own plus the new ones. */
  roles: Record<string, StoredRole>;
  /** Names of the roles being added. */
  newRoles: string[];
  folders: NewFolder[];
  rooms: NewRoom[];
  /** Rooms skipped because the team already has one by that name there. */
  alreadyHere: string[];
  /** Roles left out to stay within the role limit. */
  tooManyRoles: string[];
}

/** A 16-character id like the app's newRoleId(), for roles and folders. */
export function newRoleId(random: (n: number) => number = (n) => Math.floor(Math.random() * n)): string {
  const chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
  let id = "";
  for (let i = 0; i < 16; i++) id += chars[random(chars.length)];
  return id;
}

const norm = (s: string) => s.trim().toLowerCase();

function storedRole(r: Partial<StoredRole> | undefined): StoredRole | null {
  if (!r || typeof r.name !== "string") return null;
  return {
    name: r.name,
    color: typeof r.color === "number" ? r.color : 0,
    position: typeof r.position === "number" ? r.position : 0,
    perms: Array.isArray(r.perms) ? teamPermissions.filter((p) => r.perms!.includes(p)) : [],
  };
}

/** The team's custom roles as stored, skipping malformed ones. */
export function rolesOf(team: ImportTeam): Record<string, StoredRole> {
  const out: Record<string, StoredRole> = {};
  for (const [id, r] of Object.entries(team.roles ?? {})) {
    const role = storedRole(r);
    if (role) out[id] = role;
  }
  return out;
}

/** Whether an import adds nothing. */
export const importIsEmpty = (i: DiscordImport) => i.newRoles.length === 0 && i.folders.length === 0 && i.rooms.length === 0;

/**
 * Maps [plan] onto [team], which has [folders] and [rooms] already.
 * Roles and folders whose names the team already has are reused, and
 * rooms already in their folder by name are left alone, so importing the
 * same template twice adds nothing. [newId] makes ids for new roles and
 * folders.
 */
export function planImport(
  plan: ImportPlan,
  team: ImportTeam,
  folders: readonly ExistingFolder[],
  rooms: readonly ExistingRoom[],
  newId: () => string = () => newRoleId(),
): DiscordImport {
  // Roles: reuse by name, else add while there's room.
  const roles = rolesOf(team);
  const roleIds: Record<string, string> = {};
  const newRoles: string[] = [];
  const tooMany = [...plan.skippedRoles];
  const existing = Object.values(roles);
  let position = existing.length === 0 ? 0 : Math.max(...existing.map((r) => r.position)) + 1;
  for (const r of plan.roles) {
    const same = Object.entries(roles).find(([, e]) => norm(e.name) === norm(r.name));
    if (same) {
      roleIds[r.key] = same[0];
      continue;
    }
    if (Object.keys(roles).length >= discordLimits.roles) {
      tooMany.push(r.name);
      continue;
    }
    const id = newId();
    roles[id] = { name: r.name, color: r.color, position: position++, perms: teamPermissions.filter((p) => r.perms.includes(p)) };
    roleIds[r.key] = id;
    newRoles.push(r.name);
  }

  // Access lists in this team's ids. Roles that didn't make it are dropped,
  // which only ever narrows access.
  const ids = (keys: readonly string[]) => [...new Set(keys.flatMap((k) => (k === everyoneAudience ? [k] : roleIds[k] ? [roleIds[k]!] : [])))];

  // Folders: reuse by name, else add after the team's own.
  const folderIds: Record<string, string> = {};
  const newFolders: NewFolder[] = [];
  let folderPosition = folders.length === 0 ? 0 : Math.max(...folders.map((f) => f.position ?? 0)) + 1;
  for (const f of plan.folders) {
    const same = folders.find((e) => norm(e.name) === norm(f.name));
    if (same) {
      folderIds[f.key] = same.id;
      continue;
    }
    const folder: NewFolder = { id: newId(), name: f.name, position: folderPosition++, readRoles: ids(f.readRoles), writeRoles: ids(f.writeRoles) };
    newFolders.push(folder);
    folderIds[f.key] = folder.id;
  }

  // Rooms: skip ones already in their folder by name; add the rest after
  // the rooms already there. (The app's keys say "null" for no folder.)
  const slot = (folderId: string | null | undefined, name: string) => `${folderId ?? "null"}/${norm(name)}`;
  const taken = new Set(rooms.map((r) => slot(r.folderId, r.name)));
  const next = new Map<string | null, number>();
  const nextPosition = (folderId: string | null) => {
    if (!next.has(folderId)) {
      next.set(
        folderId,
        rooms.filter((r) => (r.folderId ?? null) === folderId).reduce((n, r) => ((r.position ?? 0) >= n ? (r.position ?? 0) + 1 : n), 0),
      );
    }
    return next.get(folderId)!;
  };
  const newRooms: NewRoom[] = [];
  const alreadyHere: string[] = [];
  for (const r of plan.rooms) {
    const folderId = r.folderKey === null ? null : (folderIds[r.folderKey] ?? null);
    const key = slot(folderId, r.name);
    if (taken.has(key)) {
      alreadyHere.push(r.name);
      continue;
    }
    taken.add(key);
    const at = nextPosition(folderId);
    next.set(folderId, at + 1);
    newRooms.push({ name: r.name, folderId, position: at, readRoles: ids(r.readRoles), writeRoles: ids(r.writeRoles) });
  }

  return { roleIdsByKey: roleIds, roles, newRoles, folders: newFolders, rooms: newRooms, alreadyHere, tooManyRoles: tooMany };
}

/**
 * Access lists as stored (ChatAccessLists.accessMap): write access folded
 * into read, both sorted, no single members.
 */
export function storedAccess(a: PlannedAccess) {
  return {
    readRoles: [...new Set([...a.readRoles, ...a.writeRoles])].sort(),
    writeRoles: [...new Set(a.writeRoles)].sort(),
    readUsers: [] as string[],
    writeUsers: [] as string[],
  };
}

// Communities with teams (DiscordTeamSplit, TeamChatImport) ------------------

/** Where each room goes in a community with teams: its own chat (null) or a linked team's (an id). */
export interface DiscordTeamSplit {
  /** Room index → where the rule sends it. */
  suggested: Array<string | null>;
  /** Room index → where it goes, overrides applied. */
  destinations: Array<string | null>;
}

/**
 * Rooms only a single team's roles can read go to that team; roles that get
 * on no team (like Admin) don't count, and rooms anyone can read, or that
 * two teams' roles read, stay in the community. [overrides] (room index →
 * destination) win when they name the community or one of its teams.
 * [roleIds]: plan role keys → [org]'s role ids (DiscordImport.roleIdsByKey).
 */
export function splitPlan(
  plan: ImportPlan,
  org: ImportTeam,
  roleIds: Record<string, string>,
  overrides: ReadonlyMap<number, string | null> = new Map(),
): DiscordTeamSplit {
  const linked = Object.entries(org.linkedTeams ?? {});
  const teamsOf = (key: string) => {
    const id = roleIds[key];
    return new Set(id ? linked.filter(([, t]) => (t?.roles ?? []).includes(id)).map(([tid]) => tid) : []);
  };
  const suggest = (r: PlannedRoom): string | null => {
    if (r.readRoles.includes(everyoneAudience)) return null;
    const teams = new Set<string>();
    for (const key of r.readRoles) {
      const of = teamsOf(key);
      if (of.size > 1) return null;
      of.forEach((t) => teams.add(t));
    }
    return teams.size === 1 ? [...teams][0]! : null;
  };
  const suggested = plan.rooms.map(suggest);
  const destinations = plan.rooms.map((_, i) => {
    if (overrides.has(i)) {
      const o = overrides.get(i)!;
      if (o === null || Object.hasOwn(org.linkedTeams ?? {}, o)) return o;
    }
    return suggested[i]!;
  });
  return { suggested, destinations };
}

/** Teams at least one room goes to. */
export const splitTeams = (split: DiscordTeamSplit) => new Set(split.destinations.filter((d): d is string => d !== null));

/** The part of [plan] going to [teamId] (null: the community), with the folders its rooms are in. */
export function planFor(plan: ImportPlan, split: DiscordTeamSplit, teamId: string | null): ImportPlan {
  const rooms = plan.rooms.filter((_, i) => split.destinations[i] === teamId);
  const used = new Set(rooms.flatMap((r) => (r.folderKey === null ? [] : [r.folderKey])));
  // Folders with no rooms at all stay with the community.
  const roomless = new Set(plan.folders.filter((f) => !plan.rooms.some((r) => r.folderKey === f.key)).map((f) => f.key));
  return {
    serverName: plan.serverName,
    roles: plan.roles,
    folders: plan.folders.filter((f) => used.has(f.key) || (teamId === null && roomless.has(f.key))),
    rooms,
    skipped: teamId === null ? plan.skipped : [],
    skippedRoles: teamId === null ? plan.skippedRoles : [],
  };
}

/** A linked team's share of an import (TeamChatImport). */
export interface TeamChatImport {
  teamId: string;
  import: DiscordImport;
  /** Team role id → the community role it copies. */
  orgRoles: Record<string, string>;
}

export function teamChatImportIsEmpty(t: TeamChatImport, team: ImportTeam): boolean {
  const before = team.orgRoles ?? {};
  return importIsEmpty(t.import) && Object.entries(t.orgRoles).every(([k, v]) => before[k] === v);
}

/** Compares by UTF-16 code units, as Dart's String.compareTo does. */
const byCodeUnits = (a: string, b: string) => (a < b ? -1 : a > b ? 1 : 0);

/**
 * [org]'s roles by position, then lowercased name (Team.sortedRoles). Names
 * compare by code units like the app, not localeCompare, so roles tied on
 * position come in the same order (and get the same new ids) on both.
 */
function sortedRoles(org: ImportTeam) {
  return Object.entries(rolesOf(org))
    .map(([id, r]) => ({ id, ...r }))
    .sort((a, b) => (a.position !== b.position ? a.position - b.position : byCodeUnits(a.name.toLowerCase(), b.name.toLowerCase())));
}

/**
 * A linked team's rooms and folders, and copies of the community roles that
 * get on it, which the communities Cloud Functions keep in step with the
 * community (orgRoles). A room every one of those roles reads is open to
 * the whole team. [teamPlan]: planFor(plan, split, teamId).
 */
export function teamChatImport(
  teamPlan: ImportPlan,
  org: ImportTeam,
  teamId: string,
  team: ImportTeam,
  roleIds: Record<string, string>,
  folders: readonly ExistingFolder[],
  rooms: readonly ExistingRoom[],
  newId: () => string = () => newRoleId(),
): TeamChatImport {
  const link = org.linkedTeams?.[teamId];
  const granting = sortedRoles(org).filter((r) => (link?.roles ?? []).includes(r.id));
  const grantingIds = new Set(granting.map((r) => r.id));

  // Access in community role ids, narrowed to this team's roles; all of
  // them means the whole team.
  const access = (keys: readonly string[]): string[] => {
    if (keys.includes(everyoneAudience)) return [everyoneAudience];
    const ids = new Set(keys.flatMap((k) => (roleIds[k] && grantingIds.has(roleIds[k]!) ? [roleIds[k]!] : [])));
    if (grantingIds.size > 0 && [...grantingIds].every((g) => ids.has(g))) return [everyoneAudience];
    return [...ids];
  };

  // A role already copying a community role keeps its id, whatever it's called now.
  const own = rolesOf(team);
  const copies = new Map(Object.entries(team.orgRoles ?? {}).map(([k, v]) => [v, k]));
  const named: ImportPlan = {
    serverName: teamPlan.serverName,
    roles: granting.map((r, i) => ({
      key: r.id,
      name: own[copies.get(r.id) ?? ""]?.name ?? r.name,
      color: r.color,
      position: i,
      perms: r.perms,
    })),
    folders: teamPlan.folders.map((f) => ({ ...f, readRoles: access(f.readRoles), writeRoles: access(f.writeRoles) })),
    rooms: teamPlan.rooms.map((r) => ({ ...r, readRoles: access(r.readRoles), writeRoles: access(r.writeRoles) })),
    skipped: [],
    skippedRoles: [],
  };
  const imported = planImport(named, team, folders, rooms, newId);
  const orgRoles = { ...(team.orgRoles ?? {}) };
  for (const [key, id] of Object.entries(imported.roleIdsByKey)) orgRoles[id] = key;
  return { teamId, import: imported, orgRoles };
}

/**
 * Rooms already in the community's chat (from an earlier import) that now
 * go to a team, so they're deleted there once the team has them.
 */
export function movingRooms(
  plan: ImportPlan,
  split: DiscordTeamSplit,
  folders: readonly ExistingFolder[],
  rooms: readonly ExistingRoom[],
): ExistingRoom[] {
  const folderNames = new Map(folders.map((f) => [f.id, norm(f.name)]));
  const planFolders = new Map(plan.folders.map((f) => [f.key, norm(f.name)]));
  const going = new Set(
    plan.rooms.flatMap((r, i) => (split.destinations[i] !== null ? [`${(r.folderKey !== null && planFolders.get(r.folderKey)) || ""}/${norm(r.name)}`] : [])),
  );
  return rooms.filter((r) => going.has(`${(r.folderId && folderNames.get(r.folderId)) || ""}/${norm(r.name)}`));
}

/** Folders that [moving] leaves empty. */
export function emptiedFolders(moving: readonly ExistingRoom[], folders: readonly ExistingFolder[], rooms: readonly ExistingRoom[]): ExistingFolder[] {
  const gone = new Set(moving.map((r) => r.id));
  return folders.filter((f) => {
    const inside = rooms.filter((r) => r.folderId === f.id);
    return inside.some((r) => gone.has(r.id)) && inside.every((r) => gone.has(r.id));
  });
}

/** An audience id's name in a preview: Everyone, or the role's. */
export function audienceLabel(id: string, roles: Record<string, StoredRole>): string {
  return id === everyoneAudience ? "Everyone" : (roles[id]?.name ?? "Deleted role");
}
