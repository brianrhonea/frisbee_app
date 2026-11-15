// Team meetings (teams/{id}/meetings, TeamMeeting in the app) and voice
// channels (chat rooms of kind "voice"): who may see and join them, and
// the requests the website sends. The decisions are ported from
// firebase/functions/src/meetings/model.ts (the meetings-joinToken and
// meetings-voiceToken callables), which the app still calls; keep the two
// in step, and in step with the meetings rules in firestore.rules.
import { z } from "zod";
import { isoDateTime } from "./dates.js";
import { audienceTier } from "./membership.js";

// ---- Who may see and join (model.ts) -------------------------------------

export interface MeetingTeam {
  name?: string;
  members?: Record<string, string>;
  memberNames?: Record<string, string>;
  /** uid → permissions from their custom roles (CustomRole in Dart). */
  memberPerms?: Record<string, string[]>;
  deletingAt?: unknown;
}

export interface MeetingDoc {
  title?: string;
  startsAt?: unknown;
  endsAt?: unknown;
  notes?: string;
  inviteRoles?: string[];
  inviteUsers?: string[];
  requireApproval?: boolean;
  status?: string;
  startedAt?: unknown;
  startedBy?: string;
  endedAt?: unknown;
  rsvps?: Record<string, unknown>;
  createdBy?: string;
}

export interface JoinRequestDoc {
  name?: string;
  status?: string;
  requestedAt?: unknown;
}

const adminRoles = new Set(["owner", "coach", "captain"]);
const own = (m: Record<string, unknown> | undefined, key: string): unknown =>
  m && typeof m === "object" && Object.hasOwn(m, key) ? m[key] : undefined;

/** The member's role; a legacy "stats" member is a player (roleOf). */
export function meetingRoleOf(team: MeetingTeam, uid: string): string | undefined {
  const role = own(team.members, uid);
  if (typeof role !== "string") return undefined;
  return audienceTier(role);
}

/**
 * Owners, coaches and captains, and members whose custom roles grant
 * manageEvents, as can(team, 'manageEvents') in firestore.rules (isAdmin).
 */
export function isMeetingAdmin(team: MeetingTeam, uid: string): boolean {
  const role = meetingRoleOf(team, uid);
  if (role === undefined) return false;
  if (adminRoles.has(role)) return true;
  const perms = own(team.memberPerms, uid);
  return Array.isArray(perms) && perms.includes("manageEvents");
}

/** Admins see every meeting; others when invited by role or by name (canSee). */
export function canSeeMeeting(team: MeetingTeam, meeting: MeetingDoc, uid: string): boolean {
  const role = meetingRoleOf(team, uid);
  if (role === undefined) return false;
  return isMeetingAdmin(team, uid) || (meeting.inviteRoles ?? []).includes(role) || (meeting.inviteUsers ?? []).includes(uid);
}

/** Team members who can see [meeting] (invitees). */
export function meetingInvitees(team: MeetingTeam, meeting: MeetingDoc): string[] {
  return Object.keys(team.members ?? {}).filter((uid) => canSeeMeeting(team, meeting, uid));
}

export type MeetingJoinDecision = "ok" | "notMember" | "notInvited" | "missing" | "notStarted" | "ended" | "needsApproval";

/** Whether [uid] may get a token for the meeting's call right now (joinDecision). */
export function meetingJoinDecision(a: {
  team?: MeetingTeam;
  meeting?: MeetingDoc;
  request?: JoinRequestDoc;
  uid: string;
}): MeetingJoinDecision {
  const { team, meeting, request, uid } = a;
  if (!team || team.deletingAt || meetingRoleOf(team, uid) === undefined) return "notMember";
  if (!meeting) return "missing";
  if (!canSeeMeeting(team, meeting, uid)) return "notInvited";
  if (meeting.status === "ended") return "ended";
  if (meeting.status !== "live") return "notStarted";
  if (meeting.requireApproval === true && !isMeetingAdmin(team, uid) && request?.status !== "admitted") {
    return "needsApproval";
  }
  return "ok";
}

export const meetingJoinMessages: Record<Exclude<MeetingJoinDecision, "ok">, string> = {
  notMember: "You're not on this team.",
  notInvited: "You weren't invited to this meeting.",
  missing: "This meeting no longer exists.",
  notStarted: "The meeting hasn't started yet.",
  ended: "This meeting has ended.",
  needsApproval: "An admin needs to let you in first.",
};

/** The LiveKit room for a meeting (roomName). */
export const meetingRoomName = (teamId: string, meetingId: string) => `${teamId}_${meetingId}`;

/** What the call shows for [uid]: their team name, else their profile name (displayName). */
export function meetingDisplayName(team: MeetingTeam, uid: string, profileName?: unknown): string {
  const teamName = own(team.memberNames, uid);
  const name = typeof teamName === "string" ? teamName : typeof profileName === "string" ? profileName : "";
  return name.trim() || "Member";
}

// ---- Voice channels --------------------------------------------------------

/** A chat room (ChatRoom in lib/domain/models/chat.dart). */
export interface VoiceRoomDoc {
  kind?: string;
  name?: string;
  readRoles?: string[];
  writeRoles?: string[];
  readUsers?: string[];
  writeUsers?: string[];
}

export interface VoiceTeam extends MeetingTeam {
  /** uid → custom role ids. */
  memberRoles?: Record<string, string[]>;
}

/**
 * Whether [uid] is in a room audience, as inAudience in model.ts:
 * "everyone", their tier (a legacy "stats" member is a player), one of
 * their custom roles, or by name. The owner is in every room.
 */
export function voiceInAudience(team: VoiceTeam, uid: string, ids: string[] = [], users: string[] = []): boolean {
  const role = meetingRoleOf(team, uid);
  if (role === undefined) return false;
  if (role === "owner") return true;
  const mineRaw = own(team.memberRoles, uid);
  const mine = Array.isArray(mineRaw) ? (mineRaw as string[]) : [];
  return ids.includes("everyone") || ids.includes(role) || mine.some((r) => ids.includes(r)) || users.includes(uid);
}

export type VoiceDecision =
  | { ok: true; canSpeak: boolean }
  | { ok: false; code: "permission-denied" | "not-found" | "failed-precondition"; message: string };

/**
 * Whether [uid] may join a voice channel: members who can read the room
 * listen, and those who can write in it talk too (voiceDecision).
 */
export function voiceDecision(team: VoiceTeam | undefined, room: VoiceRoomDoc | undefined, uid: string): VoiceDecision {
  if (!team || team.deletingAt || meetingRoleOf(team, uid) === undefined) {
    return { ok: false, code: "permission-denied", message: "You're not on this team." };
  }
  if (!room) return { ok: false, code: "not-found", message: "This channel no longer exists." };
  if (room.kind !== "voice") {
    return { ok: false, code: "failed-precondition", message: "That's not a voice channel." };
  }
  if (!voiceInAudience(team, uid, room.readRoles, room.readUsers)) {
    return { ok: false, code: "permission-denied", message: "You don't have access to this channel." };
  }
  return { ok: true, canSpeak: voiceInAudience(team, uid, room.writeRoles, room.writeUsers) };
}

/** The LiveKit room for a voice channel; can't clash with a meeting's. */
export const voiceRoomName = (teamId: string, roomId: string) => `voice:${teamId}:${roomId}`;

/** The callables' id check (validId): a stricter docIdParam. */
export const validMeetingId = (v: unknown): v is string => typeof v === "string" && /^[A-Za-z0-9_-]{1,128}$/.test(v);

// ---- Requests ---------------------------------------------------------------

/** validMeeting's limits, and TeamMeeting.maxInviteUsers. */
export const meetingLimits = { title: 100, notes: 5000, inviteUsers: 200, name: 80, message: 4000 } as const;

/** Tiers a meeting can invite (validMeeting's roles). Admins always see it. */
export const meetingInviteRoles = ["owner", "coach", "captain", "player"] as const;
export const meetingStatuses = ["scheduled", "live", "ended"] as const;
export type MeetingStatus = (typeof meetingStatuses)[number];
export const meetingRsvps = ["attending", "notAttending"] as const;
export type MeetingRsvp = (typeof meetingRsvps)[number];
export const meetingRsvpLabels: Record<MeetingRsvp, string> = { attending: "Attending", notAttending: "Not attending" };

const isoDate = isoDateTime("Give a date and time.");

/**
 * `POST /v1/teams/:teamId/meetings` and `PATCH .../meetings/:meetingId`
 * (validMeeting; the fields TeamMeeting.toEditableMap writes).
 */
export const saveMeetingRequestSchema = z
  .strictObject({
    title: z.string().trim().min(1, "Give it a title.").max(meetingLimits.title, "Keep the title under 100 characters."),
    startsAt: isoDate,
    endsAt: isoDate.nullable().default(null),
    notes: z.string().max(meetingLimits.notes, "Keep notes under 5,000 characters.").default(""),
    inviteRoles: z.array(z.enum(meetingInviteRoles)).max(meetingInviteRoles.length).default([]),
    inviteUsers: z
      .array(z.string().min(1).max(128))
      .max(meetingLimits.inviteUsers, `Invite at most ${meetingLimits.inviteUsers} people.`)
      .default([]),
    requireApproval: z.boolean().default(false),
  })
  .refine((m) => !m.endsAt || Date.parse(m.endsAt) >= Date.parse(m.startsAt), {
    message: "It can't end before it starts.",
    path: ["endsAt"],
  });
export type SaveMeetingRequest = z.input<typeof saveMeetingRequestSchema>;

/** `PUT .../meetings/:meetingId/rsvp`: null takes the answer back (respond). */
export const meetingRsvpRequestSchema = z.strictObject({ answer: z.enum(meetingRsvps).nullable() });

/** `PUT .../meetings/:meetingId/requests/:userId/decision`: an admin lets them in or turns them away. */
export const meetingJoinDecisionRequestSchema = z.strictObject({ admit: z.boolean() });

/**
 * `PUT .../meetings/:meetingId/playback` (validPlayback): the presenter's
 * state; the API adds who's presenting and the server time.
 */
export const meetingPlaybackRequestSchema = z.strictObject({
  videoId: z.string().min(1).max(128),
  playing: z.boolean(),
  positionMs: z.number().int().min(0).max(Number.MAX_SAFE_INTEGER),
});
export type MeetingPlaybackRequest = z.input<typeof meetingPlaybackRequestSchema>;

/** `POST .../meetings/:meetingId/messages`: the call's chat, text only. */
export const meetingMessageRequestSchema = z.strictObject({
  text: z.string().trim().min(1, "Write a message.").max(meetingLimits.message, "Keep messages under 4,000 characters."),
});

export interface SaveMeetingResult {
  id: string;
}

/** `POST .../meetings/:meetingId/token`: where the call is and how to get in. */
export interface MeetingTokenResult {
  url: string;
  token: string;
}

/** `POST .../voice-rooms/:roomId/token`; listeners can't publish. */
export interface VoiceTokenResult extends MeetingTokenResult {
  canSpeak: boolean;
}

// ---- Watch together (MeetingPlayback in the app) -----------------------------

/** `teams/{teamId}/meetings/{meetingId}/playback/current`, as read (timestamps as ISO strings). */
export interface MeetingPlaybackDoc {
  videoId?: string;
  playing?: boolean;
  positionMs?: number;
  presenterId?: string;
  presenterName?: string;
  updatedAt?: string | null;
}

/** WatchTogetherViewModel's sync: a tick a second, a seek past this, a presenter heartbeat. */
export const watchTogether = { tickMs: 1000, toleranceMs: 1500, heartbeatMs: 10_000 } as const;

/**
 * Where the video should be at [nowMs] (MeetingPlayback.positionAt): the
 * position, plus the time since updatedAt while it plays. A pending write
 * (no updatedAt yet) or a clock behind the server's counts as no time.
 */
export function playbackPositionAt(p: MeetingPlaybackDoc, nowMs: number): number {
  const position = p.positionMs ?? 0;
  if (!p.playing) return position;
  const at = p.updatedAt ? Date.parse(p.updatedAt) : Number.NaN;
  const since = Number.isNaN(at) ? 0 : nowMs - at;
  return since < 0 ? position : position + since;
}
