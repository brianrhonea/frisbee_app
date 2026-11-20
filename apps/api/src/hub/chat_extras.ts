// Team chat extras (redesign F2, F3, F33): pinned messages, event cards
// and polls. API-only: firestore.rules lets no client set a message's
// pinnedAt, pinnedBy, event or poll, nor a room's pins, so these checks
// are the only ones.
import {
  chatEventTitleMax,
  chatPollClosed,
  createChatPollRequestSchema,
  voteChatPollRequestSchema,
  chatPinsFullMessage,
  chatPinsMax,
  pinChatMessageRequestSchema,
  type SendChatMessageResult,
  shareChatEventRequestSchema,
} from "@stall10/shared";
import type { Caller, UserLookup } from "../auth.js";
import { ApiError, parseBody } from "../errors.js";
import { docIdParam } from "../ids.js";
import { authorOf, checkNotMuted } from "../posts/author.js";
import { type Data, type DocStore, deleteField, serverTime } from "../store.js";
import { can, clip, isMember, isOrg, isOwner, strings } from "../teams/access.js";
import { canReadRoom, canWriteRoom } from "./access.js";

const p = {
  team: (t: string) => `teams/${t}`,
  event: (t: string, id: string) => `teams/${t}/events/${id}`,
  room: (t: string, r: string) => `teams/${t}/chats/${r}`,
  message: (t: string, r: string, id: string) => `teams/${t}/chats/${r}/messages/${id}`,
  reads: (uid: string, t: string) => `users/${uid}/chatReads/${t}`,
};

const denied = (m: string) => new ApiError("permission_denied", m);
const noRoom = () => new ApiError("not_found", "That chat doesn't exist anymore.");
const noMessage = () => new ApiError("not_found", "This message was deleted.");
const noPoll = () => new ApiError("not_found", "This poll was deleted.");

/** Who pins in a room: the owner, and chat managers who can read it (they manage its settings). */
export const canPin = (team: Data, uid: string, room: Data) =>
  isOwner(team, uid) || (isMember(team, uid) && can(team, uid, "manageChats") && canReadRoom(team, uid, room));

/** The room's pinned ids, as stored (at most chatPinsMax are ever written). */
export const pinsOf = (room: Data) => strings(room.pins).slice(0, chatPinsMax * 2);

/**
 * An event everyone in the room may see: every team or group event, and
 * a community's events for "everyone" (the card's title reaches every
 * reader, in the message and its push).
 */
const sharedWithAll = (team: Data, event: Data) => !isOrg(team) || strings(event.audience).includes("everyone");

/** A message's poll, or null when it has none. */
const pollOf = (message: Data | null): Data | null =>
  message && message.poll && typeof message.poll === "object" ? (message.poll as Data) : null;

/** The poll's votes as stored, uid → option indexes. */
const votesOf = (poll: Data): Record<string, number[]> => {
  const out: Record<string, number[]> = {};
  const raw = poll.votes && typeof poll.votes === "object" ? (poll.votes as Data) : {};
  for (const [uid, v] of Object.entries(raw)) if (Array.isArray(v)) out[uid] = v.filter((x): x is number => typeof x === "number");
  return out;
};

export class ChatExtrasService {
  constructor(
    private readonly store: DocStore,
    private readonly users: UserLookup,
    private readonly now: () => number = Date.now,
  ) {}

  /**
   * Pins a message (again: a no-op). A full room refuses unless [unpin]
   * names one of its pins to take down in the same write. Pins whose
   * message was deleted (the app deletes directly) are dropped first.
   */
  async pin(caller: Caller, rawTeam: unknown, rawRoom: unknown, rawMessage: unknown, body: unknown): Promise<void> {
    const teamId = docIdParam(rawTeam);
    const roomId = docIdParam(rawRoom);
    const id = docIdParam(rawMessage);
    const { unpin } = parseBody(pinChatMessageRequestSchema, body ?? {});
    const swap = unpin === undefined ? undefined : docIdParam(unpin);
    await this.store.transact(async (tx) => {
      const [team, room, message] = await Promise.all([
        tx.get(p.team(teamId)),
        tx.get(p.room(teamId, roomId)),
        tx.get(p.message(teamId, roomId, id)),
      ]);
      if (!team || !room || !isMember(team, caller.uid) || !canReadRoom(team, caller.uid, room)) throw noRoom();
      if (!canPin(team, caller.uid, room)) throw denied("Only the team's chat managers pin messages.");
      if (!message) throw noMessage();
      const stored = pinsOf(room).filter((x) => x !== id);
      const there = await Promise.all(stored.map((x) => tx.get(p.message(teamId, roomId, x))));
      let pins = stored.filter((_, i) => there[i] !== null);
      if (swap !== undefined && pins.includes(swap)) {
        pins = pins.filter((x) => x !== swap);
        tx.update(p.message(teamId, roomId, swap), { pinnedAt: deleteField, pinnedBy: deleteField });
      }
      if (pins.length >= chatPinsMax) throw new ApiError("failed_precondition", chatPinsFullMessage);
      tx.update(p.room(teamId, roomId), { pins: [id, ...pins] });
      if (!message.pinnedAt) tx.update(p.message(teamId, roomId, id), { pinnedAt: serverTime, pinnedBy: caller.uid });
    });
  }

  /** Unpins a message (one that's gone, or never pinned: a no-op). */
  async unpin(caller: Caller, rawTeam: unknown, rawRoom: unknown, rawMessage: unknown): Promise<void> {
    const teamId = docIdParam(rawTeam);
    const roomId = docIdParam(rawRoom);
    const id = docIdParam(rawMessage);
    await this.store.transact(async (tx) => {
      const [team, room, message] = await Promise.all([
        tx.get(p.team(teamId)),
        tx.get(p.room(teamId, roomId)),
        tx.get(p.message(teamId, roomId, id)),
      ]);
      if (!team || !room || !isMember(team, caller.uid) || !canReadRoom(team, caller.uid, room)) throw noRoom();
      if (!canPin(team, caller.uid, room)) throw denied("Only the team's chat managers unpin messages.");
      const pins = pinsOf(room);
      if (pins.includes(id)) tx.update(p.room(teamId, roomId), { pins: pins.filter((x) => x !== id) });
      if (message?.pinnedAt) tx.update(p.message(teamId, roomId, id), { pinnedAt: deleteField, pinnedBy: deleteField });
    });
  }

  /**
   * Posts a team event into a room as a card. The sharer must be able to
   * post in the room and create the team's events; the event must be this
   * team's, not over, and seen by everyone in the team.
   */
  async shareEvent(caller: Caller, rawTeam: unknown, rawRoom: unknown, body: unknown): Promise<SendChatMessageResult> {
    const teamId = docIdParam(rawTeam);
    const roomId = docIdParam(rawRoom);
    const req = parseBody(shareChatEventRequestSchema, body);
    const eventId = docIdParam(req.eventId);
    await checkNotMuted(this.store, caller.uid, this.now());
    const me = await authorOf(this.store, this.users, caller);
    const id = req.id ?? this.store.newId(`teams/${teamId}/chats/${roomId}/messages`);
    await this.store.transact(async (tx) => {
      const [team, room, event, existing] = await Promise.all([
        tx.get(p.team(teamId)),
        tx.get(p.room(teamId, roomId)),
        tx.get(p.event(teamId, eventId)),
        tx.get(p.message(teamId, roomId, id)),
      ]);
      if (!team || !room || !isMember(team, caller.uid) || !canReadRoom(team, caller.uid, room)) throw noRoom();
      if (!canWriteRoom(team, caller.uid, room)) throw denied("You can read this room but not post in it.");
      if (!can(team, caller.uid, "manageEvents")) throw denied("Only people who add the team's events share them in chat.");
      if (!event) throw new ApiError("not_found", "This event was deleted.");
      if (!sharedWithAll(team, event)) {
        throw new ApiError("failed_precondition", "Only events for everyone in the community can be shared in chat.");
      }
      const start = event.startsAt instanceof Date ? event.startsAt.getTime() : Number.NaN;
      const end = event.endsAt instanceof Date ? event.endsAt.getTime() : start + 2 * 3600_000;
      if (!Number.isNaN(end) && end < this.now()) throw new ApiError("failed_precondition", "That event is over.");
      if (existing) throw new ApiError("already_exists", "That message was already sent.");
      const title = clip(typeof event.title === "string" && event.title.trim() ? event.title.trim() : "Event", chatEventTitleMax);
      tx.create(p.message(teamId, roomId, id), {
        authorId: caller.uid,
        authorName: me.name,
        text: "",
        attachments: [],
        event: { id: eventId, title },
        createdAt: serverTime,
      });
      tx.update(p.room(teamId, roomId), { lastAt: serverTime });
      tx.merge(p.reads(caller.uid, teamId), { rooms: { [roomId]: serverTime } });
    });
    return { id };
  }

  /**
   * Posts a poll into a room (F33): anyone who can post there. Options are
   * voted on by index; nobody has voted yet.
   */
  async createPoll(caller: Caller, rawTeam: unknown, rawRoom: unknown, body: unknown): Promise<SendChatMessageResult> {
    const teamId = docIdParam(rawTeam);
    const roomId = docIdParam(rawRoom);
    const req = parseBody(createChatPollRequestSchema, body);
    const closesAt = req.closesAt ? new Date(req.closesAt) : null;
    if (closesAt && closesAt.getTime() <= this.now()) throw new ApiError("invalid_argument", "Pick a closing time in the future.");
    const lower = req.options.map((o) => o.toLowerCase());
    if (new Set(lower).size !== lower.length) throw new ApiError("invalid_argument", "Each option must be different.");
    await checkNotMuted(this.store, caller.uid, this.now());
    const me = await authorOf(this.store, this.users, caller);
    const id = req.id ?? this.store.newId(`teams/${teamId}/chats/${roomId}/messages`);
    await this.store.transact(async (tx) => {
      const [team, room, existing] = await Promise.all([
        tx.get(p.team(teamId)),
        tx.get(p.room(teamId, roomId)),
        tx.get(p.message(teamId, roomId, id)),
      ]);
      if (!team || !room || !isMember(team, caller.uid) || !canReadRoom(team, caller.uid, room)) throw noRoom();
      if (!canWriteRoom(team, caller.uid, room)) throw denied("You can read this room but not post in it.");
      if (existing) throw new ApiError("already_exists", "That message was already sent.");
      tx.create(p.message(teamId, roomId, id), {
        authorId: caller.uid,
        authorName: me.name,
        text: "",
        attachments: [],
        poll: { question: req.question, options: req.options, multiple: req.multiple, closesAt, votes: {}, voterIds: [] },
        createdAt: serverTime,
      });
      tx.update(p.room(teamId, roomId), { lastAt: serverTime });
      tx.merge(p.reads(caller.uid, teamId), { rooms: { [roomId]: serverTime } });
    });
    return { id };
  }

  /**
   * Sets the caller's whole choice on a poll ([] takes their vote back):
   * anyone who can read the room, while it's open. A single-choice poll
   * takes one option.
   */
  async vote(caller: Caller, rawTeam: unknown, rawRoom: unknown, rawMessage: unknown, body: unknown): Promise<void> {
    const teamId = docIdParam(rawTeam);
    const roomId = docIdParam(rawRoom);
    const id = docIdParam(rawMessage);
    const picks = [...new Set(parseBody(voteChatPollRequestSchema, body).options)].sort((a, b) => a - b);
    await this.store.transact(async (tx) => {
      const [team, room, message] = await Promise.all([
        tx.get(p.team(teamId)),
        tx.get(p.room(teamId, roomId)),
        tx.get(p.message(teamId, roomId, id)),
      ]);
      if (!team || !room || !isMember(team, caller.uid) || !canReadRoom(team, caller.uid, room)) throw noRoom();
      const poll = pollOf(message);
      if (!poll) throw noPoll();
      if (chatPollClosed(poll, this.now())) throw new ApiError("failed_precondition", "This poll is closed.");
      const options = Array.isArray(poll.options) ? poll.options.length : 0;
      if (picks.some((i) => i >= options)) throw new ApiError("invalid_argument", "That option isn't in this poll.");
      if (poll.multiple !== true && picks.length > 1) throw new ApiError("invalid_argument", "Pick one option.");
      const votes = votesOf(poll);
      if (picks.length === 0) delete votes[caller.uid];
      else votes[caller.uid] = picks;
      tx.update(p.message(teamId, roomId, id), { poll: { ...poll, votes, voterIds: Object.keys(votes) } });
    });
  }

  /** Closes a poll early: its author, or the room's chat managers. Closing a closed one is a no-op. */
  async closePoll(caller: Caller, rawTeam: unknown, rawRoom: unknown, rawMessage: unknown): Promise<void> {
    const teamId = docIdParam(rawTeam);
    const roomId = docIdParam(rawRoom);
    const id = docIdParam(rawMessage);
    await this.store.transact(async (tx) => {
      const [team, room, message] = await Promise.all([
        tx.get(p.team(teamId)),
        tx.get(p.room(teamId, roomId)),
        tx.get(p.message(teamId, roomId, id)),
      ]);
      if (!team || !room || !isMember(team, caller.uid) || !canReadRoom(team, caller.uid, room)) throw noRoom();
      const poll = pollOf(message);
      if (!poll) throw noPoll();
      if (message?.authorId !== caller.uid && !canPin(team, caller.uid, room)) {
        throw denied("Only whoever asked and the team's chat managers close a poll.");
      }
      if (chatPollClosed(poll, this.now())) return;
      tx.update(p.message(teamId, roomId, id), { poll: { ...poll, closedAt: serverTime, closedBy: caller.uid } });
    });
  }
}
