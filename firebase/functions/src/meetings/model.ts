// Pure meeting logic: who may see and join a meeting, and who hears about
// it. No Firebase calls here, so it's unit-tested in test/meetings. Mirrors
// TeamMeeting in lib/domain/models/meeting.dart and the meetings rules in
// firestore.rules; keep the three in step.

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
  inviteRoles?: string[];
  inviteUsers?: string[];
  requireApproval?: boolean;
  status?: string;
  startedBy?: string;
  rsvps?: Record<string, unknown>;
}

export interface JoinRequestDoc {
  status?: string;
}

const adminRoles = new Set(["owner", "coach", "captain"]);

/** The member's role; a legacy "stats" member is a player. */
export function roleOf(team: MeetingTeam, uid: string): string | undefined {
  const role = team.members?.[uid];
  return role === "stats" ? "player" : role;
}

/**
 * Owners, coaches and captains, and members whose custom roles grant
 * manageEvents, as can(team, 'manageEvents') in firestore.rules.
 */
export function isAdmin(team: MeetingTeam, uid: string): boolean {
  const role = roleOf(team, uid);
  if (role === undefined) return false;
  if (adminRoles.has(role)) return true;
  const perms = team.memberPerms?.[uid];
  return Array.isArray(perms) && perms.includes("manageEvents");
}

/** Admins see every meeting; others when invited by role or by name. */
export function canSee(team: MeetingTeam, meeting: MeetingDoc, uid: string): boolean {
  const role = roleOf(team, uid);
  if (role === undefined) return false;
  return (
    isAdmin(team, uid) ||
    (meeting.inviteRoles ?? []).includes(role) ||
    (meeting.inviteUsers ?? []).includes(uid)
  );
}

/** Team members who can see [meeting]. */
export function invitees(team: MeetingTeam, meeting: MeetingDoc): string[] {
  return Object.keys(team.members ?? {}).filter((uid) => canSee(team, meeting, uid));
}

export type JoinDecision = "ok" | "notMember" | "notInvited" | "missing" | "notStarted" | "ended" | "needsApproval";

/** Whether [uid] may get a token for the meeting's call right now. */
export function joinDecision(a: {
  team?: MeetingTeam;
  meeting?: MeetingDoc;
  request?: JoinRequestDoc;
  uid: string;
}): JoinDecision {
  const { team, meeting, request, uid } = a;
  if (!team || team.deletingAt || roleOf(team, uid) === undefined) return "notMember";
  if (!meeting) return "missing";
  if (!canSee(team, meeting, uid)) return "notInvited";
  if (meeting.status === "ended") return "ended";
  if (meeting.status !== "live") return "notStarted";
  if (meeting.requireApproval === true && !isAdmin(team, uid) && request?.status !== "admitted") {
    return "needsApproval";
  }
  return "ok";
}

export const joinMessages: Record<Exclude<JoinDecision, "ok">, string> = {
  notMember: "You're not on this team.",
  notInvited: "You weren't invited to this meeting.",
  missing: "This meeting no longer exists.",
  notStarted: "The meeting hasn't started yet.",
  ended: "This meeting has ended.",
  needsApproval: "An admin needs to let you in first.",
};

/** The LiveKit room for a meeting. */
export const roomName = (teamId: string, meetingId: string) => `${teamId}_${meetingId}`;

/** What the call shows for [uid]: their team name, else their profile name. */
export function displayName(team: MeetingTeam, uid: string, profileName?: unknown): string {
  const name = team.memberNames?.[uid] ?? (typeof profileName === "string" ? profileName : "");
  return name.trim() || "Member";
}

/**
 * Who hears that the meeting started: invitees attending who aren't
 * already in the room (the starter, and anyone waiting in the lobby).
 */
export function startedRecipients(team: MeetingTeam, meeting: MeetingDoc, inRoom: Iterable<string>): string[] {
  const skip = new Set(inRoom);
  if (meeting.startedBy) skip.add(meeting.startedBy);
  const rsvps = meeting.rsvps ?? {};
  return invitees(team, meeting).filter((uid) => rsvps[uid] === "attending" && !skip.has(uid));
}

export type MeetingChange = "created" | "started" | "cancelled" | "ended";

export function meetingChange(before?: MeetingDoc, after?: MeetingDoc): MeetingChange | null {
  if (!before && after) return "created";
  if (before && !after) return before.status === "ended" ? null : "cancelled";
  if (before && after) {
    if (before.status !== "live" && after.status === "live") return "started";
    if (before.status !== "ended" && after.status === "ended") return "ended";
  }
  return null;
}

// Voice channels ------------------------------------------------------------

/** A chat room (ChatRoom in lib/domain/models/chat.dart). */
export interface VoiceRoomDoc {
  kind?: string;
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
 * Whether [uid] is in a room audience, as inAudience in firestore.rules:
 * "everyone", their tier (a legacy "stats" member is a player), one of
 * their custom roles, or by name. The owner is in every room.
 */
export function inAudience(team: VoiceTeam, uid: string, ids: string[] = [], users: string[] = []): boolean {
  const role = roleOf(team, uid);
  if (role === undefined) return false;
  if (role === "owner") return true;
  const mine = team.memberRoles?.[uid] ?? [];
  return ids.includes("everyone") || ids.includes(role) || mine.some((r) => ids.includes(r)) || users.includes(uid);
}

export type VoiceDecision =
  | { ok: true; canSpeak: boolean }
  | { ok: false; code: "permission-denied" | "not-found" | "failed-precondition"; message: string };

/**
 * Whether [uid] may join a voice channel: members who can read the room
 * listen, and those who can write in it talk too.
 */
export function voiceDecision(team: VoiceTeam | undefined, room: VoiceRoomDoc | undefined, uid: string): VoiceDecision {
  if (!team || team.deletingAt || roleOf(team, uid) === undefined) {
    return { ok: false, code: "permission-denied", message: "You're not on this team." };
  }
  if (!room) return { ok: false, code: "not-found", message: "This channel no longer exists." };
  if (room.kind !== "voice") {
    return { ok: false, code: "failed-precondition", message: "That's not a voice channel." };
  }
  if (!inAudience(team, uid, room.readRoles, room.readUsers)) {
    return { ok: false, code: "permission-denied", message: "You don't have access to this channel." };
  }
  return { ok: true, canSpeak: inAudience(team, uid, room.writeRoles, room.writeUsers) };
}

/** The LiveKit room for a voice channel; can't clash with a meeting's. */
export const voiceRoomName = (teamId: string, roomId: string) => `voice:${teamId}:${roomId}`;
