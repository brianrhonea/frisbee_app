import { type RosterMember, type RosterPerson, type RosterPlayer, rosterMax, type TeamRoster } from "@stall10/shared";
import type { Caller } from "../auth.js";
import { ApiError } from "../errors.js";
import { docIdParam } from "../ids.js";
import type { Data, DocStore } from "../store.js";

const positions = ["handler", "cutter", "hybrid"] as const;
const kinds = ["team", "community", "organization"] as const;
/** Tiers first by rank, then everyone else by name (the app's roster order). */
const tierOrder = ["owner", "coach", "captain", "stats", "player"];

const str = (v: unknown) => (typeof v === "string" ? v : "");
const asMap = (v: unknown) => (v && typeof v === "object" && !Array.isArray(v) ? (v as Record<string, unknown>) : {});

/**
 * Who's on a team, for anyone signed in: the roster's players and the
 * members, each with their public profile card. The rules keep `roster/*`
 * and the team doc to members, so this reads them with the Admin SDK and
 * returns only names, numbers, positions, tiers and role names, never
 * permissions, stats keepers, paid marks or anything else on the team doc.
 * A private group (a community or organization that approves joins) shows
 * its members only to members, as its posts and events are (showsPublic
 * and isPrivateGroup in the rules).
 */
export class RosterService {
  constructor(private readonly store: DocStore) {}

  async roster(caller: Caller, rawTeamId: unknown): Promise<TeamRoster> {
    const teamId = docIdParam(rawTeamId);
    const team = await this.store.get(`teams/${teamId}`);
    if (!team) throw new ApiError("not_found", "That team doesn't exist any more.");
    const tiers = asMap(team.members);
    const kind = kinds.find((k) => k === team.kind) ?? "team";
    const isMember = Array.isArray(team.memberIds) && team.memberIds.includes(caller.uid);
    if (kind !== "team" && team.requiresApproval === true && !isMember) {
      throw new ApiError("permission_denied", "Only members see who's in this group.");
    }

    const players = kind === "team" ? await this.store.list(`teams/${teamId}/roster`, rosterMax) : [];
    const uids = Object.keys(tiers).slice(0, rosterMax);
    const linked = players.map((p) => str(p.data.userId)).filter(Boolean);
    const cards = await this.cards([...new Set([...uids, ...linked])], asMap(team.memberNames));

    const roleDefs = asMap(team.roles);
    const roleIds = Object.keys(roleDefs).sort(
      (a, b) => Number(asMap(roleDefs[a]).position ?? 0) - Number(asMap(roleDefs[b]).position ?? 0),
    );
    const memberRoles = asMap(team.memberRoles);

    const members: RosterMember[] = uids
      .map((uid) => {
        const mine = new Set(Array.isArray(memberRoles[uid]) ? (memberRoles[uid] as unknown[]) : []);
        return {
          ...cards.get(uid)!,
          tier: str(tiers[uid]) || "player",
          roles: roleIds.filter((id) => mine.has(id)).map((id) => str(asMap(roleDefs[id]).name)).filter(Boolean),
        };
      })
      .sort((a, b) => rank(a.tier) - rank(b.tier) || a.name.localeCompare(b.name));

    return {
      kind,
      players: players
        .map(({ id, data }) => player(id, data, cards))
        .sort((a, b) => (a.number ?? 1e9) - (b.number ?? 1e9) || a.name.localeCompare(b.name)),
      members,
    };
  }

  /** Each person's public card, from their profile, or the team's copy of their name. */
  private async cards(uids: string[], names: Record<string, unknown>): Promise<Map<string, RosterPerson>> {
    const profiles = await Promise.all(uids.map((uid) => this.store.get(`profiles/${uid}`)));
    return new Map(
      uids.map((uid, i) => {
        const p = profiles[i] ?? {};
        const card: RosterPerson = { uid, name: str(p.name) || str(names[uid]) || "Member" };
        if (str(p.username)) card.username = str(p.username);
        if (str(p.photoUrl)) card.photoUrl = str(p.photoUrl);
        if (p.private === true) card.private = true;
        return [uid, card];
      }),
    );
  }
}

const rank = (tier: string) => {
  const i = tierOrder.indexOf(tier);
  return i < 0 ? tierOrder.length : i;
};

function player(id: string, d: Data, cards: Map<string, RosterPerson>): RosterPlayer {
  const out: RosterPlayer = { id, name: str(d.name) || "Player" };
  if (typeof d.number === "number" && Number.isInteger(d.number)) out.number = d.number;
  const pos = positions.find((p) => p === d.position);
  if (pos) out.position = pos;
  const person = cards.get(str(d.userId));
  if (person) out.person = person;
  return out;
}
