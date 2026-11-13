import { randomInt } from "node:crypto";
import {
  type CreateTeamInput,
  cleanMemberRoles,
  communityLinkRequestSchema,
  createCommunityTeamRequestSchema,
  createInviteCodeRequestSchema,
  editTeamRequestSchema,
  type InviteCodeResponse,
  inviteToTeamRequestSchema,
  joinByCodeRequestSchema,
  linkedTeamRolesRequestSchema,
  nameTakenMessage,
  normalizeInviteCode,
  roleLimits,
  rolesData,
  saveRolesRequestSchema,
  setMemberRoleRequestSchema,
  setStatKeeperRequestSchema,
  type TeamKind,
  type Division,
  teamNameClashes,
  teamNameKey,
  teamNameProbe,
  transferOwnershipRequestSchema,
} from "@stall10/shared";
import type { z } from "zod";
import { type Caller, callerLabel, type UserLookup } from "../auth.js";
import { ApiError, fromZod } from "../errors.js";
import { AlreadyExists, type Data, type DocStore, serverTime, type Tx } from "../store.js";
import {
  addMember,
  can,
  changeRole,
  clip,
  editDetails,
  isGroup,
  isMember,
  isOrg,
  isOwner,
  kindOf,
  listingFor,
  mapOf,
  nounOf,
  removeMember,
  requirePermission,
  setStatKeeper,
  strings,
  transferOwnership,
} from "./access.js";
import { newTeamDocuments } from "./documents.js";
import type { TeamRepository } from "./repository.js";
import { tooFastMessage } from "./service.js";

// Where everything lives (docs/ARCHITECTURE.md, firestore.rules).
const p = {
  team: (id: string) => `teams/${id}`,
  listing: (id: string) => `teamDirectory/${id}`,
  code: (code: string) => `inviteCodes/${code}`,
  join: (teamId: string, uid: string) => `teams/${teamId}/joins/${uid}`,
  request: (teamId: string, uid: string) => `teams/${teamId}/joinRequests/${uid}`,
  invite: (uid: string, teamId: string) => `users/${uid}/teamInvites/${teamId}`,
  linkRequest: (orgId: string, teamId: string) => `teams/${orgId}/linkRequests/${teamId}`,
  limits: (uid: string) => `limits/${uid}`,
};

/** No 0/O/1/I, so codes read aloud easily (as the app mints them). */
const codeAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

function parse<S extends z.ZodType>(schema: S, body: unknown): z.output<S> {
  const r = schema.safeParse(body ?? {});
  if (!r.success) throw fromZod(r.error);
  return r.data;
}

const notFound = (what = "team") => new ApiError("not_found", `That ${what} doesn't exist anymore.`);

/**
 * Team membership and management: joining (code or link, open groups,
 * requests, invites), leaving and removing, roles, stat keepers,
 * ownership, details, invite codes, and school or club communities.
 *
 * Each operation reads what its rule in firebase/firestore.rules read and
 * checks the same conditions (access.ts) inside one transaction, then
 * writes what the app wrote. Names written come from the Auth record.
 */
export class MembershipService {
  constructor(
    private readonly store: DocStore,
    private readonly users: UserLookup,
    private readonly teams: Pick<TeamRepository, "listingsWithKeywords">,
    private readonly now: () => number = Date.now,
    private readonly randomCode: (length: number) => string = (n) =>
      Array.from({ length: n }, () => codeAlphabet[randomInt(codeAlphabet.length)]).join(""),
  ) {}

  /** The caller's name as the app shows it, from their Auth record. */
  private async label(caller: Caller): Promise<string> {
    const user = await this.users.lookup(caller.uid);
    return clip(callerLabel({ uid: caller.uid, ...(user ?? { name: caller.name, email: caller.email }) }), 80);
  }

  /**
   * communityInvites() in the teamInvites rule: a community's member
   * managers also invite people to the teams it accepted (orgLinked, and
   * listed in its linkedTeams), without being on them.
   */
  private async communityInvites(tx: Tx, team: Data, teamId: string, uid: string): Promise<boolean> {
    if (team.orgLinked !== true || typeof team.orgId !== "string" || !team.orgId) return false;
    const org = await tx.get(p.team(team.orgId));
    return !!org && can(org, uid, "manageMembers") && Object.hasOwn(mapOf(org.linkedTeams), teamId);
  }

  private async team(tx: Tx, id: string): Promise<Data> {
    const t = await tx.get(p.team(id));
    if (!t) throw notFound();
    return t;
  }

  /** notMuted(): the flood mute the functions set on limits/{uid}. */
  private async checkNotMuted(uid: string) {
    const until = (await this.store.get(p.limits(uid)))?.mutedUntil;
    const now = this.now();
    if (until instanceof Date && until.getTime() > now) {
      throw new ApiError("resource_exhausted", tooFastMessage(until.getTime(), now));
    }
  }

  /** Throws if another [kind] (in [division], for teams) has the name. */
  private async ensureNameFree(name: string, kind: TeamKind, division: Division, excludeId?: string) {
    const listings = await this.teams.listingsWithKeywords(teamNameProbe(name), 200);
    const clash = listings.find((l) => teamNameClashes(l, { name, kind, division, excludeId }));
    if (clash) throw new ApiError("already_exists", nameTakenMessage(clash.name, kind, division));
  }

  // ---- Joining -------------------------------------------------------------

  /**
   * join(): a non-member joins as a player with a live invite code or link
   * token for the team (createdAt + ttl on the server's clock). Writes the
   * joins/{uid} proof as the app does. Returns the team id.
   */
  async joinByCode(caller: Caller, body: unknown): Promise<string> {
    const code = normalizeInviteCode(parse(joinByCodeRequestSchema, body).code);
    if (!code) throw new ApiError("not_found", "No team found for that invite code.");
    const name = await this.label(caller);
    return this.store.transact(async (tx) => {
      const invite = await tx.get(p.code(code));
      const teamId = typeof invite?.teamId === "string" ? invite.teamId : null;
      if (!invite || !teamId) throw new ApiError("not_found", "No team found for that invite code.");
      const createdAt = invite.createdAt;
      const ttl = invite.ttl;
      // Codes from before rotation have neither and no longer work.
      if (!(createdAt instanceof Date) || typeof ttl !== "number" || this.now() >= createdAt.getTime() + ttl * 1000) {
        throw new ApiError("failed_precondition", "That invite has expired. Ask for a new code or link.");
      }
      const team = await tx.get(p.team(teamId));
      if (!team) throw new ApiError("not_found", "No team found for that invite code.");
      // Already in: nothing to do (the rule refuses, so no one's role drops).
      if (isMember(team, caller.uid)) return teamId;
      tx.set(p.join(teamId, caller.uid), { code });
      tx.update(p.team(teamId), addMember(team, caller.uid, name));
      return teamId;
    });
  }

  /** joinOpenGroup(): anyone joins a group that doesn't need approval. */
  async joinGroup(caller: Caller, teamId: string): Promise<void> {
    const name = await this.label(caller);
    await this.store.transact(async (tx) => {
      const team = await this.team(tx, teamId);
      if (isMember(team, caller.uid)) return;
      if (!isGroup(team)) throw new ApiError("permission_denied", "Join a team with an invite code or link.");
      if (team.requiresApproval === true) {
        throw new ApiError("failed_precondition", "This group needs approval. Ask to join instead.");
      }
      tx.update(p.team(teamId), addMember(team, caller.uid, name));
    });
  }

  /**
   * joinRequests create: a non-member asks to join a group that needs
   * approval (flood-controlled, so not while muted).
   */
  async requestToJoin(caller: Caller, teamId: string): Promise<void> {
    await this.checkNotMuted(caller.uid);
    const name = await this.label(caller);
    await this.store.transact(async (tx) => {
      const team = await this.team(tx, teamId);
      const existing = await tx.get(p.request(teamId, caller.uid));
      if (!isGroup(team) || team.requiresApproval !== true) {
        throw new ApiError("failed_precondition", "This doesn't take join requests.");
      }
      if (isMember(team, caller.uid)) throw new ApiError("already_exists", `You're already in this ${nounOf(team)}.`);
      if (existing) return;
      tx.create(p.request(teamId, caller.uid), { name, createdAt: serverTime });
    });
  }

  /** joinRequests delete: the asker withdraws, or a manageMembers admin declines. */
  async deleteJoinRequest(caller: Caller, teamId: string, uid: string): Promise<void> {
    await this.store.transact(async (tx) => {
      if (uid !== caller.uid) {
        const team = await this.team(tx, teamId);
        requirePermission(team, caller.uid, "manageMembers", "You can't answer join requests here.");
      }
      tx.delete(p.request(teamId, uid));
    });
  }

  /**
   * approveRequest(): a manageMembers admin of a group adds someone who
   * asked, as a member named as in their request, and clears the request.
   */
  async approveJoinRequest(caller: Caller, teamId: string, uid: string): Promise<void> {
    await this.store.transact(async (tx) => {
      const team = await this.team(tx, teamId);
      const request = await tx.get(p.request(teamId, uid));
      if (!isGroup(team)) throw new ApiError("failed_precondition", "Only groups take join requests.");
      requirePermission(team, caller.uid, "manageMembers", "You can't answer join requests here.");
      if (!request) throw new ApiError("not_found", "That request was withdrawn.");
      const name = typeof request.name === "string" && request.name ? request.name : "Member";
      if (isMember(team, uid)) {
        tx.delete(p.request(teamId, uid));
        return;
      }
      tx.update(p.team(teamId), addMember(team, uid, name));
      tx.delete(p.request(teamId, uid));
    });
  }

  /**
   * teamInvites create: a manageMembers admin invites someone who isn't a
   * member. Inviting again refreshes the invite.
   */
  async invite(caller: Caller, teamId: string, body: unknown): Promise<void> {
    const { uid } = parse(inviteToTeamRequestSchema, body);
    const by = await this.label(caller);
    await this.store.transact(async (tx) => {
      const team = await this.team(tx, teamId);
      if (!can(team, caller.uid, "manageMembers") && !(await this.communityInvites(tx, team, teamId, caller.uid))) {
        throw new ApiError("permission_denied", `You can't invite people to this ${nounOf(team)}.`);
      }
      if (isMember(team, uid)) throw new ApiError("already_exists", `They're already in this ${nounOf(team)}.`);
      tx.set(p.invite(uid, teamId), {
        teamName: String(team.name ?? ""),
        kind: kindOf(team),
        invitedBy: caller.uid,
        invitedByName: by,
        createdAt: serverTime,
      });
    });
  }

  /**
   * acceptInvite(): someone invited joins as a player, with no code; the
   * invite (the rule's proof) and any join request of theirs are cleared.
   */
  async acceptInvite(caller: Caller, teamId: string): Promise<void> {
    const name = await this.label(caller);
    await this.store.transact(async (tx) => {
      const invite = await tx.get(p.invite(caller.uid, teamId));
      const team = await tx.get(p.team(teamId));
      if (!invite) throw new ApiError("not_found", "That invite was withdrawn.");
      if (!team) throw notFound();
      if (!isMember(team, caller.uid)) tx.update(p.team(teamId), addMember(team, caller.uid, name));
      tx.delete(p.invite(caller.uid, teamId));
      tx.delete(p.request(teamId, caller.uid));
    });
  }

  /** teamInvites delete: the invitee declines. */
  async declineInvite(caller: Caller, teamId: string): Promise<void> {
    await this.store.transact(async (tx) => {
      tx.delete(p.invite(caller.uid, teamId));
    });
  }

  // ---- Members -------------------------------------------------------------

  /** removeMember(): leave, or remove someone (see access.ts). */
  async removeMember(caller: Caller, teamId: string, uid: string): Promise<void> {
    await this.store.transact(async (tx) => {
      const team = await this.team(tx, teamId);
      tx.update(p.team(teamId), removeMember(team, caller.uid, uid));
    });
  }

  /** changeRole(). */
  async setMemberRole(caller: Caller, teamId: string, uid: string, body: unknown): Promise<void> {
    const { role } = parse(setMemberRoleRequestSchema, body);
    await this.store.transact(async (tx) => {
      const team = await this.team(tx, teamId);
      const update = changeRole(team, caller.uid, uid, role);
      if (update) tx.update(p.team(teamId), update);
    });
  }

  /** setStatKeepers(). */
  async setStatKeeper(caller: Caller, teamId: string, uid: string, body: unknown): Promise<void> {
    const { on } = parse(setStatKeeperRequestSchema, body);
    await this.store.transact(async (tx) => {
      const team = await this.team(tx, teamId);
      const update = setStatKeeper(team, caller.uid, uid, on);
      if (update) tx.update(p.team(teamId), update);
    });
  }

  /** transferOwnership(). */
  async transferOwnership(caller: Caller, teamId: string, body: unknown): Promise<void> {
    const { uid } = parse(transferOwnershipRequestSchema, body);
    await this.store.transact(async (tx) => {
      const team = await this.team(tx, teamId);
      tx.update(p.team(teamId), transferOwnership(team, caller.uid, uid));
    });
  }

  /**
   * setRoles(): the owner replaces the custom roles and who has them. Who
   * has which is cleaned to current members and existing roles, and each
   * member's permissions (memberPerms) are worked out here, never taken
   * from the body. Tiers and community role copies (orgRoles) stay.
   */
  async saveRoles(caller: Caller, teamId: string, body: unknown): Promise<void> {
    const input = parse(saveRolesRequestSchema, body);
    await this.store.transact(async (tx) => {
      const team = await this.team(tx, teamId);
      if (!isOwner(team, caller.uid)) throw new ApiError("permission_denied", "Only the owner can edit roles.");
      const ids = new Set(strings(team.memberIds));
      const members = Object.keys(mapOf(team.members)).filter((u) => ids.has(u));
      const memberRoles = cleanMemberRoles(input.memberRoles, input.roles, members);
      tx.update(p.team(teamId), rolesData(input.roles, memberRoles));
    });
  }

  // ---- Details and the directory -------------------------------------------

  /**
   * editDetails(), and the team's directory listing rewritten to match in
   * the same transaction. A new name must be free, as the app checks.
   */
  async editTeam(caller: Caller, teamId: string, body: unknown): Promise<void> {
    const input = parse(editTeamRequestSchema, body);
    const [current, listed] = await Promise.all([this.store.get(p.team(teamId)), this.store.get(p.listing(teamId))]);
    if (!current) throw notFound();
    requirePermission(current, caller.uid, "manageTeam", `You can't edit this ${nounOf(current)}.`);
    const kind = kindOf(current);
    const division = (typeof current.division === "string" ? current.division : "mixed") as Division;
    // Renamed (or never listed): the new name must be free.
    if (!listed || teamNameKey(String(listed.name ?? "")) !== teamNameKey(input.name)) {
      await this.ensureNameFree(input.name, kind, division, teamId);
    }
    await this.store.transact(async (tx) => {
      const team = await this.team(tx, teamId);
      const update = editDetails(team, caller.uid, input);
      tx.update(p.team(teamId), update);
      tx.set(p.listing(teamId), listingFor({ ...team, ...update }));
    });
  }

  /** teamDirectory write: a manageTeam admin republishes the listing. */
  async publishListing(caller: Caller, teamId: string): Promise<void> {
    await this.store.transact(async (tx) => {
      const team = await this.team(tx, teamId);
      requirePermission(team, caller.uid, "manageTeam", `You can't edit this ${nounOf(team)}.`);
      tx.set(p.listing(teamId), listingFor(team));
    });
  }

  // ---- Invite codes --------------------------------------------------------

  /**
   * inviteCodes create: manageMembers admins of a team or community (not a
   * community group, which anyone finds and joins) mint a short code (ttl
   * 45 s) or a link token (an hour to 30 days). Codes are made here.
   */
  async createInviteCode(caller: Caller, body: unknown): Promise<InviteCodeResponse> {
    const { teamId, ttl } = parse(createInviteCodeRequestSchema, body);
    const team = await this.store.get(p.team(teamId));
    if (!team) throw notFound();
    requirePermission(team, caller.uid, "manageMembers", `You can't invite people to this ${nounOf(team)}.`);
    if (kindOf(team) === "community") {
      throw new ApiError("failed_precondition", "Groups don't use invite codes; anyone can find them.");
    }
    const length = ttl === 45 ? 6 : 20;
    for (let attempt = 0; ; attempt++) {
      const code = this.randomCode(length);
      const expiresAt = new Date(this.now() + ttl * 1000);
      try {
        await this.store.transact(async (tx) => {
          tx.create(p.code(code), { teamId, createdBy: caller.uid, createdAt: serverTime, ttl, expiresAt });
        });
        return { code, teamId, expiresAt: expiresAt.toISOString() };
      } catch (e) {
        // A code in use: try a fresh one.
        if (!(e instanceof AlreadyExists) || attempt >= 2) throw e;
      }
    }
  }

  // ---- School and club communities -----------------------------------------

  /** The community [orgId], checked editLinks()-style for the caller. */
  private async orgForLinks(tx: Tx, orgId: string, caller: string): Promise<Data> {
    const org = await tx.get(p.team(orgId));
    if (!org || !isOrg(org)) throw notFound("community");
    requirePermission(org, caller, "manageTeam", "You can't manage this community's teams.");
    return org;
  }

  private static linked(org: Data) {
    return mapOf(org.linkedTeams);
  }

  private static checkLinkLimit(links: Record<string, unknown>) {
    if (Object.keys(links).length > roleLimits.linkedTeams) {
      throw new ApiError("failed_precondition", `A community can link ${roleLimits.linkedTeams} teams.`);
    }
  }

  /**
   * setOrg() and linkRequests create: a team's manageTeam admin names the
   * community (orgId, orgName from its doc) and asks to join it.
   */
  async requestCommunityLink(caller: Caller, teamId: string, body: unknown): Promise<void> {
    const { orgId } = parse(communityLinkRequestSchema, body);
    if (orgId === teamId) throw new ApiError("invalid_argument", "A team can't join itself.");
    const by = await this.label(caller);
    await this.store.transact(async (tx) => {
      const team = await this.team(tx, teamId);
      const org = await tx.get(p.team(orgId));
      const existing = await tx.get(p.linkRequest(orgId, teamId));
      requirePermission(team, caller.uid, "manageTeam", "You can't change this team's community.");
      if (isGroup(team)) throw new ApiError("failed_precondition", "Only a team can join a community.");
      if (!org || !isOrg(org)) throw notFound("community");
      tx.update(p.team(teamId), { orgId, orgName: clip(String(org.name ?? ""), 80) });
      if (!existing) {
        tx.create(p.linkRequest(orgId, teamId), {
          teamName: clip(String(team.name ?? ""), 80),
          division: typeof team.division === "string" ? team.division : "mixed",
          requestedBy: caller.uid,
          requestedByName: by,
          createdAt: serverTime,
        });
      }
    });
  }

  /**
   * setOrg(): takes a team out of its community, or withdraws its request
   * (deleting it, as the asker may). The communities functions drop the
   * people the community added.
   */
  async leaveCommunity(caller: Caller, teamId: string): Promise<void> {
    await this.store.transact(async (tx) => {
      const team = await this.team(tx, teamId);
      requirePermission(team, caller.uid, "manageTeam", "You can't change this team's community.");
      if (isGroup(team)) throw new ApiError("failed_precondition", "Only a team can join a community.");
      const orgId = typeof team.orgId === "string" ? team.orgId : null;
      tx.update(p.team(teamId), { orgId: null, orgName: "" });
      if (orgId && team.orgLinked !== true) tx.delete(p.linkRequest(orgId, teamId));
    });
  }

  /** editLinks(): lists the asking team with [roles]; clears the request. */
  async acceptLinkRequest(caller: Caller, orgId: string, teamId: string, body: unknown): Promise<void> {
    const { roles } = parse(linkedTeamRolesRequestSchema, body);
    await this.store.transact(async (tx) => {
      const org = await this.orgForLinks(tx, orgId, caller.uid);
      const request = await tx.get(p.linkRequest(orgId, teamId));
      if (!request) throw new ApiError("not_found", "That request was withdrawn.");
      const links = {
        ...MembershipService.linked(org),
        [teamId]: {
          name: String(request.teamName ?? ""),
          division: typeof request.division === "string" ? request.division : "mixed",
          roles: [...new Set(roles)].sort(),
        },
      };
      MembershipService.checkLinkLimit(links);
      tx.update(p.team(orgId), { linkedTeams: links });
      tx.delete(p.linkRequest(orgId, teamId));
    });
  }

  /** linkRequests delete: the community's or the team's manageTeam admins. */
  async declineLinkRequest(caller: Caller, orgId: string, teamId: string): Promise<void> {
    await this.store.transact(async (tx) => {
      const org = await tx.get(p.team(orgId));
      const asker = await tx.get(p.team(teamId));
      const ok = (org && can(org, caller.uid, "manageTeam")) || (asker && can(asker, caller.uid, "manageTeam"));
      if (!ok) throw new ApiError("permission_denied", "You can't answer this request.");
      tx.delete(p.linkRequest(orgId, teamId));
    });
  }

  /** editLinks(): changes which community roles get on a listed team. */
  async saveLinkedTeam(caller: Caller, orgId: string, teamId: string, body: unknown): Promise<void> {
    const { roles } = parse(linkedTeamRolesRequestSchema, body);
    await this.store.transact(async (tx) => {
      const org = await this.orgForLinks(tx, orgId, caller.uid);
      const links = MembershipService.linked(org);
      const entry = mapOf(links[teamId]);
      if (!Object.hasOwn(links, teamId)) throw new ApiError("not_found", "That team isn't in this community.");
      tx.update(p.team(orgId), { linkedTeams: { ...links, [teamId]: { ...entry, roles: [...new Set(roles)].sort() } } });
    });
  }

  /** editLinks(): drops a team; the functions take its community members off. */
  async unlinkTeam(caller: Caller, orgId: string, teamId: string): Promise<void> {
    await this.store.transact(async (tx) => {
      const org = await this.orgForLinks(tx, orgId, caller.uid);
      const links = MembershipService.linked(org);
      if (!Object.hasOwn(links, teamId)) return;
      const { [teamId]: _, ...rest } = links;
      tx.update(p.team(orgId), { linkedTeams: rest });
    });
  }

  /**
   * A new team inside a community, listed at once with the community
   * [roles] that get on it: the team create rule (notMuted, the caller the
   * owner, orgId/orgName from the community) plus editLinks() on the
   * community, in one transaction. Returns the team id.
   */
  async createTeamInCommunity(caller: Caller, orgId: string, body: unknown): Promise<string> {
    const input = parse(createCommunityTeamRequestSchema, body);
    await this.checkNotMuted(caller.uid);
    await this.ensureNameFree(input.name, "team", input.division);
    const label = await this.label(caller);
    const teamId = this.store.newId("teams");
    const team: CreateTeamInput = {
      name: input.name,
      division: input.division,
      level: input.level,
      city: input.city,
      kind: "team",
      description: "",
      requiresApproval: false,
      location: null,
      leagueId: null,
    };
    await this.store.transact(async (tx) => {
      const org = await this.orgForLinks(tx, orgId, caller.uid);
      const links = {
        ...MembershipService.linked(org),
        [teamId]: { name: input.name, division: input.division, roles: [...new Set(input.roles)].sort() },
      };
      MembershipService.checkLinkLimit(links);
      const docs = newTeamDocuments(teamId, team, { uid: caller.uid, label }, serverTime, {
        id: orgId,
        name: clip(String(org.name ?? ""), 80),
      });
      for (const [path, data] of Object.entries(docs)) tx.create(path, data);
      tx.update(p.team(orgId), { linkedTeams: links });
    });
    return teamId;
  }
}
