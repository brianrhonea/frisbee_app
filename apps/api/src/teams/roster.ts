import {
  isYouthTeam,
  publicPageOn,
  type PublicRoster,
  type PublicRosterPlayer,
  rosterIsPublic,
  type OutsiderRosterMember,
  type OutsiderRosterPlayer,
  type OutsiderTeamRoster,
  type RosterMember,
  type RosterPerson,
  type RosterPlayer,
  type RosterTeam,
  rosterLineOf,
  rosterMax,
  staffTiers,
  setRosterLinesRequestSchema,
  type TeamRoster,
} from "@stall10/shared";
import type { AdultVisibility } from "../account/adult_visibility.js";
import type { Caller } from "../auth.js";
import { isPrivateProfile, validId } from "../browse/model.js";
import { isDraftedLeagueTeam } from "../browse/visibility.js";
import { ApiError, parseBody } from "../errors.js";
import { docIdParam } from "../ids.js";
import { type Data, type DocStore, deleteField } from "../store.js";
import { can, isGroup, mapOf } from "./access.js";
import { trustedProfilePhoto } from "../media/photo_url.js";

const positions = ["handler", "cutter", "hybrid"] as const;
/** What anyone who isn't on a youth team sees in place of its roster (the app and website say the same). */
export const youthRosterPrivate = "Rosters of youth teams are private: only members see them.";
/** What anyone who isn't on a team with its public page off sees in place of its roster. */
export const teamPagePrivate = "This team's page is private: only members see its roster.";
const kinds = ["team", "community", "organization"] as const;
/** Tiers first by rank, then everyone else by name (the app's roster order). */
const tierOrder = ["owner", "coach", "captain", "stats", "player"];

const str = (v: unknown) => (typeof v === "string" ? v : "");

/**
 * Who's on a team, for anyone signed in: the roster's players and the
 * members, each with their public profile card. The rules keep `roster/*`
 * and the team doc to members, so this reads them with the Admin SDK and
 * returns only names, numbers, positions, tiers, role names and a
 * community's team names, never
 * permissions, stats keepers, paid marks or anything else on the team doc.
 * A private group (a community or organization that approves joins) shows
 * its members only to members, as its posts and events are (showsPublic
 * and isPrivateGroup in the rules).
 */
export class RosterService {
  constructor(
    private readonly store: DocStore,
    /** Buckets visitors may load profile photos from (visibility.ts photoBuckets). */
    _buckets: readonly string[] = [],
    /** D-1317: linked accounts without the adult claim are shown as private. */
    private readonly adults?: AdultVisibility,
  ) {}

  /**
   * Whether [uid] manages members of the school or club community that
   * accepted [team] (orgLinked, and listed in its linkedTeams), as
   * communityInvites() in the teamInvites rule.
   */
  private async managesOrgOf(team: Data, teamId: string, uid: string): Promise<boolean> {
    if (team.orgLinked !== true || typeof team.orgId !== "string" || !validId(team.orgId)) return false;
    const org = await this.store.get(`teams/${team.orgId}`);
    return !!org && can(org, uid, "manageMembers") && Object.hasOwn(mapOf(org.linkedTeams), teamId);
  }

  async roster(caller: Caller, rawTeamId: unknown): Promise<TeamRoster | OutsiderTeamRoster> {
    const teamId = docIdParam(rawTeamId);
    const team = await this.store.get(`teams/${teamId}`);
    if (!team) throw new ApiError("not_found", "That team doesn't exist any more.");
    const tiers = mapOf(team.members);
    const kind = kinds.find((k) => k === team.kind) ?? "team";
    const isMember = Array.isArray(team.memberIds) && team.memberIds.includes(caller.uid);
    if (kind !== "team" && team.requiresApproval === true && !isMember) {
      throw new ApiError("permission_denied", "Only members see who's in this community.");
    }
    // A youth team's roster is its members' (and its school or club's
    // admins'), and so is a team's in a youth division of a league, whatever
    // level the team doc says (drafted before league teams kept "youth").
    if (!isMember && (isYouthTeam(team) || (await this.inYouthLeague(team, teamId)))) {
      if (!(await this.managesOrgOf(team, teamId, caller.uid))) throw new ApiError("permission_denied", youthRosterPrivate);
    }
    // A team whose public page is off (publicPageOn) shows outsiders its card only.
    if (!isMember && !publicPageOn(team) && !(await this.managesOrgOf(team, teamId, caller.uid))) {
      throw new ApiError("permission_denied", teamPagePrivate);
    }

    const players = kind === "team" ? await this.store.list(`teams/${teamId}/roster`, rosterMax) : [];
    const uids = Object.keys(tiers).slice(0, rosterMax);
    const linked = players.map((p) => str(p.data.userId)).filter(Boolean);
    const everyone = [...new Set([...uids, ...linked])];
    // Members, and the admins of the school or club that took a team in, see
    // the roster whole. Anyone else is an outsider (see outsiderView).
    const full = isMember || (await this.managesOrgOf(team, teamId, caller.uid));
    const { cards, hidden } = await this.cards(everyone, mapOf(team.memberNames), full);

    const roleDefs = mapOf(team.roles);
    const roleIds = Object.keys(roleDefs).sort(
      (a, b) => Number(mapOf(roleDefs[a]).position ?? 0) - Number(mapOf(roleDefs[b]).position ?? 0),
    );
    const memberRoles = mapOf(team.memberRoles);

    const members: RosterMember[] = uids
      .map((uid) => {
        const mine = new Set(Array.isArray(memberRoles[uid]) ? (memberRoles[uid] as unknown[]) : []);
        return {
          ...cards.get(uid)!,
          tier: str(tiers[uid]) || "player",
          roles: roleIds.filter((id) => mine.has(id)).map((id) => str(mapOf(roleDefs[id]).name)).filter(Boolean),
        };
      })
      .sort((a, b) => rank(a.tier) - rank(b.tier) || a.name.localeCompare(b.name));

    const sorted = players
      .map(({ id, data }) => player(id, data, cards, hidden))
      // RosterPlayer.compareRoster: by number (none counts as 1000), then name by code units.
      .sort((a, b) => (a.number ?? 1000) - (b.number ?? 1000) || (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
    const teams = kind === "team" ? [] : linkedTeams(team.linkedTeams);
    if (full) return { kind, players: sorted, members, teams };
    return outsiderView(kind, sorted, members, teams, hidden);
  }

  /**
   * An adult team's roster for anyone, signed in or not (the website's
   * visitors): only when the team doc and its directory listing both pass
   * rosterIsPublic, so youth teams, teams without a level and every group
   * answer not_found. Players only, built field by field: the roster's
   * name, number and position, plus a linked public profile's username and
   * picture (a Storage or Google URL only) unless it hides its teams
   * (visibility.teams false, as browse's profileView does). No uids or roster ids, and no
   * members list: who joined, their tiers and roles stay with signed-in
   * members (`GET /v1/teams/:id/roster`). A league's drafted team
   * (`league_…`) and a team in a youth division of a league answer
   * not_found too. A spot linked to a private profile, or one that hides
   * its teams, shows as "Player" with its number and position only.
   */
  async publicRoster(rawTeamId: unknown): Promise<PublicRoster> {
    const hidden = () => new ApiError("not_found", "This team's roster isn't public.");
    if (!validId(rawTeamId) || isDraftedLeagueTeam(rawTeamId)) throw hidden();
    const [team, listing] = await this.store.getAll([`teams/${rawTeamId}`, `teamDirectory/${rawTeamId}`]);
    if (!team || !listing || !rosterIsPublic(team) || !rosterIsPublic(listing)) throw hidden();
    if (await this.inYouthLeague(team, rawTeamId)) throw hidden();
    const players = await this.store.list(`teams/${rawTeamId}/roster`, rosterMax);
    const uids = [...new Set(players.map((p) => str(p.data.userId)).filter(Boolean))];
    const found = await this.store.getAll(uids.map((uid) => `profiles/${uid}`));
    const profiles = new Map(uids.map((uid, i) => [uid, found[i] ?? undefined]));
    const noAdult = this.adults ? await this.adults.hidden(uids) : new Set<string>();
    return {
      players: players
        .map(({ data }) => {
          const linked = str(data.userId);
          const profile = profiles.get(linked);
          // A private profile, or one that hides its teams (or a link to a
          // profile that's gone), isn't named or tied to the roster for visitors.
          // An account D-1317 hides (no adult claim) is private as well.
          const shown = !!profile && !isPrivateProfile(profile) && mapOf(profile.visibility).teams !== false && !noAdult.has(linked);
          const out: PublicRosterPlayer = { name: (linked && !shown ? "" : str(data.name)) || "Player" };
          if (typeof data.number === "number" && Number.isInteger(data.number)) out.number = data.number;
          const pos = positions.find((p) => p === data.position);
          if (pos) out.position = pos;
          if (profile && shown) {
            if (str(profile.username)) out.username = str(profile.username);
            const photo = trustedProfilePhoto(profile.photoUrl, linked);
            if (photo) out.photoUrl = photo;
          }
          return out;
        })
        .sort((a, b) => (a.number ?? 1000) - (b.number ?? 1000) || (a.name < b.name ? -1 : a.name > b.name ? 1 : 0)),
    };
  }

  /**
   * Puts roster spots on the O-line, D-line or both, or takes their line
   * away (null): the roster's "Edit lines". Only for a team (groups keep
   * no roster), by its admins who may change the roster (manageTeam, as
   * the roster rules and roster-players). Every spot named must still be
   * on the roster. The rules keep clients from writing `line` themselves.
   */
  async setLines(caller: Caller, rawTeamId: unknown, body: unknown): Promise<void> {
    const teamId = docIdParam(rawTeamId);
    const { lines } = parseBody(setRosterLinesRequestSchema, body);
    const ids = Object.keys(lines);
    await this.store.transact(async (tx) => {
      const team = await tx.get(`teams/${teamId}`);
      if (!team) throw new ApiError("not_found", "That team doesn't exist any more.");
      if (isGroup(team)) throw new ApiError("failed_precondition", "Only teams have lines.");
      if (!can(team, caller.uid, "manageTeam")) throw new ApiError("permission_denied", "Only the team's admins can change the roster.");
      const spots = await Promise.all(ids.map((id) => tx.get(`teams/${teamId}/roster/${id}`)));
      if (spots.some((s) => !s)) throw new ApiError("not_found", "Someone was taken off the roster. Refresh and try again.");
      for (const id of ids) tx.update(`teams/${teamId}/roster/${id}`, { line: lines[id] ?? deleteField });
    });
  }

  /**
   * Whether [team] plays in a league (leagueId) in a youth division: its
   * entry's division by the league's division summaries, or, without an
   * entry, any youth division of the league (refused to be safe).
   */
  private async inYouthLeague(team: Data, teamId: string): Promise<boolean> {
    const leagueId = team.leagueId;
    if (typeof leagueId !== "string" || !leagueId) return false;
    if (!validId(leagueId)) return true;
    const [league, entry] = await this.store.getAll([`tournaments/${leagueId}`, `tournaments/${leagueId}/entries/${teamId}`]);
    if (!league) return false;
    const divisions = Array.isArray(league.divisions) ? league.divisions.map(mapOf) : [];
    const divisionId = str(entry?.divisionId);
    const mine = divisionId ? divisions.filter((d) => d.id === divisionId) : divisions;
    return mine.some((d) => d.level === "youth");
  }

  /**
   * Each person's public card, from their profile, or the team's copy of their
   * name. For an outsider ([full] false) also who must stay hidden: a private
   * profile, one that hides its teams (visibility.teams false) and an account
   * D-1317 hides, as publicRoster does. A person without a profile is not hidden.
   */
  private async cards(
    uids: string[],
    names: Record<string, unknown>,
    full: boolean,
  ): Promise<{ cards: Map<string, RosterPerson>; hidden: Set<string> }> {
    const profiles = await this.store.getAll(uids.map((uid) => `profiles/${uid}`));
    const noAdult = full || !this.adults ? new Set<string>() : await this.adults.hidden(uids);
    const hidden = new Set<string>();
    const cards = new Map(
      uids.map((uid, i) => {
        const p = profiles[i] ?? {};
        if (!full && (noAdult.has(uid) || (profiles[i] && (isPrivateProfile(p) || mapOf(p.visibility).teams === false)))) hidden.add(uid);
        const card: RosterPerson = { uid, name: str(p.name) || str(names[uid]) || "Member" };
        if (str(p.username)) card.username = str(p.username);
        const photo = trustedProfilePhoto(p.photoUrl, uid);
        if (photo) card.photoUrl = photo;
        if (p.private === true) card.private = true;
        return [uid, card];
      }),
    );
    return { cards, hidden };
  }
}

/**
 * What a signed-in non-member gets (the same hiding publicRoster applies):
 * a hidden person (private profile, teams hidden, no D-1317 adult claim) is
 * left out of `members`, and a spot linked to one shows as "Player" with its
 * number and position only. Everyone else keeps their public card but
 * with no `uid` field, except staff (staffTiers), whose uid the Message sheet
 * needs to open a conversation. A spot's person has no `uid` field. Visible
 * (public) people remain resolvable by username or photo URL (accepted);
 * hidden people are never included.
 */
function outsiderView(
  kind: TeamRoster["kind"],
  players: RosterPlayer[],
  members: RosterMember[],
  teams: RosterTeam[],
  hidden: Set<string>,
): OutsiderTeamRoster {
  const staff = new Set<string>(staffTiers);
  return {
    kind,
    players: players.map((p): OutsiderRosterPlayer => {
      if (!p.person) return p;
      if (hidden.has(p.person.uid)) {
        const { person: _gone, ...rest } = p;
        return rest;
      }
      const { uid: _uid, ...card } = p.person;
      return { ...p, person: card };
    }),
    members: members
      .filter((m) => !hidden.has(m.uid))
      .map((m): OutsiderRosterMember => {
        if (staff.has(m.tier)) return m;
        const { uid: _uid, ...rest } = m;
        return rest;
      }),
    teams,
  };
}

const rank = (tier: string) => {
  const i = tierOrder.indexOf(tier);
  return i < 0 ? tierOrder.length : i;
};

/** A community's teams (linkedTeams: id → {name, division, roles}), without the roles. */
function linkedTeams(raw: unknown): RosterTeam[] {
  return Object.entries(mapOf(raw))
    .map(([id, v]) => {
      const t = mapOf(v);
      const out: RosterTeam = { id, name: str(t.name) || "Team" };
      if (str(t.division)) out.division = str(t.division);
      return out;
    })
    .sort((a, b) => a.name.localeCompare(b.name));
}

function player(id: string, d: Data, cards: Map<string, RosterPerson>, hidden: Set<string>): RosterPlayer {
  // A spot linked to a hidden person isn't named (publicRoster's "Player").
  const out: RosterPlayer = { id, name: (hidden.has(str(d.userId)) ? "" : str(d.name)) || "Player" };
  if (typeof d.number === "number" && Number.isInteger(d.number)) out.number = d.number;
  const pos = positions.find((p) => p === d.position);
  if (pos) out.position = pos;
  const line = rosterLineOf(d.line);
  if (line) out.line = line;
  const person = cards.get(str(d.userId));
  if (person) out.person = person;
  return out;
}
