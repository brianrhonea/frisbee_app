// `GET /v1/teams/:teamId/roster`: who's on a team, for any signed-in
// member of Stall 10 (not only the team's). Players come from the team's
// `roster/*`; members from the team doc's `members` and `memberNames`,
// with each one's public profile card. A private group's (a community or
// organization with requiresApproval) roster stays with its members, as
// its posts do.
import { z } from "zod";

/** A person's public card: what their profile shows anyone signed in. */
export interface RosterPerson {
  uid: string;
  name: string;
  username?: string;
  photoUrl?: string;
  /** A private profile: the card links to a page that asks to follow. */
  private?: boolean;
}

/** A player on the roster (RosterPlayer in the app). */
export interface RosterPlayer {
  id: string;
  name: string;
  number?: number;
  position?: "handler" | "cutter" | "hybrid";
  /** Which line they play on (O, D or both); none while unassigned. */
  line?: RosterLine;
  /** The member this player is linked to, if any. */
  person?: RosterPerson;
}

/** A member of the team or group. */
export interface RosterMember extends RosterPerson {
  /** Their tier: owner, coach, captain, stats or player. */
  tier: string;
  /** Their custom roles' names, in the team's order. */
  roles: string[];
}

/**
 * Who a team's Message sheet lists: the tiers a non-member may direct-message.
 * The roster route gives a non-member a `uid` for these members only.
 */
export const staffTiers = ["owner", "coach", "captain"] as const;

/**
 * What `GET /v1/teams/:id/roster` returns a signed-in NON-member (and what
 * members still get, in full, as TeamRoster): the same shape with no `uid`
 * field except on staff (staffTiers) who show their teams, adults and public
 * profile; hidden people are never included (left out of `members`, and a
 * spot linked to one is a bare "Player" with no `person`). A spot's `person`
 * has no `uid` field. Visible (public) people remain resolvable by username
 * or photo URL, which is accepted: their profiles are already public.
 */
export type OutsiderRosterPerson = Omit<RosterPerson, "uid"> & { uid?: string };
export interface OutsiderRosterPlayer extends Omit<RosterPlayer, "person"> {
  person?: OutsiderRosterPerson;
}
export interface OutsiderRosterMember extends OutsiderRosterPerson {
  tier: string;
  roles: string[];
}
export interface OutsiderTeamRoster {
  kind: TeamRoster["kind"];
  players: OutsiderRosterPlayer[];
  members: OutsiderRosterMember[];
  teams: RosterTeam[];
}

/** A team a community lists (its `linkedTeams`). */
export interface RosterTeam {
  id: string;
  name: string;
  division?: string;
}

export interface TeamRoster {
  kind: "team" | "community" | "organization";
  /** Empty for a community or organization: they keep no roster. */
  players: RosterPlayer[];
  members: RosterMember[];
  /** A community's teams, by name; empty for a team. */
  teams: RosterTeam[];
}

/** Most players and members the roster lists. */
export const rosterMax = 500;

// ---- Lines (O-line / D-line) ------------------------------------------------
//
// A roster spot's `line` (teams/{id}/roster/{playerId}.line): which line the
// player is on, set by the team's admins (manageTeam) through
// `PUT /v1/teams/:teamId/roster-lines`; clients can't write it themselves
// (firestore.rules). Not a position (handler, cutter, hybrid), and not a
// stats game's lines (StatsLine), which are per game.

/** O-line, D-line, or both; a spot without one is unassigned. */
export const rosterLines = ["o", "d", "both"] as const;
export type RosterLine = (typeof rosterLines)[number];

/** The headings the roster groups players under (RosterLine.label in the app). */
export const rosterLineLabels: Record<RosterLine, string> = { o: "O-line", d: "D-line", both: "Both lines" };
/** The heading for players without a line. */
export const unassignedLineLabel = "Unassigned";

/** [raw] as a line, or undefined for anything else (missing, null, unknown). */
export function rosterLineOf(raw: unknown): RosterLine | undefined {
  return rosterLines.find((l) => l === raw);
}

/**
 * The roster grouped by line, in the order O-line, D-line, Both lines,
 * Unassigned, each keeping [players]' order and leaving out empty groups.
 * Empty when no one has a line yet, so the roster shows as one list.
 */
export function groupByLine<P extends { line?: RosterLine | null }>(players: P[]): Array<{ line: RosterLine | null; players: P[] }> {
  if (!players.some((p) => rosterLineOf(p.line))) return [];
  return [...rosterLines, null]
    .map((line) => ({ line, players: players.filter((p) => (rosterLineOf(p.line) ?? null) === line) }))
    .filter((g) => g.players.length > 0);
}

const docId = z.string().regex(/^[A-Za-z0-9_-]{1,128}$/);

/**
 * `PUT /v1/teams/:teamId/roster-lines`: lines to set, by roster spot id;
 * null takes a spot's line away. Spots left out keep theirs.
 */
export const setRosterLinesRequestSchema = z.strictObject({
  lines: z
    .record(docId, z.enum(rosterLines).nullable())
    .refine((m) => Object.keys(m).length > 0, "Pick a line for someone.")
    .refine((m) => Object.keys(m).length <= rosterMax, `At most ${rosterMax} players at a time.`),
});
export type SetRosterLinesRequest = z.input<typeof setRosterLinesRequestSchema>;

// ---- Invites pending ---------------------------------------------------------

/**
 * Someone invited to the team who hasn't answered yet
 * (users/{uid}/teamInvites/{teamId}), as `GET /v1/teams/:teamId/invites`
 * lists them for whoever may invite: their public card, who invited them
 * and when.
 */
export interface PendingInvite extends RosterPerson {
  invitedByName?: string;
  /** ISO 8601. */
  invitedAt?: string;
}

export interface PendingInvites {
  invites: PendingInvite[];
}

/** Most pending invites the roster lists. */
export const pendingInvitesMax = 100;
