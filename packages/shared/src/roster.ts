// `GET /v1/teams/:teamId/roster`: who's on a team, for any signed-in
// member of Stall 10 (not only the team's). Players come from the team's
// `roster/*`; members from the team doc's `members` and `memberNames`,
// with each one's public profile card. A private group's (a community or
// organization with requiresApproval) roster stays with its members, as
// its posts do.

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

export interface TeamRoster {
  kind: "team" | "community" | "organization";
  /** Empty for a community or organization: they keep no roster. */
  players: RosterPlayer[];
  members: RosterMember[];
}

/** Most players and members the roster lists. */
export const rosterMax = 500;
