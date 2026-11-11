// Pure Discord server template logic: turning a template's roles and
// channels into the app's custom roles, chat folders and rooms. No Firebase
// or network calls here, so it's unit-tested in test/discord. The app's
// side is CustomRole (lib/domain/models/team_role.dart) and ChatRoom /
// ChatFolder (lib/domain/models/chat.dart); keep them in step.
//
// A server template (https://discord.com/developers/docs/resources/guild-template)
// is a snapshot of a server's roles, channels and permission overwrites,
// with no members or messages. Its role and channel ids are small numbers
// local to the template; role 0 is @everyone.

/** Discord permission bits the import looks at. */
export const Perm = {
  kickMembers: 1n << 1n,
  banMembers: 1n << 2n,
  administrator: 1n << 3n,
  manageChannels: 1n << 4n,
  manageGuild: 1n << 5n,
  viewChannel: 1n << 10n,
  sendMessages: 1n << 11n,
  manageMessages: 1n << 13n,
  manageEvents: 1n << 33n,
} as const;

export const ChannelType = {
  text: 0,
  voice: 2,
  category: 4,
  announcement: 5,
  stage: 13,
  forum: 15,
} as const;

/** Channels that become chat rooms; the rest are skipped. */
const roomTypes = new Set<number>([ChannelType.text, ChannelType.announcement, ChannelType.forum]);

export interface TemplateRole {
  id: number | string;
  name?: string;
  color?: number;
  permissions?: string;
  position?: number;
}

export interface TemplateOverwrite {
  id: number | string;
  /** 0 for a role, 1 for a member. */
  type?: number;
  allow?: string;
  deny?: string;
}

export interface TemplateChannel {
  id: number | string;
  type?: number;
  name?: string;
  position?: number;
  parent_id?: number | string | null;
  permission_overwrites?: TemplateOverwrite[];
}

export interface GuildTemplate {
  code?: string;
  name?: string;
  serialized_source_guild?: {
    name?: string;
    roles?: TemplateRole[];
    channels?: TemplateChannel[];
  };
}

/** The app's permission names (TeamPermission in Dart). */
export type AppPermission = "manageTeam" | "manageMembers" | "manageChats" | "manageEvents" | "moderate" | "keepStats";

export interface PlannedRole {
  /** The template's role id, which rooms' access lists refer to. */
  key: string;
  name: string;
  /** ARGB, 0 for none, as CustomRole stores it. */
  color: number;
  position: number;
  perms: AppPermission[];
}

export interface PlannedAccess {
  /** "everyone" or role keys. */
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

/** What importing a template would create, for the app to preview and write. */
export interface ImportPlan {
  serverName: string;
  roles: PlannedRole[];
  folders: PlannedFolder[];
  rooms: PlannedRoom[];
  skipped: SkippedChannel[];
  /** Roles left out because a team holds at most [maxRoles]. */
  skippedRoles: string[];
}

/** Limits from the app and firestore.rules. */
export const maxRoles = 50;
export const maxRoleName = 40;
export const maxChatName = 60;
export const maxRooms = 200;

const codePattern = /^[A-Za-z0-9-]{2,64}$/;

/**
 * The template code in a link like https://discord.new/abc123 or
 * https://discord.com/template/abc123, or a bare code. Null if there's none.
 */
export function templateCode(input: unknown): string | null {
  if (typeof input !== "string") return null;
  const text = input.trim();
  if (codePattern.test(text)) return text;
  let url: URL;
  try {
    url = new URL(/^[a-z]+:\/\//i.test(text) ? text : `https://${text}`);
  } catch {
    return null;
  }
  const host = url.hostname.toLowerCase().replace(/^www\./, "");
  const parts = url.pathname.split("/").filter((p) => p.length > 0);
  let code: string | undefined;
  if (host === "discord.new") {
    code = parts[0];
  } else if (["discord.com", "discordapp.com", "ptb.discord.com", "canary.discord.com"].includes(host)) {
    if (parts[0] === "template") code = parts[1];
  }
  return code !== undefined && codePattern.test(code) ? code : null;
}

function bits(value: unknown): bigint {
  if (typeof value === "string" && /^\d+$/.test(value)) return BigInt(value);
  if (typeof value === "number" && Number.isInteger(value) && value >= 0) return BigInt(value);
  return 0n;
}

const has = (perms: bigint, bit: bigint) => (perms & bit) === bit;

/** The app permissions a Discord role's permission bits map to. */
export function appPermissions(perms: bigint): AppPermission[] {
  if (has(perms, Perm.administrator)) {
    return ["manageTeam", "manageMembers", "manageChats", "manageEvents", "moderate"];
  }
  const out: AppPermission[] = [];
  if (has(perms, Perm.manageGuild)) out.push("manageTeam");
  if (has(perms, Perm.kickMembers) || has(perms, Perm.banMembers)) out.push("manageMembers");
  if (has(perms, Perm.manageChannels)) out.push("manageChats");
  if (has(perms, Perm.manageEvents)) out.push("manageEvents");
  if (has(perms, Perm.manageMessages)) out.push("moderate");
  return out;
}

function clip(text: unknown, max: number, fallback: string): string {
  const t = typeof text === "string" ? text.trim() : "";
  return (t.length > 0 ? t : fallback).slice(0, max);
}

/**
 * Discord's channel permissions for one role, ignoring member overwrites:
 * the role's server permissions plus @everyone's, then @everyone's channel
 * overwrite, then the role's. Administrators can do everything.
 */
export function channelPermissions(
  everyone: bigint,
  role: { key: string; perms: bigint } | null,
  overwrites: TemplateOverwrite[],
  everyoneKey: string,
): bigint {
  let perms = everyone | (role?.perms ?? 0n);
  if (has(perms, Perm.administrator)) return ~0n;
  const apply = (key: string) => {
    for (const o of overwrites) {
      if ((o.type ?? 0) === 0 && String(o.id) === key) {
        perms &= ~bits(o.deny);
        perms |= bits(o.allow);
      }
    }
  };
  apply(everyoneKey);
  if (role) apply(role.key);
  return perms;
}

/** Who can read and write a channel, as audience ids. */
function accessOf(
  channel: TemplateChannel,
  everyone: bigint,
  everyoneKey: string,
  roles: { key: string; perms: bigint }[],
): PlannedAccess {
  const overwrites = channel.permission_overwrites ?? [];
  const canRead = (p: bigint) => has(p, Perm.viewChannel);
  const canWrite = (p: bigint) => canRead(p) && has(p, Perm.sendMessages);
  const base = channelPermissions(everyone, null, overwrites, everyoneKey);
  const readRoles: string[] = [];
  const writeRoles: string[] = [];
  if (canRead(base)) readRoles.push("everyone");
  if (canWrite(base)) writeRoles.push("everyone");
  for (const role of roles) {
    const p = channelPermissions(everyone, role, overwrites, everyoneKey);
    // A role adds nothing where everyone already has the same access.
    // Writing needs reading, so writers are always readers too.
    if (canRead(p) && !canRead(base)) readRoles.push(role.key);
    if (canWrite(p) && !canWrite(base)) writeRoles.push(role.key);
  }
  return { readRoles, writeRoles };
}

const byPosition = (a: { position?: number; id: number | string }, b: { position?: number; id: number | string }) =>
  (a.position ?? 0) - (b.position ?? 0) || String(a.id).localeCompare(String(b.id), undefined, { numeric: true });

/** Turns a server template into what the app would create. */
export function mapTemplate(template: GuildTemplate): ImportPlan {
  const guild = template.serialized_source_guild ?? {};
  const allRoles = guild.roles ?? [];
  // @everyone is role 0 in templates; fall back to a role named @everyone.
  const everyoneRole = allRoles.find((r) => String(r.id) === "0") ?? allRoles.find((r) => r.name === "@everyone");
  const everyoneKey = everyoneRole ? String(everyoneRole.id) : "0";
  const everyone = bits(everyoneRole?.permissions);

  // Highest role first, as Discord lists them; the app's lowest position
  // is first. Templates number roles from the bottom up, so without
  // positions the highest id is the highest role.
  const sortedRoles = allRoles
    .filter((r) => r !== everyoneRole)
    .sort(
      (a, b) =>
        (b.position ?? 0) - (a.position ?? 0) ||
        String(b.id).localeCompare(String(a.id), undefined, { numeric: true }),
    );
  const kept = sortedRoles.slice(0, maxRoles);
  const roles: PlannedRole[] = kept.map((r, i) => ({
    key: String(r.id),
    name: clip(r.name, maxRoleName, "Role"),
    color: r.color ? (0xff000000 | (r.color & 0xffffff)) >>> 0 : 0,
    position: i,
    perms: appPermissions(bits(r.permissions)),
  }));
  const rolePerms = kept.map((r) => ({ key: String(r.id), perms: bits(r.permissions) }));

  const channels = [...(guild.channels ?? [])].sort(byPosition);
  const categories = channels.filter((c) => c.type === ChannelType.category);
  const folders: PlannedFolder[] = categories.map((c, i) => ({
    key: String(c.id),
    name: clip(c.name, maxChatName, "Folder"),
    position: i,
    ...accessOf(c, everyone, everyoneKey, rolePerms),
  }));
  const folderKeys = new Set(folders.map((f) => f.key));

  const rooms: PlannedRoom[] = [];
  const skipped: SkippedChannel[] = [];
  const counts = new Map<string, number>();
  for (const c of channels) {
    if (c.type === ChannelType.category) continue;
    const name = clip(c.name, maxChatName, "room");
    if (!roomTypes.has(c.type ?? -1)) {
      skipped.push({
        name,
        reason: c.type === ChannelType.voice || c.type === ChannelType.stage ? "Voice channel" : "Unsupported channel",
      });
      continue;
    }
    if (rooms.length >= maxRooms) {
      skipped.push({ name, reason: "Too many channels" });
      continue;
    }
    const parent = c.parent_id === null || c.parent_id === undefined ? null : String(c.parent_id);
    const folderKey = parent !== null && folderKeys.has(parent) ? parent : null;
    const position = counts.get(folderKey ?? "") ?? 0;
    counts.set(folderKey ?? "", position + 1);
    rooms.push({ name, folderKey, position, ...accessOf(c, everyone, everyoneKey, rolePerms) });
  }

  return {
    serverName: clip(guild.name ?? template.name, 100, "Discord server"),
    roles,
    folders,
    rooms,
    skipped,
    skippedRoles: sortedRoles.slice(maxRoles).map((r) => clip(r.name, maxRoleName, "Role")),
  };
}
