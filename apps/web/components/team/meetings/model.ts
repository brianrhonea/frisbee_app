"use client";
import type { MeetingRsvp, MeetingStatus } from "@stall10/shared";
import { limit, orderBy, type QueryConstraint, where } from "firebase/firestore";
import { type Doc, useLiveQueries } from "@/lib/live";
import type { TeamViewer } from "../TeamContext";

/** A meeting as members read it (TeamMeeting.fromMap). */
export interface MeetingData {
  title?: string;
  startsAt?: string;
  endsAt?: string | null;
  notes?: string;
  inviteRoles?: string[];
  inviteUsers?: string[];
  requireApproval?: boolean;
  status?: MeetingStatus;
  startedAt?: string;
  startedBy?: string;
  endedAt?: string;
  rsvps?: Record<string, MeetingRsvp>;
  createdBy?: string;
}
export type Meeting = Doc<MeetingData>;

/** A join request (JoinRequest): keyed by the asker's uid. */
export interface JoinRequestData {
  name?: string;
  status?: "pending" | "admitted" | "denied";
  requestedAt?: string;
}

export const teamBase = (teamId: string) => `/teams/${encodeURIComponent(teamId)}`;
export const meetingsHref = (teamId: string) => `${teamBase(teamId)}/meetings`;
export const meetingHref = (teamId: string, id: string) => `${meetingsHref(teamId)}/${encodeURIComponent(id)}`;
export const roomHref = (teamId: string, id: string) => `${meetingHref(teamId, id)}/room`;
export const meetingsApi = (teamId: string) => `/v1/teams/${encodeURIComponent(teamId)}/meetings`;
export const meetingApi = (teamId: string, id: string) => `${meetingsApi(teamId)}/${encodeURIComponent(id)}`;

const editors = ["owner", "coach", "captain"];

/** The viewer's tier as meetings invite it: a legacy stats member is a player (chatRole). */
export const inviteTier = (tier: string) => (tier === "stats" ? "player" : tier);

/** Whether the member sees [m] (TeamMeeting.canSee): admins all, others by tier or by name. */
export function canSee(m: MeetingData, viewer: Extract<TeamViewer, { state: "member" }>): boolean {
  return viewer.can("manageEvents") || (m.inviteRoles ?? []).includes(inviteTier(viewer.tier)) || (m.inviteUsers ?? []).includes(viewer.uid);
}

/** Who's invited, in a line (TeamMeeting.audience). */
export function audienceLine(m: MeetingData): string {
  if ((m.inviteRoles ?? []).includes("player")) return "Everyone";
  const people = (m.inviteUsers ?? []).length;
  return ["Admins", ...(people > 0 ? [`${people} ${people === 1 ? "person" : "people"}`] : [])].join(" + ");
}

/** Whether the member waits for an admin (TeamMeeting.needsApproval). */
export const needsApproval = (m: MeetingData, admin: boolean) => m.requireApproval === true && !admin;

const byStart = (a: Meeting, b: Meeting) => (a.startsAt ?? "").localeCompare(b.startsAt ?? "");

/** How many meetings a team's lists read. */
const meetingCap = 200;

/**
 * The Firestore reads for the meetings a member can see (watchMeetings):
 * admins read them all; others ask by their tier and by their uid, as the
 * rules require. [key] names the set for useLiveQueries. Shared with My
 * schedule. Bounded: admins read the [meetingCap] made most recently; an
 * invitee's reads (no index to order them) stop at [meetingCap] each.
 */
export function teamMeetingQueries(member: Extract<TeamViewer, { state: "member" }>) {
  const admin = member.can("manageEvents");
  const queries: QueryConstraint[][] = admin
    ? [[orderBy("createdAt", "desc"), limit(meetingCap)]]
    : [
        [where("inviteRoles", "array-contains", inviteTier(member.tier)), limit(meetingCap)],
        [where("inviteUsers", "array-contains", member.uid), limit(meetingCap)],
      ];
  return { queries, key: admin ? "all" : `${member.tier}|${member.uid}` };
}

/** The team's meetings the member can see, soonest first, live, merged. */
export function useTeamMeetings(teamId: string, viewer: TeamViewer) {
  const member = viewer.state === "member" ? viewer : null;
  const { queries, key } = member ? teamMeetingQueries(member) : { queries: [], key: "" };
  const live = useLiveQueries<MeetingData>(member ? `teams/${teamId}/meetings` : null, queries, key);
  return { ...live, data: live.data?.slice().sort(byStart) };
}

/** When a meeting is: start, and end if it has one. */
export function whenLine(m: MeetingData): string {
  if (!m.startsAt) return "";
  const start = new Date(m.startsAt);
  const day = start.toLocaleDateString(undefined, { weekday: "short", month: "short", day: "numeric", year: "numeric" });
  const time = (d: Date) => d.toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" });
  const end = m.endsAt ? new Date(m.endsAt) : null;
  return `${day} · ${time(start)}${end ? `–${time(end)}` : ""}`;
}

export const isEditorTier = (tier: string) => editors.includes(tier);
