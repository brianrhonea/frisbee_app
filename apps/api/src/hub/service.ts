import {
  chatReactionChoices,
  chatReactionRequestSchema,
  eventReactionRequestSchema,
  eventVotesRequestSchema,
  nextRsvpNotes,
  rsvpRequestSchema,
  type SaveTeamEventResult,
  type SaveTeamPostResult,
  type SendChatMessageResult,
  saveTeamEventRequestSchema,
  saveTeamPostRequestSchema,
  sendChatMessageRequestSchema,
  sharedEventPreview,
  chatPollPreview,
  teamPostImagesMax,
  teamPostTournamentKeyMax,
} from "@stall10/shared";
import type { Caller, UserLookup } from "../auth.js";
import { ApiError, parseBody } from "../errors.js";
import { docIdParam } from "../ids.js";
import type { MediaStorage } from "../media/storage.js";
import { authorOf, checkNotMuted } from "../posts/author.js";
import { type Data, type DocStore, serverTime } from "../store.js";
import { can, clip, isMember, isOrg, isOwner, mapOf, strings } from "../teams/access.js";
import { canReadRoom, canWriteRoom, seesEvent } from "./access.js";
import { deleteFilesUnder, filesOf, uploadedFiles } from "./uploads.js";

const p = {
  team: (t: string) => `teams/${t}`,
  post: (t: string, id: string) => `teams/${t}/posts/${id}`,
  event: (t: string, id: string) => `teams/${t}/events/${id}`,
  publicEvent: (t: string, id: string) => `teams/${t}/publicEvents/${id}`,
  room: (t: string, r: string) => `teams/${t}/chats/${r}`,
  message: (t: string, r: string, id: string) => `teams/${t}/chats/${r}/messages/${id}`,
  /** The caller's read times for a team's rooms (rooms.{roomId}); private to them. */
  reads: (uid: string, t: string) => `users/${uid}/chatReads/${t}`,
};

const denied = (m: string) => new ApiError("permission_denied", m);
const noTeam = () => new ApiError("not_found", "That team doesn't exist anymore.");
const noEvent = () => new ApiError("not_found", "This event was deleted.");
const noRoom = () => new ApiError("not_found", "That chat doesn't exist anymore.");
const noMessage = () => new ApiError("not_found", "This message was deleted.");

/**
 * validPost's tournamentKey conjunct: absent, or a string of at most 300
 * characters matching 'tournament_' + teamId + '_.+'. The tournament part
 * must also be a plain id (stricter than the rule's '.+').
 */
export function checkTournamentKey(teamId: string, key: string | undefined): string | undefined {
  if (key === undefined) return undefined;
  const prefix = `tournament_${teamId}_`;
  if (key.length > teamPostTournamentKeyMax || !key.startsWith(prefix) || key.length === prefix.length) {
    throw new ApiError("invalid_argument", "That isn't one of this team's tournaments.");
  }
  docIdParam(key.slice(prefix.length));
  return key;
}

/** A per-uid map field without [uid] (FieldValue.delete() on one key). */
function without(m: unknown, uid: string): Data {
  const out = { ...mapOf(m) };
  delete out[uid];
  return out;
}

/**
 * The team hub's writes from the website: team posts, team events with
 * RSVPs, reactions and polls, and chat messages. The Admin SDK skips
 * firestore.rules, so each method checks what its rule checks (comments
 * name the rule), inside a transaction where it reads what it decides on.
 */
export class HubService {
  constructor(
    private readonly store: DocStore,
    private readonly users: UserLookup,
    private readonly media: MediaStorage | undefined,
    private readonly now: () => number = Date.now,
  ) {}

  private async team(teamId: string): Promise<Data> {
    const team = await this.store.get(p.team(teamId));
    if (!team) throw noTeam();
    return team;
  }

  // Team posts (teams/{id}/posts: manageTeam writes; validPost) -----------

  async createPost(caller: Caller, rawTeam: unknown, body: unknown): Promise<SaveTeamPostResult> {
    const teamId = docIdParam(rawTeam);
    const req = parseBody(saveTeamPostRequestSchema, body);
    const tournamentKey = checkTournamentKey(teamId, req.tournamentKey);
    const team = await this.team(teamId);
    if (!can(team, caller.uid, "manageTeam")) throw denied("Only the team's admins post for it.");
    await checkNotMuted(this.store, caller.uid, this.now());
    const id = req.id ?? this.store.newId(`teams/${teamId}/posts`);
    const images = await uploadedFiles(this.store, caller, req.uploadIds, {
      purpose: "teamImage",
      targetId: teamId,
      itemId: id,
      imagesOnly: true,
    });
    const words = req.body.trim();
    if (!words && images.length === 0) throw new ApiError("invalid_argument", "Write something or add a photo.");
    const me = await authorOf(this.store, this.users, caller);
    await this.store.transact(async (tx) => {
      const now = await tx.get(p.team(teamId));
      if (!now || !can(now, caller.uid, "manageTeam")) throw denied("Only the team's admins post for it.");
      if (await tx.get(p.post(teamId, id))) throw new ApiError("already_exists", "That post already exists.");
      tx.create(p.post(teamId, id), {
        title: req.title,
        body: words,
        location: req.location,
        links: req.links,
        images,
        public: req.public,
        ...(tournamentKey !== undefined && { tournamentKey }),
        authorId: caller.uid,
        authorName: me.name,
        createdAt: serverTime,
        updatedAt: serverTime,
      });
    });
    return { id };
  }

  async editPost(caller: Caller, rawTeam: unknown, rawPost: unknown, body: unknown): Promise<SaveTeamPostResult> {
    const teamId = docIdParam(rawTeam);
    const id = docIdParam(rawPost);
    const req = parseBody(saveTeamPostRequestSchema, body);
    const tournamentKey = checkTournamentKey(teamId, req.tournamentKey);
    const team = await this.team(teamId);
    if (!can(team, caller.uid, "manageTeam")) throw denied("Only the team's admins edit its posts.");
    const current = await this.store.get(p.post(teamId, id));
    if (!current) throw new ApiError("not_found", "This post was deleted.");
    const before = filesOf(current.images);
    const keep = req.keepImages ? before.filter((i) => req.keepImages!.includes(i.path)) : before;
    const added = await uploadedFiles(this.store, caller, req.uploadIds, {
      purpose: "teamImage",
      targetId: teamId,
      itemId: id,
      imagesOnly: true,
    });
    const images = [...keep, ...added.filter((a) => !keep.some((k) => k.path === a.path))];
    if (images.length > teamPostImagesMax) throw new ApiError("invalid_argument", `Add at most ${teamPostImagesMax} photos.`);
    const words = req.body.trim();
    if (!words && images.length === 0) throw new ApiError("invalid_argument", "Write something or add a photo.");
    await this.store.transact(async (tx) => {
      const [t, post] = await Promise.all([tx.get(p.team(teamId)), tx.get(p.post(teamId, id))]);
      if (!t || !can(t, caller.uid, "manageTeam")) throw denied("Only the team's admins edit its posts.");
      if (!post) throw new ApiError("not_found", "This post was deleted.");
      tx.update(p.post(teamId, id), {
        title: req.title,
        body: words,
        location: req.location,
        links: req.links,
        images,
        public: req.public,
        ...(tournamentKey !== undefined && { tournamentKey }),
        updatedAt: serverTime,
      });
    });
    const removed = before.filter((i) => !images.some((k) => k.path === i.path));
    await deleteFilesUnder(this.media, `teams/${teamId}/posts/${id}`, removed);
    return { id };
  }

  async deletePost(caller: Caller, rawTeam: unknown, rawPost: unknown): Promise<void> {
    const teamId = docIdParam(rawTeam);
    const id = docIdParam(rawPost);
    const images = await this.store.transact(async (tx) => {
      const [team, post] = await Promise.all([tx.get(p.team(teamId)), tx.get(p.post(teamId, id))]);
      if (!team) throw noTeam();
      if (!can(team, caller.uid, "manageTeam")) throw denied("Only the team's admins delete its posts.");
      if (!post) return [];
      tx.delete(p.post(teamId, id));
      return filesOf(post.images);
    });
    await deleteFilesUnder(this.media, `teams/${teamId}/posts/${id}`, images);
  }

  // Team events (teams/{id}/events: manageEvents writes; respond()) -------

  /** The event's fields as the app writes them (toEditableMap), and its public copy. */
  private eventFields(team: Data, body: unknown, editing = false) {
    const req = parseBody(saveTeamEventRequestSchema, body);
    // An edit without an audience keeps the event's own; a new one is for everyone.
    const keep = !isOrg(team) || (editing && req.audience === undefined);
    const audience = keep ? null : [...new Set(req.audience?.length ? req.audience : ["everyone"])].sort();
    const details = {
      title: req.title,
      type: req.type,
      startsAt: new Date(req.startsAt),
      endsAt: req.endsAt ? new Date(req.endsAt) : null,
      location: req.location,
      notes: req.notes,
    };
    const poll = req.poll
      ? {
          question: req.poll.question,
          options: req.poll.options.map((o) => ({ id: o.id, text: o.text })),
          multiple: req.poll.multiple,
        }
      : null;
    if (poll && new Set(poll.options.map((o) => o.id)).size !== poll.options.length) {
      throw new ApiError("invalid_argument", "Each poll option needs its own id.");
    }
    return { details, poll, isPublic: req.public, audience };
  }

  async createEvent(caller: Caller, rawTeam: unknown, body: unknown): Promise<SaveTeamEventResult> {
    const teamId = docIdParam(rawTeam);
    const team = await this.team(teamId);
    if (!can(team, caller.uid, "manageEvents")) throw denied("You can't add events to this team.");
    await checkNotMuted(this.store, caller.uid, this.now());
    const { details, poll, isPublic, audience } = this.eventFields(team, body);
    const id = this.store.newId(`teams/${teamId}/events`);
    await this.store.transact(async (tx) => {
      const t = await tx.get(p.team(teamId));
      if (!t || !can(t, caller.uid, "manageEvents")) throw denied("You can't add events to this team.");
      tx.create(p.event(teamId, id), {
        ...details,
        poll,
        ...(audience && { audience }),
        public: isPublic,
        rsvps: {},
        reactions: {},
        votes: {},
        createdBy: caller.uid,
        createdAt: serverTime,
        updatedAt: serverTime,
      });
      if (isPublic) tx.set(p.publicEvent(teamId, id), { ...details, updatedAt: serverTime });
    });
    return { id };
  }

  async editEvent(caller: Caller, rawTeam: unknown, rawEvent: unknown, body: unknown): Promise<SaveTeamEventResult> {
    const teamId = docIdParam(rawTeam);
    const id = docIdParam(rawEvent);
    const team = await this.team(teamId);
    if (!can(team, caller.uid, "manageEvents")) throw denied("You can't edit this team's events.");
    const { details, poll, isPublic, audience } = this.eventFields(team, body, true);
    await this.store.transact(async (tx) => {
      const [t, event] = await Promise.all([tx.get(p.team(teamId)), tx.get(p.event(teamId, id))]);
      if (!t || !can(t, caller.uid, "manageEvents")) throw denied("You can't edit this team's events.");
      if (!event) throw noEvent();
      // A changed poll starts its votes over (editors may only reset them).
      const pollChanged = JSON.stringify(event.poll ?? null) !== JSON.stringify(poll);
      tx.update(p.event(teamId, id), {
        ...details,
        poll,
        ...(audience && { audience }),
        public: isPublic,
        ...(pollChanged && { votes: {} }),
        updatedAt: serverTime,
      });
      if (isPublic) tx.set(p.publicEvent(teamId, id), { ...details, updatedAt: serverTime });
      else tx.delete(p.publicEvent(teamId, id));
    });
    return { id };
  }

  async deleteEvent(caller: Caller, rawTeam: unknown, rawEvent: unknown): Promise<void> {
    const teamId = docIdParam(rawTeam);
    const id = docIdParam(rawEvent);
    await this.store.transact(async (tx) => {
      const team = await tx.get(p.team(teamId));
      if (!team) throw noTeam();
      if (!can(team, caller.uid, "manageEvents")) throw denied("You can't delete this team's events.");
      tx.delete(p.event(teamId, id));
      tx.delete(p.publicEvent(teamId, id));
    });
  }

  /** respond(): a member who sees the event changes only their own entries. */
  private async respond(caller: Caller, rawTeam: unknown, rawEvent: unknown, change: (event: Data) => Data) {
    const teamId = docIdParam(rawTeam);
    const id = docIdParam(rawEvent);
    await this.store.transact(async (tx) => {
      const [team, event] = await Promise.all([tx.get(p.team(teamId)), tx.get(p.event(teamId, id))]);
      if (!team) throw noTeam();
      if (!event) throw noEvent();
      if (!isMember(team, caller.uid) || !seesEvent(team, caller.uid, event)) throw noEvent();
      tx.update(p.event(teamId, id), change(event));
    });
  }

  async setRsvp(caller: Caller, rawTeam: unknown, rawEvent: unknown, body: unknown): Promise<void> {
    const { status, note } = parseBody(rsvpRequestSchema, body);
    const uid = caller.uid;
    await this.respond(caller, rawTeam, rawEvent, (event) => ({
      rsvps: status ? { ...mapOf(event.rsvps), [uid]: status } : without(event.rsvps, uid),
      // The note goes with the answer: left out keeps it, taking the answer back drops it.
      rsvpNotes: nextRsvpNotes(event.rsvpNotes, uid, status !== null, note),
      // Only those going react or vote.
      ...(status !== "going" && { reactions: without(event.reactions, uid), votes: without(event.votes, uid) }),
    }));
  }

  async setEventReaction(caller: Caller, rawTeam: unknown, rawEvent: unknown, body: unknown): Promise<void> {
    const { reaction, on } = parseBody(eventReactionRequestSchema, body);
    const uid = caller.uid;
    await this.respond(caller, rawTeam, rawEvent, (event) => {
      if (mapOf(event.rsvps)[uid] !== "going") throw new ApiError("failed_precondition", "Say you're going to react.");
      const mine = strings(mapOf(event.reactions)[uid]).filter((r) => r !== reaction);
      const next = on ? [...mine, reaction] : mine;
      return { reactions: next.length ? { ...mapOf(event.reactions), [uid]: next } : without(event.reactions, uid) };
    });
  }

  async setEventVotes(caller: Caller, rawTeam: unknown, rawEvent: unknown, body: unknown): Promise<void> {
    const { optionIds } = parseBody(eventVotesRequestSchema, body);
    const uid = caller.uid;
    await this.respond(caller, rawTeam, rawEvent, (event) => {
      const poll = event.poll && typeof event.poll === "object" ? (event.poll as Data) : null;
      if (!poll) throw new ApiError("failed_precondition", "This event has no poll.");
      if (mapOf(event.rsvps)[uid] !== "going") throw new ApiError("failed_precondition", "Say you're going to vote.");
      const options = Array.isArray(poll.options) ? poll.options.map((o) => String((o as Data)?.id ?? "")) : [];
      const picked = [...new Set(optionIds)];
      if (picked.some((o) => !options.includes(o))) throw new ApiError("invalid_argument", "That isn't one of the options.");
      if (picked.length > (poll.multiple === true ? options.length : 1)) {
        throw new ApiError("invalid_argument", "Pick one option.");
      }
      return { votes: picked.length ? { ...mapOf(event.votes), [uid]: picked } : without(event.votes, uid) };
    });
  }

  // Team chat (teams/{id}/chats/{room}/messages) --------------------------

  async sendMessage(caller: Caller, rawTeam: unknown, rawRoom: unknown, body: unknown): Promise<SendChatMessageResult> {
    const teamId = docIdParam(rawTeam);
    const roomId = docIdParam(rawRoom);
    const req = parseBody(sendChatMessageRequestSchema, body);
    await checkNotMuted(this.store, caller.uid, this.now());
    const [team, room] = await Promise.all([this.store.get(p.team(teamId)), this.store.get(p.room(teamId, roomId))]);
    if (!team || !room) throw noRoom();
    // Outsiders and those who can't read the room learn nothing about it.
    if (!isMember(team, caller.uid) || !canReadRoom(team, caller.uid, room)) throw noRoom();
    if (!canWriteRoom(team, caller.uid, room)) throw denied("You can read this room but not post in it.");
    const id = req.id ?? this.store.newId(`teams/${teamId}/chats/${roomId}/messages`);
    const attachments = await uploadedFiles(this.store, caller, req.uploadIds, {
      purpose: "chat",
      targetId: `teams/${teamId}/chats/${roomId}`,
      itemId: id,
    });
    const text = req.text.trim();
    if (!text && attachments.length === 0) throw new ApiError("invalid_argument", "Write a message or attach a file.");
    let replyTo: Data | null = null;
    if (req.replyTo) {
      const quoted = await this.store.get(p.message(teamId, roomId, docIdParam(req.replyTo)));
      if (!quoted) throw new ApiError("not_found", "The message you're answering was deleted.");
      replyTo = {
        id: req.replyTo,
        authorId: clip(String(quoted.authorId ?? ""), 128),
        authorName: clip(String(quoted.authorName ?? ""), 80),
        // A shared event or a poll has no text: quote its card's title (F3) or question (F33).
        text: clip(
          String(quoted.text ?? "") ||
            (quoted.event
              ? sharedEventPreview(String(mapOf(quoted.event).title ?? ""))
              : quoted.poll
                ? chatPollPreview(String(mapOf(quoted.poll).question ?? ""))
                : ""),
          200,
        ),
      };
    }
    const me = await authorOf(this.store, this.users, caller);
    await this.store.transact(async (tx) => {
      const [t, r] = await Promise.all([tx.get(p.team(teamId)), tx.get(p.room(teamId, roomId))]);
      if (!t || !r || !isMember(t, caller.uid) || !canWriteRoom(t, caller.uid, r)) throw denied("You can't post in this chat.");
      if (await tx.get(p.message(teamId, roomId, id))) throw new ApiError("already_exists", "That message was already sent.");
      tx.create(p.message(teamId, roomId, id), {
        authorId: caller.uid,
        authorName: me.name,
        text,
        attachments,
        createdAt: serverTime,
        ...(replyTo && { replyTo }),
      });
      // The inbox's unread dots: when the room last had a message (a time,
      // never the text), and the sender has read their own.
      tx.update(p.room(teamId, roomId), { lastAt: serverTime });
      tx.merge(p.reads(caller.uid, teamId), { rooms: { [roomId]: serverTime } });
    });
    return { id };
  }

  /** Marks a room read for the caller (users/{uid}/chatReads/{teamId}), for their unread dots. */
  async markRoomRead(caller: Caller, rawTeam: unknown, rawRoom: unknown): Promise<void> {
    const teamId = docIdParam(rawTeam);
    const roomId = docIdParam(rawRoom);
    const [team, room] = await Promise.all([this.store.get(p.team(teamId)), this.store.get(p.room(teamId, roomId))]);
    if (!team || !room || !isMember(team, caller.uid) || !canReadRoom(team, caller.uid, room)) throw noRoom();
    await this.store.transact(async (tx) => {
      tx.merge(p.reads(caller.uid, teamId), { rooms: { [roomId]: serverTime } });
    });
  }

  /** reactsOnlyAsMe(): anyone who can read the room sets or clears their own emoji. */
  async setMessageReaction(caller: Caller, rawTeam: unknown, rawRoom: unknown, rawMessage: unknown, body: unknown): Promise<void> {
    const teamId = docIdParam(rawTeam);
    const roomId = docIdParam(rawRoom);
    const id = docIdParam(rawMessage);
    const { emoji } = parseBody(chatReactionRequestSchema, body);
    if (emoji !== null && !(chatReactionChoices as readonly string[]).includes(emoji)) {
      throw new ApiError("invalid_argument", "Pick one of the reactions.");
    }
    await this.store.transact(async (tx) => {
      const [team, room, message] = await Promise.all([
        tx.get(p.team(teamId)),
        tx.get(p.room(teamId, roomId)),
        tx.get(p.message(teamId, roomId, id)),
      ]);
      if (!team || !room || !isMember(team, caller.uid) || !canReadRoom(team, caller.uid, room)) throw noRoom();
      if (!message) throw noMessage();
      const reactions = emoji ? { ...mapOf(message.reactions), [caller.uid]: emoji } : without(message.reactions, caller.uid);
      tx.update(p.message(teamId, roomId, id), { reactions });
    });
  }

  /** Authors delete their own; the owner, and moderators or chat managers who can read the room, moderate. */
  async deleteMessage(caller: Caller, rawTeam: unknown, rawRoom: unknown, rawMessage: unknown): Promise<void> {
    const teamId = docIdParam(rawTeam);
    const roomId = docIdParam(rawRoom);
    const id = docIdParam(rawMessage);
    const message = await this.store.transact(async (tx) => {
      const [team, room, message] = await Promise.all([
        tx.get(p.team(teamId)),
        tx.get(p.room(teamId, roomId)),
        tx.get(p.message(teamId, roomId, id)),
      ]);
      if (!team || !room) throw noRoom();
      const uid = caller.uid;
      const reads = isMember(team, uid) && canReadRoom(team, uid, room);
      // Outsiders learn nothing about which messages exist.
      if (!isMember(team, uid)) throw noRoom();
      if (!message) return null;
      const allowed =
        message.authorId === uid ||
        isOwner(team, uid) ||
        ((can(team, uid, "moderate") || can(team, uid, "manageChats")) && reads);
      if (!allowed) throw reads ? denied("You can only delete your own messages.") : noRoom();
      tx.delete(p.message(teamId, roomId, id));
      // Its pin goes with it (F2).
      const pins = strings(room.pins);
      if (pins.includes(id)) tx.update(p.room(teamId, roomId), { pins: pins.filter((x) => x !== id) });
      return message;
    });
    if (message) {
      const author = String(message.authorId ?? "");
      await deleteFilesUnder(this.media, `teams/${teamId}/chats/${roomId}/${author}/${id}`, filesOf(message.attachments));
    }
  }
}
