// Ports of the team rule functions in firebase/firestore.rules (match
// /teams/{teamId}): who may change what, and what each change writes.
// Pure: each takes the team as stored and returns the fields to write, or
// throws an ApiError saying why not. The Admin SDK skips the rules, so
// these are what guard team membership for writes through the API.
import {
  type EditTeamInput,
  type GroupLocation,
  roleLimits,
  searchKeywords,
  type TeamKind,
  type TeamPermission,
  teamTiers,
} from "@stall10/shared";
import { ApiError } from "../errors.js";
import type { Data } from "../store.js";

// ---- Reading a team doc (no prototype keys: a uid can be "constructor") ----

const isMap = (v: unknown): v is Record<string, unknown> =>
  !!v && typeof v === "object" && !Array.isArray(v) && !(v instanceof Date);
export const mapOf = (v: unknown): Record<string, unknown> => (isMap(v) ? v : {});
export const strings = (v: unknown): string[] => (Array.isArray(v) ? v.filter((x) => typeof x === "string") : []);
export const own = (m: unknown, key: string): unknown => (isMap(m) && Object.hasOwn(m, key) ? m[key] : undefined);
const str = (v: unknown, fallback = "") => (typeof v === "string" ? v : fallback);

export const clip = (s: string, max: number) => (s.length > max ? s.substring(0, max) : s);

// ---- The rules' helpers --------------------------------------------------

/** roleIn(team): the caller's tier, or "". */
export const roleIn = (t: Data, uid: string) => str(own(t.members, uid));
export const isOwner = (t: Data, uid: string) => roleIn(t, uid) === "owner";
export const isEditor = (t: Data, uid: string) => ["owner", "coach", "captain"].includes(roleIn(t, uid));
export const isMember = (t: Data, uid: string) => strings(t.memberIds).includes(uid);
export const permsOf = (t: Data, uid: string) => strings(own(t.memberPerms, uid));

/** can(team, perm): owners, coaches and captains, or a member granted [perm]. */
export const can = (t: Data, uid: string, perm: TeamPermission) =>
  isEditor(t, uid) || (isMember(t, uid) && permsOf(t, uid).includes(perm));

export function kindOf(t: Data): TeamKind {
  return t.kind === "community" || t.kind === "organization" ? t.kind : "team";
}
export const isGroup = (t: Data) => kindOf(t) !== "team";
export const isOrg = (t: Data) => kindOf(t) === "organization";
export const isPrivateGroup = (t: Data) => isGroup(t) && t.requiresApproval === true;

/** "team", "group" or "community", as the app says it (TeamKind.noun). */
export const nounOf = (t: Data) => ({ team: "team", community: "group", organization: "community" })[kindOf(t)];

const denied = (message: string) => new ApiError("permission_denied", message);

/** Throws unless the caller has [perm] on [t]. */
export function requirePermission(t: Data, uid: string, perm: TeamPermission, message: string) {
  if (!can(t, uid, perm)) throw denied(message);
}

// ---- Joining (join, joinOpenGroup, acceptInvite, approveRequest: addsOnly) ----

/** addsOnly(uid): [uid] joins as a player, named [name]. */
export function addMember(t: Data, uid: string, name: string): Data {
  if (isMember(t, uid)) throw new ApiError("already_exists", `You're already in this ${nounOf(t)}.`);
  return {
    members: { ...mapOf(t.members), [uid]: "player" },
    memberIds: [...strings(t.memberIds), uid],
    memberNames: { ...mapOf(t.memberNames), [uid]: clip(name, roleLimits.memberName) },
  };
}

// ---- removeMember ----------------------------------------------------------

/**
 * A member leaves, the owner removes anyone but themself, and coaches,
 * captains and members with manageMembers remove players who have no
 * permissions of their own. Stats access, custom roles and community
 * membership go with them.
 */
export function removeMember(t: Data, caller: string, target: string): Data {
  if (!isMember(t, target)) throw new ApiError("not_found", `They're not in this ${nounOf(t)}.`);
  if (target === t.ownerId) {
    throw new ApiError(
      "failed_precondition",
      target === caller
        ? `The owner can't leave. Make someone else the owner first.`
        : `The owner can't be removed.`,
    );
  }
  const allowed =
    target === caller ||
    roleIn(t, caller) === "owner" ||
    (can(t, caller, "manageMembers") &&
      ["player", "stats"].includes(roleIn(t, target)) &&
      permsOf(t, target).length === 0);
  if (!allowed) throw denied("You can't remove this member.");

  const without = (m: unknown) => Object.fromEntries(Object.entries(mapOf(m)).filter(([k]) => k !== target));
  const update: Data = {
    members: without(t.members),
    memberIds: strings(t.memberIds).filter((u) => u !== target),
    memberNames: without(t.memberNames),
    statKeepers: strings(t.statKeepers).filter((u) => u !== target),
  };
  if ("memberRoles" in t) update.memberRoles = without(t.memberRoles);
  if ("memberPerms" in t) update.memberPerms = without(t.memberPerms);
  if ("orgMembers" in t) update.orgMembers = strings(t.orgMembers).filter((u) => u !== target);
  return update;
}

// ---- changeRole ------------------------------------------------------------

const legacyAdmin = (roles: string[]) => roles.filter((r) => r === "coach" || r === "captain").length;

/**
 * The owner changes another member's tier. Only an owner and players now:
 * legacy coaches and captains may be moved down but nobody new becomes
 * one, there's still exactly one owner (ownership moves by transfer), and
 * nobody new gets the old "stats" tier (that's statKeepers). Returns null
 * when nothing changes.
 */
export function changeRole(t: Data, caller: string, target: string, role: string): Data | null {
  if (roleIn(t, caller) !== "owner") throw denied("Only the owner can change roles.");
  const members = mapOf(t.members);
  if (!Object.hasOwn(members, target)) throw new ApiError("not_found", `They're not in this ${nounOf(t)}.`);
  if (target === t.ownerId) throw new ApiError("failed_precondition", "The owner's role can't be changed.");
  if (members[target] === role) return null;
  if (role === "owner") {
    throw new ApiError("failed_precondition", "Make them the owner with Transfer ownership.");
  }

  const after = { ...members, [target]: role };
  const before = Object.values(members).map(String);
  const roles = Object.values(after).map(String);
  if (!roles.every((r) => (teamTiers as readonly string[]).includes(r))) {
    throw new ApiError("failed_precondition", "This team has a member with an unknown role.");
  }
  const admins = legacyAdmin(roles);
  if (!(admins < legacyAdmin(before) || admins === 0)) {
    throw new ApiError("failed_precondition", "Give them a custom role instead.");
  }
  if (roles.filter((r) => r === "owner").length !== 1) {
    throw new ApiError("failed_precondition", "A team has exactly one owner.");
  }
  if (roles.filter((r) => r !== "stats").length < before.filter((r) => r !== "stats").length) {
    throw new ApiError("failed_precondition", "Give them stats access instead.");
  }
  return { members: after };
}

// ---- setStatKeepers --------------------------------------------------------

/** The owner gives a member stats access or takes it away. */
export function setStatKeeper(t: Data, caller: string, target: string, on: boolean): Data | null {
  if (roleIn(t, caller) !== "owner") throw denied("Only the owner can give stats access.");
  const keepers = strings(t.statKeepers);
  if (on === keepers.includes(target)) return null;
  if (on && !isMember(t, target)) throw new ApiError("not_found", "They're not on this team.");
  // The rule wants every keeper to be a member: drop any who left.
  const ids = new Set(strings(t.memberIds));
  const next = (on ? [...keepers, target] : keepers.filter((u) => u !== target)).filter((u) => ids.has(u));
  if (next.length > roleLimits.statKeepers) {
    throw new ApiError("failed_precondition", `A team can have up to ${roleLimits.statKeepers} stat keepers.`);
  }
  return { statKeepers: next };
}

// ---- transferOwnership -----------------------------------------------------

/** The owner hands the team to another member and becomes a player. */
export function transferOwnership(t: Data, caller: string, next: string): Data {
  if (roleIn(t, caller) !== "owner" || t.ownerId !== caller) {
    throw denied("Only the owner can hand over the team.");
  }
  if (next === caller) throw new ApiError("invalid_argument", "You're already the owner.");
  if (!isMember(t, next) || !Object.hasOwn(mapOf(t.members), next)) {
    throw new ApiError("not_found", `They're not in this ${nounOf(t)}.`);
  }
  return { ownerId: next, members: { ...mapOf(t.members), [next]: "owner", [caller]: "player" } };
}

// ---- editDetails and the directory listing ---------------------------------

/** A stored location as the app reads it (GroupLocation.fromMap). */
export function locationOf(v: unknown): GroupLocation | null {
  if (!isMap(v) || typeof v.lat !== "number" || typeof v.lng !== "number") return null;
  return { address: String(v.address ?? ""), lat: v.lat, lng: v.lng };
}

/**
 * The team's directory listing (TeamListing.of(team).toMap() in the app):
 * its details, a group's fields (a private group's location left out), the
 * official mark, and search keywords.
 */
export function listingFor(t: Data): Data {
  const name = str(t.name);
  const city = str(t.city);
  const kind = kindOf(t);
  const listing: Data = { name, division: str(t.division, "mixed"), level: str(t.level, "club"), city };
  if (kind !== "team") {
    listing.kind = kind;
    listing.description = str(t.description);
    listing.requiresApproval = t.requiresApproval === true;
    listing.location = isPrivateGroup(t) ? null : locationOf(t.location);
  }
  if (t.official === true) listing.official = true;
  listing.keywords = searchKeywords(`${name} ${city}`);
  return listing;
}

/**
 * Admins (manageTeam) edit the details. The kind never changes and only
 * groups have group fields; nor does the division (names are unique per
 * division; changing it goes through support).
 */
export function editDetails(t: Data, caller: string, e: EditTeamInput): Data {
  requirePermission(t, caller, "manageTeam", `You can't edit this ${nounOf(t)}.`);
  if (e.division != null && e.division !== str(t.division, "mixed")) {
    throw new ApiError("failed_precondition", "A team's division can't be changed.");
  }
  const update: Data = { name: e.name, level: e.level, city: e.city };
  const groupFields = e.description !== undefined || e.requiresApproval !== undefined || e.location !== undefined;
  if (isGroup(t)) {
    if (e.description !== undefined) update.description = e.description;
    if (e.requiresApproval !== undefined) update.requiresApproval = e.requiresApproval;
    if (e.location !== undefined) update.location = e.location;
  } else if (groupFields) {
    throw new ApiError("invalid_argument", "Only groups have a description, approval setting or location.");
  }
  return update;
}
