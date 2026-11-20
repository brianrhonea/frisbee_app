// The team page's quick stat tiles and its More list's subtitles, worded
// the same on the app (team_page.dart) and the website.

import { presetMatching, type TeamPermission } from "./membership.js";
import type { InboxRoom, TeamChatSummary } from "./team_chats.js";

/** How many answered Going in an event's `rsvps` (uid → answer). */
export function goingCount(rsvps: Record<string, unknown> | null | undefined): number {
  return Object.values(rsvps ?? {}).filter((a) => a === "going").length;
}

/**
 * The chat tile ("N new in chat") counts the team's rooms with messages
 * the member hasn't read (teamChatSummary's unread), not messages, which
 * would cost a read each. This is its longer description (tooltip, screen
 * readers).
 */
export function newInChatDescription(rooms: number): string {
  return rooms === 0 ? "No new messages" : `${rooms} ${rooms === 1 ? "room has" : "rooms have"} new messages`;
}

/** The sections More can list (HubSection subs on the website, TeamSection in the app). */
export type TeamMoreRow = "playbook" | "videos" | "stats" | "tournaments" | "meetings" | "manage";

/** One line under each row of More: what's there (a count would cost a read per row). */
export const teamMoreSubtitles: Record<TeamMoreRow, string> = {
  playbook: "Plays and whiteboards",
  videos: "Game film and highlights",
  stats: "Games, lines and player stats",
  tournaments: "Events your team has entered",
  meetings: "Video calls with the team",
  manage: "Details, sections and visibility",
};

/** The More row that opens Settings, for admins. */
export const manageRowLabel = (kind: string): string => (kind === "team" ? "Manage team" : "Manage group");

// The community page (redesign F27): its chat and organizers sections.

/** Rooms the community page's chat section lists before "All chat". */
export const chatSectionMax = 5;

/**
 * The chat section's rooms from the member's [summary] (teamChatSummary):
 * unread ones first (newest first), each marked, then the rest in the
 * team's order, up to [max]; [more] is how many are left for the chat page.
 */
export function chatSectionRooms<R extends InboxRoom>(
  summary: Pick<TeamChatSummary<R>, "rooms" | "unread">,
  max: number = chatSectionMax,
): { rooms: Array<{ room: R; unread: boolean }>; more: number } {
  const unread = new Set(summary.unread.map((r) => r.id));
  const all = [
    ...summary.unread.map((room) => ({ room, unread: true })),
    ...summary.rooms.filter((r) => !unread.has(r.id)).map((room) => ({ room, unread: false })),
  ];
  return { rooms: all.slice(0, max), more: Math.max(0, all.length - max) };
}

/**
 * Permissions that make a member one of a community's organizers: running
 * it, its members or its events. Chat moderators alone aren't listed.
 */
export const organizerPermissions: readonly TeamPermission[] = ["manageTeam", "manageMembers", "manageEvents"];

/** One person in the community page's Organizers section. */
export interface CommunityOrganizer {
  uid: string;
  name: string;
  /** "Owner", the legacy tier ("Organizer" for a captain, "Coach"), or the preset their permissions match ("Admin", "Organizer"), else "Organizer". */
  label: string;
}

/** The team doc's fields [communityOrganizers] reads. */
export interface OrganizerSource {
  members?: Record<string, string>;
  memberNames?: Record<string, string>;
  /** What each member may do: their roles' permissions and their own (F25). */
  memberPerms?: Record<string, readonly string[]>;
}

/**
 * A community's organizers (the app's communityOrganizers): the owner,
 * then everyone else who can run it (a coach or captain tier, or
 * [organizerPermissions] from their roles or their own switches), by name.
 */
export function communityOrganizers(team: OrganizerSource): CommunityOrganizer[] {
  const out: Array<CommunityOrganizer & { owner: boolean }> = [];
  for (const [uid, tier] of Object.entries(team.members ?? {})) {
    const name = team.memberNames?.[uid] || "Member";
    if (tier === "owner") {
      out.push({ uid, name, label: "Owner", owner: true });
    } else if (tier === "coach" || tier === "captain") {
      out.push({ uid, name, label: tier === "captain" ? "Organizer" : "Coach", owner: false });
    } else {
      const perms = team.memberPerms?.[uid] ?? [];
      if (!perms.some((p) => (organizerPermissions as readonly string[]).includes(p))) continue;
      out.push({ uid, name, label: presetMatching(perms, true)?.name ?? "Organizer", owner: false });
    }
  }
  const cmp = (a: string, b: string) => (a < b ? -1 : a > b ? 1 : 0);
  out.sort((a, b) => Number(b.owner) - Number(a.owner) || cmp(a.name, b.name) || cmp(a.uid, b.uid));
  return out.map((o) => ({ uid: o.uid, name: o.name, label: o.label }));
}

/**
 * The community page's next-event card (F27): its title and what it says
 * when nothing's ahead. A pickup community's events are pickups; a school
 * or club's are anything.
 */
export function nextEventCardText(kind: string): { title: string; empty: string } {
  return kind === "organization"
    ? { title: "Next event", empty: "No events scheduled" }
    : { title: "Next pickup", empty: "No pickup scheduled" };
}
