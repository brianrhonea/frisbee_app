"use client";
import { type OptionalTeamSection, sectionOn, type TeamPermission } from "@stall10/shared";
import { createContext, type ReactNode, useContext } from "react";
import { type Doc, useLiveDoc } from "@/lib/live";
import { useAuth } from "../AuthProvider";

/** One custom role in the team doc's `roles` map (CustomRole in the app). */
export interface CustomRoleDoc {
  name: string;
  color?: number;
  position?: number;
  perms?: TeamPermission[];
}

/** The team's custom roles in the app's order (by position), with their ids. */
export function rolesInOrder(roles: Record<string, CustomRoleDoc> | undefined): Array<CustomRoleDoc & { id: string }> {
  return Object.entries(roles ?? {})
    .filter(([, r]) => r && typeof r === "object" && typeof r.name === "string")
    .map(([id, r]) => ({ ...r, id }))
    .sort((a, b) => (a.position ?? 0) - (b.position ?? 0));
}

/** The team doc's fields the hub uses (Team.fromMap in the app). */
export interface TeamDoc {
  roles?: Record<string, CustomRoleDoc>;
  /** A community's teams (LinkedTeam): their name, division and the roles that join them. */
  linkedTeams?: Record<string, { name?: string; division?: string; roles?: string[] }>;
  orgId?: string | null;
  orgName?: string;
  orgLinked?: boolean;
  name?: string;
  kind?: "team" | "community" | "organization";
  ownerId?: string;
  memberIds?: string[];
  members?: Record<string, string>;
  memberNames?: Record<string, string>;
  memberRoles?: Record<string, string[]>;
  memberPerms?: Record<string, TeamPermission[]>;
  /** Each member's own permissions (the owner's per-person switches, F25); memberPerms counts them. API-written. */
  memberGrants?: Record<string, TeamPermission[]>;
  statKeepers?: string[];
  requiresApproval?: boolean;
  location?: { address?: string } | null;
  /** When the team was made (an ISO time, as live reads give them): the header's "Est. 2019". */
  createdAt?: string;
  /**
   * Its optional sections (Settings › Sections), each on or off; a missing
   * map or key is on (sectionOn in packages/shared). New teams store all off.
   */
  sections?: Partial<Record<OptionalTeamSection, boolean>>;
  /** The league a league team was started for (Team.isLeagueTeam in the app). */
  leagueId?: string | null;
  /** The "Public team page" switch: false when outsiders see its card only (publicPageOn in packages/shared). */
  publicPage?: boolean;
  /** "Allow join requests" (F26, teams only): true when signed-in outsiders may ask to join. API-written. */
  allowJoinRequests?: boolean;
}

/**
 * Whether the hub shows [section] to [viewer]: off only for a member of a
 * team whose owner turned it off. Groups store no sections, so always on.
 */
export function viewerSectionOn(viewer: TeamViewer, section: OptionalTeamSection): boolean {
  return viewer.state !== "member" || sectionOn(viewer.team, section);
}

/**
 * Who the viewer is on this team: still loading, a signed-out visitor,
 * signed in but not a member (the rules refuse the team doc), a team doc
 * that couldn't be read for another reason (not treated as an outsider, so
 * a member isn't offered "Join"), or a member with the team doc live.
 */
export type TeamViewer =
  | { state: "loading" }
  | { state: "visitor" }
  | { state: "outsider"; uid: string }
  | { state: "error"; uid: string; message: string }
  | { state: "member"; uid: string; team: Doc<TeamDoc>; tier: string; can: (p: TeamPermission) => boolean; audience: string[] };

interface TeamHubInfo {
  teamId: string;
  name: string;
  kind: "team" | "community" | "organization";
  /** A community or organization that approves joins: only members see inside. */
  privateGroup: boolean;
  /** A team whose "Public team page" is off (its listing's publicPage): only members see inside, as a private group. */
  privatePage: boolean;
  /** A team that takes join requests (its listing's allowJoinRequests, F26): signed-in outsiders get "Ask to join". */
  joinRequests?: boolean;
  /** A youth team (isYouthTeam): visitors see its card only, and only members its roster. */
  youth: boolean;
  /** Visitors may see the roster (rosterIsPublic: an adult team's), without links to profiles. */
  publicRoster: boolean;
  viewer: TeamViewer;
}

const TeamContext = createContext<TeamHubInfo | null>(null);

const editors = ["owner", "coach", "captain"];

/**
 * The member [uid] of [team] as the hub and the schedule see them: their
 * tier, what they may do, and the audience ids events and rooms list.
 */
export function memberViewer(team: Doc<TeamDoc>, uid: string): Extract<TeamViewer, { state: "member" }> {
  const tier = team.members?.[uid] ?? "player";
  const perms = team.memberPerms?.[uid] ?? [];
  return {
    state: "member",
    uid,
    team,
    tier,
    can: (p) => editors.includes(tier) || perms.includes(p),
    // Chat rooms and a community's events say who sees them by these ids
    // (ChatAudience in the app): everyone, the tier (a legacy stats member
    // is a player) and each custom role.
    audience: ["everyone", tier === "stats" ? "player" : tier, ...(team.memberRoles?.[uid] ?? [])],
  };
}

/** Listens to the team doc once for every section of the hub. */
export function TeamProvider({
  teamId,
  name,
  kind,
  privateGroup,
  privatePage,
  joinRequests = false,
  youth,
  publicRoster,
  children,
}: Omit<TeamHubInfo, "viewer"> & { children: ReactNode }) {
  const { user } = useAuth();
  const live = useLiveDoc<TeamDoc>(user ? `teams/${teamId}` : null);

  let viewer: TeamViewer;
  if (user === undefined) viewer = { state: "loading" };
  else if (!user) viewer = { state: "visitor" };
  else if (live.error && live.denied) viewer = { state: "outsider", uid: user.uid };
  else if (live.error) viewer = { state: "error", uid: user.uid, message: live.error };
  else if (live.data === undefined) viewer = { state: "loading" };
  else if (!live.data || !live.data.memberIds?.includes(user.uid)) viewer = { state: "outsider", uid: user.uid };
  else viewer = memberViewer(live.data, user.uid);
  // Members see their team as it is: the public page hides a drafted
  // league team's name (its players') from everyone else.
  const shownName = viewer.state === "member" ? viewer.team.name || name : name;
  return (
    <TeamContext.Provider value={{ teamId, name: shownName, kind, privateGroup, privatePage, joinRequests, youth, publicRoster, viewer }}>
      {children}
    </TeamContext.Provider>
  );
}

export function useTeamHub(): TeamHubInfo {
  const info = useContext(TeamContext);
  if (!info) throw new Error("useTeamHub outside TeamProvider");
  return info;
}

/** What a member is asked before leaving (Settings › Leave and the team page's More menu). */
export const LEAVE_CONFIRM = { title: "Leave this team?", message: "You'll need a new invite to come back.", confirmLabel: "Leave team" };
