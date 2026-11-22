// Team meetings (teams/{id}/meetings) and voice channels, for the website.
//
// The writes are ports of the `match /meetings/{meetingId}` rules in
// firestore.rules (create, editDetails, respond, start, end, delete, and
// requests, playback and messages beneath), which the Admin SDK skips, so
// every conjunct is checked here. The token routes port the
// meetings-joinToken and meetings-voiceToken callables
// (firebase/functions/src/meetings/functions.ts): the same checks in the
// same order, the same grants and messages. The app keeps the callables
// and its direct writes; the closeRoom trigger still closes the call when
// a meeting ends or is deleted, whoever wrote it.
import {
  audienceTier,
  meetingDisplayName,
  type JoinRequestDoc,
  meetingInviteRoles,
  meetingJoinDecision,
  meetingJoinDecisionRequestSchema,
  meetingJoinMessages,
  meetingLimits,
  meetingMessageRequestSchema,
  meetingPlaybackRequestSchema,
  meetingRoomName,
  meetingRsvpRequestSchema,
  nextRsvpNotes,
  type MeetingDoc,
  type MeetingTeam,
  type MeetingTokenResult,
  saveMeetingRequestSchema,
  type SaveMeetingResult,
  validMeetingId,
  voiceDecision,
  type VoiceRoomDoc,
  type VoiceTeam,
  type VoiceTokenResult,
  voiceRoomName,
} from "@stall10/shared";
import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import type { z } from "zod";
import { type Caller, requireCaller, type UserLookup } from "../auth.js";
import { ApiError, parseBody } from "../errors.js";
import { chatRole } from "../hub/access.js";
import { hubLimits } from "../hub/routes.js";
import { docIdParam } from "../ids.js";
import { limited, type MemoryRateLimiter } from "../limits/memory.js";
import type { Limit } from "../limits/model.js";
import { authorOf, checkNotMuted } from "../posts/author.js";
import { type Data, type DocStore, serverTime } from "../store.js";
import { can, clip, isMember, mapOf, strings } from "../teams/access.js";
import type { TeamRepository } from "../teams/repository.js";
import type { LiveKitSigner } from "./signer.js";

const minute = 60_000;

/**
 * Buckets of their own: tokens are reads that mint credentials, and the
 * presenter's playback heartbeat (every 10 s) plus play, pause and seeks
 * would crowd the hub's 30-a-minute write bucket.
 */
export const meetingRateLimits = {
  token: { max: 30, windowMs: minute },
  playback: { max: 60, windowMs: minute },
} satisfies Record<string, Limit>;

const p = {
  team: (t: string) => `teams/${t}`,
  meetings: (t: string) => `teams/${t}/meetings`,
  meeting: (t: string, m: string) => `teams/${t}/meetings/${m}`,
  request: (t: string, m: string, u: string) => `teams/${t}/meetings/${m}/requests/${u}`,
  playback: (t: string, m: string) => `teams/${t}/meetings/${m}/playback/current`,
  messages: (t: string, m: string) => `teams/${t}/meetings/${m}/messages`,
  message: (t: string, m: string, id: string) => `teams/${t}/meetings/${m}/messages/${id}`,
  video: (t: string, v: string) => `teams/${t}/videos/${v}`,
  room: (t: string, r: string) => `teams/${t}/chats/${r}`,
  profile: (u: string) => `profiles/${u}`,
};

const noTeam = () => new ApiError("not_found", "That team doesn't exist.");
const notOnTeam = () => new ApiError("permission_denied", "You're not on this team.");
const noMeeting = () => new ApiError("not_found", meetingJoinMessages.missing);
const notInvited = () => new ApiError("permission_denied", meetingJoinMessages.notInvited);
const adminsOnly = () => new ApiError("permission_denied", "Only admins can manage meetings.");
const notSetUp = () => new ApiError("failed_precondition", "Meetings aren't set up here yet.");

// ---- The rules' helpers (match /meetings/{meetingId}) ----------------------

/** canManage: can(team(), 'manageEvents'). */
const manages = (team: Data, uid: string) => can(team, uid, "manageEvents");

/** invited(m): admins, or by tier, or by name. */
export function invited(team: Data, uid: string, m: Data): boolean {
  return manages(team, uid) || strings(m.inviteRoles).includes(chatRole(team, uid)) || strings(m.inviteUsers).includes(uid);
}

/** inCall(m): admins, and invitees let in when the meeting needs approval. */
export function inCall(team: Data, uid: string, m: Data, request: Data | null): boolean {
  return manages(team, uid) || (invited(team, uid, m) && (m.requireApproval !== true || request?.status === "admitted"));
}

/**
 * The editable fields as stored (TeamMeeting.toEditableMap): roles in the
 * app's order, and per-person invites only for current members who aren't
 * admins or already invited by their tier, sorted, as the app's editor
 * saves them.
 */
function editableFields(team: Data, m: z.output<typeof saveMeetingRequestSchema>): Data {
  const roles = meetingInviteRoles.filter((r) => m.inviteRoles.includes(r));
  const members = mapOf(team.members);
  const users = [...new Set(m.inviteUsers)].filter((uid) => {
    const raw = Object.hasOwn(members, uid) ? members[uid] : undefined;
    if (typeof raw !== "string") return false;
    const role = audienceTier(raw);
    return !["owner", "coach", "captain"].includes(role) && !roles.includes(role as (typeof roles)[number]);
  });
  return {
    title: m.title,
    startsAt: new Date(m.startsAt),
    endsAt: m.endsAt ? new Date(m.endsAt) : null,
    notes: m.notes,
    inviteRoles: roles,
    inviteUsers: users.sort(),
    requireApproval: m.requireApproval,
  };
}

export class MeetingService {
  constructor(
    private readonly store: DocStore,
    private readonly users: UserLookup,
    private readonly teams: Pick<TeamRepository, "deleteTree">,
    private readonly livekit: LiveKitSigner | undefined,
    private readonly now: () => number = Date.now,
  ) {}

  /** The meeting's name for people (AppUser.label on the web: the author name posts use). */
  private async nameOf(caller: Caller) {
    return clip((await authorOf(this.store, this.users, caller)).name, meetingLimits.name);
  }

  /** allow create: an admin, status scheduled, no answers yet, made by the caller, validMeeting. */
  async create(caller: Caller, rawTeam: unknown, body: unknown): Promise<SaveMeetingResult> {
    const teamId = docIdParam(rawTeam);
    const req = parseBody(saveMeetingRequestSchema, body);
    const id = this.store.newId(p.meetings(teamId));
    await this.store.transact(async (tx) => {
      const team = await tx.get(p.team(teamId));
      if (!team) throw noTeam();
      if (!manages(team, caller.uid)) throw adminsOnly();
      tx.create(p.meeting(teamId, id), {
        ...editableFields(team, req),
        status: "scheduled",
        rsvps: {},
        createdBy: caller.uid,
        createdAt: serverTime,
        updatedAt: serverTime,
      });
    });
    return { id };
  }

  /** editDetails: a member who manages events changes only the editable fields. */
  async edit(caller: Caller, rawTeam: unknown, rawMeeting: unknown, body: unknown): Promise<void> {
    const teamId = docIdParam(rawTeam);
    const meetingId = docIdParam(rawMeeting);
    const req = parseBody(saveMeetingRequestSchema, body);
    await this.store.transact(async (tx) => {
      const [team, meeting] = await Promise.all([tx.get(p.team(teamId)), tx.get(p.meeting(teamId, meetingId))]);
      if (!team) throw noTeam();
      if (!isMember(team, caller.uid)) throw notOnTeam();
      if (!manages(team, caller.uid)) throw adminsOnly();
      if (!meeting) throw noMeeting();
      tx.update(p.meeting(teamId, meetingId), { ...editableFields(team, req), updatedAt: serverTime });
    });
  }

  /**
   * allow delete (cancelling): admins. Its chat, join requests and
   * playback go with it, as the app's deleteMeeting clears them.
   */
  async cancel(caller: Caller, rawTeam: unknown, rawMeeting: unknown): Promise<void> {
    const teamId = docIdParam(rawTeam);
    const meetingId = docIdParam(rawMeeting);
    const [team, meeting] = await Promise.all([this.store.get(p.team(teamId)), this.store.get(p.meeting(teamId, meetingId))]);
    if (!team) throw noTeam();
    if (!manages(team, caller.uid)) throw adminsOnly();
    if (!meeting) return;
    await this.teams.deleteTree(p.meeting(teamId, meetingId));
  }

  /** respond: an invitee answers for themselves only; null takes it back. */
  async rsvp(caller: Caller, rawTeam: unknown, rawMeeting: unknown, body: unknown): Promise<void> {
    const teamId = docIdParam(rawTeam);
    const meetingId = docIdParam(rawMeeting);
    const { answer, note } = parseBody(meetingRsvpRequestSchema, body);
    await this.store.transact(async (tx) => {
      const [team, meeting] = await Promise.all([tx.get(p.team(teamId)), tx.get(p.meeting(teamId, meetingId))]);
      if (!team) throw noTeam();
      if (!isMember(team, caller.uid)) throw notOnTeam();
      if (!meeting) throw noMeeting();
      if (!invited(team, caller.uid, meeting)) throw notInvited();
      // The whole map, read in this transaction: only the caller's key moves.
      const rsvps: Data = { ...mapOf(meeting.rsvps) };
      if (answer === null) delete rsvps[caller.uid];
      else rsvps[caller.uid] = answer;
      // The note goes with the answer (respond's rsvpNotes conjuncts).
      const rsvpNotes = nextRsvpNotes(meeting.rsvpNotes, caller.uid, answer !== null, note);
      tx.update(p.meeting(teamId, meetingId), { rsvps, rsvpNotes });
    });
  }

  /** start: an admin opens a scheduled meeting. */
  async start(caller: Caller, rawTeam: unknown, rawMeeting: unknown): Promise<void> {
    const teamId = docIdParam(rawTeam);
    const meetingId = docIdParam(rawMeeting);
    await this.store.transact(async (tx) => {
      const [team, meeting] = await Promise.all([tx.get(p.team(teamId)), tx.get(p.meeting(teamId, meetingId))]);
      if (!team) throw noTeam();
      if (!isMember(team, caller.uid)) throw notOnTeam();
      if (!manages(team, caller.uid)) throw new ApiError("permission_denied", "Only admins can start the meeting.");
      if (!meeting) throw noMeeting();
      if (meeting.status === "ended") throw new ApiError("failed_precondition", meetingJoinMessages.ended);
      if (meeting.status !== "scheduled") throw new ApiError("failed_precondition", "The meeting has already started.");
      tx.update(p.meeting(teamId, meetingId), { status: "live", startedAt: serverTime, startedBy: caller.uid });
    });
  }

  /** end: an admin ends it for everyone; watch together stops with it (the app's endMeeting). */
  async end(caller: Caller, rawTeam: unknown, rawMeeting: unknown): Promise<void> {
    const teamId = docIdParam(rawTeam);
    const meetingId = docIdParam(rawMeeting);
    await this.store.transact(async (tx) => {
      const [team, meeting, playback] = await Promise.all([
        tx.get(p.team(teamId)),
        tx.get(p.meeting(teamId, meetingId)),
        tx.get(p.playback(teamId, meetingId)),
      ]);
      if (!team) throw noTeam();
      if (!isMember(team, caller.uid)) throw notOnTeam();
      if (!manages(team, caller.uid)) throw new ApiError("permission_denied", "Only admins can end the meeting.");
      if (!meeting) throw noMeeting();
      if (meeting.status === "ended") throw new ApiError("failed_precondition", meetingJoinMessages.ended);
      tx.update(p.meeting(teamId, meetingId), { status: "ended", endedAt: serverTime });
      if (playback) tx.delete(p.playback(teamId, meetingId));
    });
  }

  /**
   * requests/{userId} create, update: invitees ask (or ask again) for
   * themselves, while the meeting needs approval and hasn't ended.
   */
  async askToJoin(caller: Caller, rawTeam: unknown, rawMeeting: unknown, rawUser: unknown): Promise<void> {
    const teamId = docIdParam(rawTeam);
    const meetingId = docIdParam(rawMeeting);
    const userId = docIdParam(rawUser);
    if (userId !== caller.uid) throw new ApiError("permission_denied", "You can only ask to join for yourself.");
    const name = await this.nameOf(caller);
    await this.store.transact(async (tx) => {
      const [team, meeting] = await Promise.all([tx.get(p.team(teamId)), tx.get(p.meeting(teamId, meetingId))]);
      if (!team) throw noTeam();
      if (!isMember(team, caller.uid)) throw notOnTeam();
      if (!meeting) throw noMeeting();
      if (!invited(team, caller.uid, meeting)) throw notInvited();
      if (meeting.requireApproval !== true) throw new ApiError("failed_precondition", "This meeting doesn't need approval.");
      if (meeting.status === "ended") throw new ApiError("failed_precondition", meetingJoinMessages.ended);
      tx.set(p.request(teamId, meetingId, userId), { name, status: "pending", requestedAt: serverTime });
    });
  }

  /** requests/{userId} update by an admin: let in or turned away, by whom and when. */
  async decide(caller: Caller, rawTeam: unknown, rawMeeting: unknown, rawUser: unknown, body: unknown): Promise<void> {
    const teamId = docIdParam(rawTeam);
    const meetingId = docIdParam(rawMeeting);
    const userId = docIdParam(rawUser);
    const { admit } = parseBody(meetingJoinDecisionRequestSchema, body);
    await this.store.transact(async (tx) => {
      const [team, request] = await Promise.all([tx.get(p.team(teamId)), tx.get(p.request(teamId, meetingId, userId))]);
      if (!team) throw noTeam();
      if (!manages(team, caller.uid)) throw new ApiError("permission_denied", "Only admins can let people in.");
      if (!request) throw new ApiError("not_found", "They're no longer asking to join.");
      tx.update(p.request(teamId, meetingId, userId), {
        status: admit ? "admitted" : "denied",
        decidedBy: caller.uid,
        decidedAt: serverTime,
      });
    });
  }

  /** requests/{userId} delete: the asker takes it back, or an admin clears it. */
  async withdraw(caller: Caller, rawTeam: unknown, rawMeeting: unknown, rawUser: unknown): Promise<void> {
    const teamId = docIdParam(rawTeam);
    const meetingId = docIdParam(rawMeeting);
    const userId = docIdParam(rawUser);
    await this.store.transact(async (tx) => {
      const team = caller.uid === userId ? null : await tx.get(p.team(teamId));
      if (caller.uid !== userId && !(team && manages(team, caller.uid))) {
        throw new ApiError("permission_denied", "You can only take back your own request.");
      }
      tx.delete(p.request(teamId, meetingId, userId));
    });
  }

  /**
   * playback/current create, update (watch together): an admin, while the
   * meeting is live, puts up one of the team's videos; they become the
   * presenter, and the time is the server's.
   */
  async setPlayback(caller: Caller, rawTeam: unknown, rawMeeting: unknown, body: unknown): Promise<void> {
    const teamId = docIdParam(rawTeam);
    const meetingId = docIdParam(rawMeeting);
    const req = parseBody(meetingPlaybackRequestSchema, body);
    const videoId = docIdParam(req.videoId);
    const presenterName = await this.nameOf(caller);
    await this.store.transact(async (tx) => {
      const [team, meeting, video] = await Promise.all([
        tx.get(p.team(teamId)),
        tx.get(p.meeting(teamId, meetingId)),
        tx.get(p.video(teamId, videoId)),
      ]);
      if (!team) throw noTeam();
      if (!manages(team, caller.uid)) throw new ApiError("permission_denied", "Only admins can play videos for everyone.");
      if (!meeting) throw noMeeting();
      if (meeting.status !== "live") throw new ApiError("failed_precondition", "Videos play for everyone while the meeting is live.");
      if (!video) throw new ApiError("not_found", "That video was removed.");
      tx.set(p.playback(teamId, meetingId), {
        videoId,
        playing: req.playing,
        positionMs: req.positionMs,
        presenterId: caller.uid,
        presenterName,
        updatedAt: serverTime,
      });
    });
  }

  /** playback delete: admins stop it, any time. */
  async stopPlayback(caller: Caller, rawTeam: unknown, rawMeeting: unknown): Promise<void> {
    const teamId = docIdParam(rawTeam);
    const meetingId = docIdParam(rawMeeting);
    await this.store.transact(async (tx) => {
      const team = await tx.get(p.team(teamId));
      if (!team) throw noTeam();
      if (!manages(team, caller.uid)) throw new ApiError("permission_denied", "Only admins can play videos for everyone.");
      tx.delete(p.playback(teamId, meetingId));
    });
  }

  /** messages create: the call's chat, by people in the call while it's live, not while muted. */
  async sendMessage(caller: Caller, rawTeam: unknown, rawMeeting: unknown, body: unknown): Promise<{ id: string }> {
    const teamId = docIdParam(rawTeam);
    const meetingId = docIdParam(rawMeeting);
    const { text } = parseBody(meetingMessageRequestSchema, body);
    await checkNotMuted(this.store, caller.uid, this.now());
    const authorName = await this.nameOf(caller);
    const id = this.store.newId(p.messages(teamId, meetingId));
    await this.store.transact(async (tx) => {
      const [team, meeting, request] = await Promise.all([
        tx.get(p.team(teamId)),
        tx.get(p.meeting(teamId, meetingId)),
        tx.get(p.request(teamId, meetingId, caller.uid)),
      ]);
      if (!team) throw noTeam();
      if (!isMember(team, caller.uid)) throw notOnTeam();
      if (!meeting) throw noMeeting();
      if (meeting.status !== "live") throw new ApiError("failed_precondition", "The meeting isn't live.");
      if (!inCall(team, caller.uid, meeting, request)) throw new ApiError("permission_denied", "Join the meeting to chat.");
      tx.create(p.message(teamId, meetingId, id), { authorId: caller.uid, authorName, text, createdAt: serverTime });
    });
    return { id };
  }

  /** messages delete: authors their own; admins any. */
  async deleteMessage(caller: Caller, rawTeam: unknown, rawMeeting: unknown, rawMessage: unknown): Promise<void> {
    const teamId = docIdParam(rawTeam);
    const meetingId = docIdParam(rawMeeting);
    const id = docIdParam(rawMessage);
    await this.store.transact(async (tx) => {
      const [team, message] = await Promise.all([tx.get(p.team(teamId)), tx.get(p.message(teamId, meetingId, id))]);
      if (!message) return;
      if (message.authorId !== caller.uid && !(team && manages(team, caller.uid))) {
        throw new ApiError("permission_denied", "You can only delete your own messages.");
      }
      tx.delete(p.message(teamId, meetingId, id));
    });
  }

  /**
   * joinToken: a member who can see the meeting, while it's live, and let
   * in by an admin when it needs approval. Named by uid, with their photo
   * in the metadata; 6 hours.
   */
  async joinToken(caller: Caller, rawTeam: unknown, rawMeeting: unknown): Promise<MeetingTokenResult> {
    if (!validMeetingId(rawTeam) || !validMeetingId(rawMeeting)) throw new ApiError("invalid_argument", "Unknown meeting.");
    const teamId = docIdParam(rawTeam);
    const meetingId = docIdParam(rawMeeting);
    const livekit = this.livekit;
    if (!livekit) throw notSetUp();
    const uid = caller.uid;
    const [team, meeting, request, profile] = await Promise.all([
      this.store.get(p.team(teamId)),
      this.store.get(p.meeting(teamId, meetingId)),
      this.store.get(p.request(teamId, meetingId, uid)),
      this.store.get(p.profile(uid)),
    ]);
    const teamData = (team ?? undefined) as MeetingTeam | undefined;
    const decision = meetingJoinDecision({
      team: teamData,
      meeting: (meeting ?? undefined) as MeetingDoc | undefined,
      request: (request ?? undefined) as JoinRequestDoc | undefined,
      uid,
    });
    if (decision !== "ok") {
      const code = decision === "notStarted" || decision === "needsApproval" ? "failed_precondition" : "permission_denied";
      throw new ApiError(code, meetingJoinMessages[decision]);
    }
    const photoUrl = profile?.photoUrl;
    const token = await livekit.sign({
      identity: uid,
      name: meetingDisplayName(teamData!, uid, profile?.name),
      metadata: JSON.stringify(typeof photoUrl === "string" ? { photoUrl } : {}),
      ttl: "6h",
      room: meetingRoomName(teamId, meetingId),
      canPublish: true,
    });
    return { url: livekit.url, token };
  }

  /**
   * voiceToken: members who can read the voice channel listen; those who
   * can write in it talk too.
   */
  async voiceToken(caller: Caller, rawTeam: unknown, rawRoom: unknown): Promise<VoiceTokenResult> {
    if (!validMeetingId(rawTeam) || !validMeetingId(rawRoom)) throw new ApiError("invalid_argument", "Unknown channel.");
    const teamId = docIdParam(rawTeam);
    const roomId = docIdParam(rawRoom);
    const livekit = this.livekit;
    if (!livekit) throw notSetUp();
    const uid = caller.uid;
    const [team, room, profile] = await Promise.all([
      this.store.get(p.team(teamId)),
      this.store.get(p.room(teamId, roomId)),
      this.store.get(p.profile(uid)),
    ]);
    const teamData = (team ?? undefined) as VoiceTeam | undefined;
    const decision = voiceDecision(teamData, (room ?? undefined) as VoiceRoomDoc | undefined, uid);
    if (!decision.ok) {
      const code = ({ "permission-denied": "permission_denied", "not-found": "not_found", "failed-precondition": "failed_precondition" } as const)[decision.code];
      throw new ApiError(code, decision.message);
    }
    const photoUrl = profile?.photoUrl;
    const token = await livekit.sign({
      identity: uid,
      name: meetingDisplayName(teamData!, uid, profile?.name),
      metadata: JSON.stringify(typeof photoUrl === "string" ? { photoUrl } : {}),
      ttl: "6h",
      room: voiceRoomName(teamId, roomId),
      canPublish: decision.canSpeak,
    });
    return { url: livekit.url, token, canSpeak: decision.canSpeak };
  }
}

/** The meetings and voice routes, as the signed-in caller. */
export function meetingRoutes(app: FastifyInstance, meetings: MeetingService, limiter: MemoryRateLimiter) {
  const buckets = { ...hubLimits, ...meetingRateLimits };
  const caller = (req: FastifyRequest, bucket: keyof typeof buckets): Caller => {
    const c = requireCaller(req);
    const key = bucket in meetingRateLimits ? `meeting-${bucket}:${c.uid}` : `${bucket}:${c.uid}`;
    limited(limiter, key, buckets[bucket]);
    return c;
  };
  const noContent = async (reply: FastifyReply, work: () => Promise<void>) => {
    await work();
    return reply.code(204).send();
  };
  type T = { Params: { teamId: string } };
  type M = { Params: { teamId: string; meetingId: string } };
  type U = { Params: { teamId: string; meetingId: string; userId: string } };
  type Msg = { Params: { teamId: string; meetingId: string; messageId: string } };
  type V = { Params: { teamId: string; roomId: string } };
  const base = "/v1/teams/:teamId/meetings";

  app.post<T>(base, async (req, reply) => reply.code(201).send(await meetings.create(caller(req, "write"), req.params.teamId, req.body)));
  app.patch<M>(`${base}/:meetingId`, (req, reply) =>
    noContent(reply, () => meetings.edit(caller(req, "write"), req.params.teamId, req.params.meetingId, req.body)),
  );
  app.delete<M>(`${base}/:meetingId`, (req, reply) => noContent(reply, () => meetings.cancel(caller(req, "write"), req.params.teamId, req.params.meetingId)));
  app.put<M>(`${base}/:meetingId/rsvp`, (req, reply) =>
    noContent(reply, () => meetings.rsvp(caller(req, "respond"), req.params.teamId, req.params.meetingId, req.body)),
  );
  app.post<M>(`${base}/:meetingId/start`, (req, reply) => noContent(reply, () => meetings.start(caller(req, "write"), req.params.teamId, req.params.meetingId)));
  app.post<M>(`${base}/:meetingId/end`, (req, reply) => noContent(reply, () => meetings.end(caller(req, "write"), req.params.teamId, req.params.meetingId)));
  app.put<U>(`${base}/:meetingId/requests/:userId`, (req, reply) =>
    noContent(reply, () => meetings.askToJoin(caller(req, "write"), req.params.teamId, req.params.meetingId, req.params.userId)),
  );
  app.put<U>(`${base}/:meetingId/requests/:userId/decision`, (req, reply) =>
    noContent(reply, () => meetings.decide(caller(req, "write"), req.params.teamId, req.params.meetingId, req.params.userId, req.body)),
  );
  app.delete<U>(`${base}/:meetingId/requests/:userId`, (req, reply) =>
    noContent(reply, () => meetings.withdraw(caller(req, "write"), req.params.teamId, req.params.meetingId, req.params.userId)),
  );
  app.put<M>(`${base}/:meetingId/playback`, (req, reply) =>
    noContent(reply, () => meetings.setPlayback(caller(req, "playback"), req.params.teamId, req.params.meetingId, req.body)),
  );
  app.delete<M>(`${base}/:meetingId/playback`, (req, reply) =>
    noContent(reply, () => meetings.stopPlayback(caller(req, "playback"), req.params.teamId, req.params.meetingId)),
  );
  app.post<M>(`${base}/:meetingId/messages`, async (req, reply) =>
    reply.code(201).send(await meetings.sendMessage(caller(req, "chat"), req.params.teamId, req.params.meetingId, req.body)),
  );
  app.delete<Msg>(`${base}/:meetingId/messages/:messageId`, (req, reply) =>
    noContent(reply, () => meetings.deleteMessage(caller(req, "chat"), req.params.teamId, req.params.meetingId, req.params.messageId)),
  );
  // Tokens are credentials: answered, never logged.
  // Tokens are bearer credentials: never kept by a cache.
  app.post<M>(`${base}/:meetingId/token`, async (req, reply) =>
    reply.header("cache-control", "no-store").send(await meetings.joinToken(caller(req, "token"), req.params.teamId, req.params.meetingId)),
  );
  app.post<V>("/v1/teams/:teamId/voice-rooms/:roomId/token", async (req, reply) =>
    reply.header("cache-control", "no-store").send(await meetings.voiceToken(caller(req, "token"), req.params.teamId, req.params.roomId)),
  );
}
