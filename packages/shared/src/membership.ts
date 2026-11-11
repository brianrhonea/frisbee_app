// Team membership and management requests (ARCHITECTURE.md §10, item 2),
// and the pure role logic shared with the app: a port of cleanMemberRoles,
// memberPermsFor and rolesData in apps/mobile/lib/domain/models/
// team_role.dart, checked against packages/shared/fixtures/team_roles.json.
import { z } from "zod";
import { competitionLevels, divisions, groupLocationSchema, teamLimits } from "./team.js";

/** Member tiers on the team doc's `members` (TeamRole in the app). */
export const teamTiers = ["owner", "coach", "captain", "stats", "player"] as const;
export type TeamTier = (typeof teamTiers)[number];

/** What a custom role can grant (TeamPermission), in the app's order. */
export const teamPermissions = [
  "manageTeam",
  "manageMembers",
  "manageChats",
  "manageEvents",
  "moderate",
  "keepStats",
] as const;
export type TeamPermission = (typeof teamPermissions)[number];

/** Limits shared with the app (CustomRole, LinkedTeam) and firestore.rules. */
export const roleLimits = {
  /** Custom roles per team (CustomRole.maxRoles; setRoles). */
  roles: 50,
  roleName: 40,
  /** Teams a community links (LinkedTeam.max; editLinks). */
  linkedTeams: 20,
  /** statKeepers (setStatKeepers). */
  statKeepers: 200,
  memberName: 80,
} as const;

/** Invite code and link lifetimes, in seconds (inviteCodes rule). */
export const inviteTtls = [45, 3600, 86400, 604800, 2592000] as const;
export type InviteTtl = (typeof inviteTtls)[number];

/** A code as typed: upper case, letters and digits only (normalizeCode). */
export function normalizeInviteCode(code: string): string {
  return code.trim().toUpperCase().replace(/[^A-Z0-9]/g, "");
}

// Map keys written to Firestore: no path separators.
const docId = z.string().min(1).max(128).regex(/^[^/]+$/, "Invalid id.");
const roleId = z.string().min(1).max(64).regex(/^[^./]+$/, "Invalid role id.");

/** `POST /v1/teams/join`: join with an invite code or link token. */
export const joinByCodeRequestSchema = z.strictObject({
  code: z.string().max(64),
});
export interface JoinByCodeResponse {
  teamId: string;
}

/** `POST /v1/invite-codes`: mint a short code (ttl 45) or a link token. */
export const createInviteCodeRequestSchema = z.strictObject({
  teamId: docId,
  ttl: z
    .number()
    .refine((t): t is InviteTtl => (inviteTtls as readonly number[]).includes(t), "Pick how long the invite lasts."),
});
export interface InviteCodeResponse {
  code: string;
  teamId: string;
  /** ISO 8601. */
  expiresAt: string;
}

/** `PUT /v1/teams/:id/members/:uid/role`. Custom roles do the rest. */
export const setMemberRoleRequestSchema = z.strictObject({
  role: z.enum(["owner", "coach", "captain", "player"]),
});

/** `PUT /v1/teams/:id/members/:uid/stat-keeper`. */
export const setStatKeeperRequestSchema = z.strictObject({ on: z.boolean() });

/** `POST /v1/teams/:id/owner`: hand the team to another member. */
export const transferOwnershipRequestSchema = z.strictObject({ uid: docId });

/** `POST /v1/teams/:id/invites`: invite someone found in the directory. */
export const inviteToTeamRequestSchema = z.strictObject({ uid: docId });

export const customRoleSchema = z.strictObject({
  name: z.string().trim().min(1, "Name the role.").max(roleLimits.roleName),
  color: z.number().int().default(0),
  position: z.number().int().default(0),
  perms: z.array(z.enum(teamPermissions)).max(teamPermissions.length).default([]),
});
export type CustomRoleInput = z.output<typeof customRoleSchema>;

/**
 * `PUT /v1/teams/:id/roles`: the team's custom roles and who has which.
 * memberPerms is worked out by the API, never taken from the body.
 */
export const saveRolesRequestSchema = z.strictObject({
  roles: z
    .record(roleId, customRoleSchema)
    .refine((r) => Object.keys(r).length <= roleLimits.roles, `A team can have up to ${roleLimits.roles} roles.`),
  memberRoles: z.record(docId, z.array(roleId).max(roleLimits.roles)),
});
export type SaveRolesRequest = z.input<typeof saveRolesRequestSchema>;

/**
 * `PATCH /v1/teams/:id`: a team's or group's details (Team.toEditableMap).
 * The kind and the division never change; group fields are for groups.
 */
export const editTeamRequestSchema = z.strictObject({
  name: z.string().trim().min(1, "Name your team.").max(teamLimits.name),
  level: z.enum(competitionLevels),
  city: z.string().trim().max(teamLimits.city).default(""),
  /** Accepted only if unchanged. */
  division: z.enum(divisions).optional(),
  description: z.string().trim().max(teamLimits.description).optional(),
  requiresApproval: z.boolean().optional(),
  location: groupLocationSchema.nullable().optional(),
});
export type EditTeamRequest = z.input<typeof editTeamRequestSchema>;
export type EditTeamInput = z.output<typeof editTeamRequestSchema>;

/** `PUT /v1/teams/:id/community`: ask to put a team in a community. */
export const communityLinkRequestSchema = z.strictObject({ orgId: docId });

/** Community roles that put someone on a linked team. */
const linkRoles = z.array(roleId).max(roleLimits.roles);

/** Accepting a link request, or changing a linked team's roles. */
export const linkedTeamRolesRequestSchema = z.strictObject({ roles: linkRoles });

/** `POST /v1/teams/:orgId/linked-teams`: a new team in a community. */
export const createCommunityTeamRequestSchema = z.strictObject({
  name: z.string().trim().min(1, "Name your team.").max(teamLimits.name),
  division: z.enum(divisions),
  level: z.enum(competitionLevels),
  city: z.string().trim().max(teamLimits.city).default(""),
  roles: linkRoles.default([]),
});
export type CreateCommunityTeamInput = z.output<typeof createCommunityTeamRequestSchema>;

// ---- Role logic (team_role.dart) -------------------------------------------

const sorted = (xs: Iterable<string>) => [...new Set(xs)].sort();

/**
 * [memberRoles] cleaned for saving: only [members], only roles that exist,
 * no empty entries; each list sorted (cleanMemberRoles + rolesData).
 */
export function cleanMemberRoles(
  memberRoles: Record<string, readonly string[]>,
  roles: Record<string, unknown>,
  members: Iterable<string>,
): Record<string, string[]> {
  const keep = new Set(members);
  const out: Record<string, string[]> = {};
  for (const [uid, ids] of Object.entries(memberRoles)) {
    if (!keep.has(uid)) continue;
    const valid = ids.filter((id) => Object.hasOwn(roles, id));
    if (valid.length > 0) out[uid] = sorted(valid);
  }
  return out;
}

/** Each member's permissions from their roles (memberPermsFor). */
export function memberPermsFor(
  memberRoles: Record<string, readonly string[]>,
  roles: Record<string, { perms: readonly string[] }>,
): Record<string, TeamPermission[]> {
  const out: Record<string, TeamPermission[]> = {};
  for (const [uid, ids] of Object.entries(memberRoles)) {
    const perms = new Set<string>();
    for (const id of ids) {
      if (Object.hasOwn(roles, id)) for (const p of roles[id].perms) perms.add(p);
    }
    const ordered = teamPermissions.filter((p) => perms.has(p));
    if (ordered.length > 0) out[uid] = ordered;
  }
  return out;
}

/** The team doc fields for [roles] and cleaned [memberRoles] (rolesData). */
export function rolesData(roles: Record<string, CustomRoleInput>, memberRoles: Record<string, readonly string[]>) {
  const stored: Record<string, { name: string; color: number; position: number; perms: TeamPermission[] }> = {};
  for (const [id, r] of Object.entries(roles)) {
    stored[id] = {
      name: r.name.trim(),
      color: r.color,
      position: r.position,
      perms: teamPermissions.filter((p) => r.perms.includes(p)),
    };
  }
  const cleaned: Record<string, string[]> = {};
  for (const [uid, ids] of Object.entries(memberRoles)) cleaned[uid] = sorted(ids);
  return { roles: stored, memberRoles: cleaned, memberPerms: memberPermsFor(cleaned, stored) };
}
