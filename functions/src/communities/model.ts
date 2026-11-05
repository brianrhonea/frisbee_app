/**
 * School and club communities (kind "organization" team docs) link full
 * teams. A team is in a community once both sides agree: the team names
 * it (`orgId`, set by the team's admins) and the community lists the team
 * (`linkedTeams.{teamId}`, set by its admins, with the community roles
 * that get on the team). These pure helpers say who joins or leaves each
 * team when either side changes; functions.ts applies them.
 */

export type Data = Record<string, unknown>;

export type OrgDoc = {
  kind?: string;
  name?: string;
  memberIds?: string[];
  memberNames?: Record<string, string>;
  memberRoles?: Record<string, string[]>;
  linkedTeams?: Record<string, { name?: string; roles?: string[] }>;
};

export type TeamDoc = {
  kind?: string;
  ownerId?: string;
  members?: Record<string, string>;
  memberIds?: string[];
  memberNames?: Record<string, string>;
  memberRoles?: Record<string, string[]>;
  memberPerms?: Record<string, string[]>;
  statKeepers?: string[];
  orgId?: string | null;
  orgName?: string;
  orgLinked?: boolean;
  orgMembers?: string[];
  /** Custom roles by id; only their permissions matter here. */
  roles?: Record<string, { perms?: string[] }>;
  /** Team role id -> the community role it copies (Team.orgRoles). */
  orgRoles?: Record<string, string>;
};

export const isOrg = (d: { kind?: string } | undefined): boolean => d?.kind === "organization";

/** Community members holding any of [roles]. */
export function holders(org: OrgDoc | undefined, roles: string[] | undefined): Set<string> {
  const wanted = new Set(roles ?? []);
  const out = new Set<string>();
  if (!org || wanted.size === 0) return out;
  const ids = new Set(org.memberIds ?? []);
  for (const [uid, mine] of Object.entries(org.memberRoles ?? {})) {
    if (ids.has(uid) && (mine ?? []).some((r) => wanted.has(r))) out.add(uid);
  }
  return out;
}

/** What a change to a community means for one listed (or unlisted) team. */
export type TeamChange = {
  teamId: string;
  listed: boolean;
  /** Everyone the team's roles cover now, for a team that just joined. */
  all: string[];
  add: string[];
  remove: string[];
  renamed: boolean;
};

/** Per team the community lists before or after the change (listed teams always). */
export function planOrgChange(before: OrgDoc | undefined, after: OrgDoc | undefined): TeamChange[] {
  const ids = new Set([
    ...Object.keys(before?.linkedTeams ?? {}),
    ...Object.keys(after?.linkedTeams ?? {}),
  ]);
  const renamed = (before?.name ?? "") !== (after?.name ?? "");
  const changes: TeamChange[] = [];
  for (const teamId of ids) {
    const was = before?.linkedTeams?.[teamId];
    const now = after?.linkedTeams?.[teamId];
    const hadRole = was ? holders(before, was.roles) : new Set<string>();
    const hasRole = now ? holders(after, now.roles) : new Set<string>();
    const add = [...hasRole].filter((u) => !hadRole.has(u));
    const remove = [...hadRole].filter((u) => !hasRole.has(u));
    // Listed teams always get a look, so one the community never linked
    // (e.g. roles given before this function ran) catches up; the sync
    // writes nothing when nothing changes.
    if (!was && !now) continue;
    changes.push({ teamId, listed: !!now, all: [...hasRole], add, remove, renamed });
  }
  return changes;
}

/**
 * The team doc update that adds [add] (as players, unless already on the
 * team) and removes [remove] (only those the community added, never the
 * owner), or null if nothing changes.
 */
export function membershipUpdate(
  team: TeamDoc,
  add: string[],
  remove: string[],
  names: Record<string, string>,
): Data | null {
  const members = { ...(team.members ?? {}) };
  const memberIds = [...(team.memberIds ?? [])];
  const memberNames = { ...(team.memberNames ?? {}) };
  const memberRoles = { ...(team.memberRoles ?? {}) };
  const memberPerms = { ...(team.memberPerms ?? {}) };
  let statKeepers = [...(team.statKeepers ?? [])];
  const orgMembers = new Set(team.orgMembers ?? []);
  let changed = false;

  for (const uid of add) {
    if (memberIds.includes(uid)) continue;
    members[uid] = "player";
    memberIds.push(uid);
    memberNames[uid] = (names[uid] ?? "").slice(0, 80) || "Member";
    orgMembers.add(uid);
    changed = true;
  }
  for (const uid of remove) {
    if (!orgMembers.has(uid)) continue;
    orgMembers.delete(uid);
    changed = true;
    if (uid === team.ownerId || members[uid] === "owner") continue;
    delete members[uid];
    delete memberNames[uid];
    delete memberRoles[uid];
    delete memberPerms[uid];
    statKeepers = statKeepers.filter((u) => u !== uid);
    const i = memberIds.indexOf(uid);
    if (i >= 0) memberIds.splice(i, 1);
  }
  if (!changed) return null;
  return {
    members,
    memberIds,
    memberNames,
    memberRoles,
    memberPerms,
    statKeepers,
    orgMembers: [...orgMembers],
  };
}

const sameLists = (a: Record<string, string[]>, b: Record<string, string[]>): boolean => {
  const norm = (m: Record<string, string[]>) =>
    JSON.stringify(
      Object.keys(m)
        .filter((k) => (m[k] ?? []).length > 0)
        .sort()
        .map((k) => [k, [...m[k]].sort()]),
    );
  return norm(a) === norm(b);
};

/**
 * Who holds the team's copies of community roles (`orgRoles`, e.g. Woof
 * Captain): exactly the team's members holding the community role, so a
 * captain there is a captain here. Other roles are left alone, and
 * memberPerms is worked out again from every role (as the app's
 * memberPermsFor does). Null when nothing changes.
 */
export function mirrorUpdate(team: TeamDoc, org: OrgDoc | undefined): Data | null {
  const copies = Object.entries(team.orgRoles ?? {}).filter(([id]) => team.roles?.[id]);
  const copyIds = new Set(Object.keys(team.orgRoles ?? {}));
  if (copyIds.size === 0) return null;
  const inOrg = new Set(org?.memberIds ?? []);
  const memberRoles: Record<string, string[]> = {};
  const memberPerms: Record<string, string[]> = {};
  for (const uid of team.memberIds ?? []) {
    const held = inOrg.has(uid) ? (org?.memberRoles?.[uid] ?? []) : [];
    const roles = [
      ...(team.memberRoles?.[uid] ?? []).filter((r) => !copyIds.has(r) && team.roles?.[r]),
      ...copies.filter(([, source]) => held.includes(source)).map(([id]) => id),
    ];
    if (roles.length === 0) continue;
    memberRoles[uid] = roles;
    const perms = new Set(roles.flatMap((r) => team.roles?.[r]?.perms ?? []));
    if (perms.size > 0) memberPerms[uid] = [...perms].sort();
  }
  if (sameLists(memberRoles, team.memberRoles ?? {}) && sameLists(memberPerms, team.memberPerms ?? {})) {
    return null;
  }
  return { memberRoles, memberPerms };
}

/** membershipUpdate, then mirrorUpdate on the result, as one update. */
export function syncUpdate(
  team: TeamDoc,
  org: OrgDoc | undefined,
  add: string[],
  remove: string[],
  names: Record<string, string>,
): Data | null {
  const members = membershipUpdate(team, add, remove, names);
  const mirror = mirrorUpdate({ ...team, ...(members ?? {}) } as TeamDoc, org);
  return members || mirror ? { ...(members ?? {}), ...(mirror ?? {}) } : null;
}
