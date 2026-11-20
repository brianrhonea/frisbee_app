// Team chat extras (redesign F2, F3, F33): pinned messages, event cards and polls in a
// team room. All are API-only (firestore.rules never lets a client set
// these fields), so the app and the website write them through the API.
import { z } from "zod";
import { isoDateTime } from "./dates.js";

// ---- Pins (F2) ----------------------------------------------------------------
//
// A pinned message carries `pinnedAt` and `pinnedBy`; the room keeps the
// ids in `pins` (ids only: chat managers read rooms' docs even when they
// can't read the messages) so the API can hold the limit. Clients list a
// room's pins with a query on its messages (orderBy pinnedAt desc, limit
// pinsMax), so a deleted message's pin goes with it.

/** Most pinned messages in one room. */
export const chatPinsMax = 10;

/**
 * `PUT /v1/teams/:teamId/chats/:roomId/messages/:messageId/pin`. With a
 * full room, [unpin] names the pin to take down in the same write;
 * without it the API answers failed_precondition ([chatPinsFullMessage]).
 * `DELETE` on the same path unpins.
 */
export const pinChatMessageRequestSchema = z.strictObject({
  unpin: z.string().min(1).max(128).optional(),
});

export const chatPinsFullMessage = `This room has ${chatPinsMax} pinned messages. Unpin one first.`;

// ---- Event cards (F3) -----------------------------------------------------------
//
// A message that shares a team event carries `event: { id, title }`: the
// title as it was when shared, for the push ("<name> shared an event:
// <title>") and previews. The card itself reads the live event, and says
// "Event no longer available" when it's gone or the reader can't see it.

/** `POST /v1/teams/:teamId/chats/:roomId/event-shares`: posts [eventId] as a card. */
export const shareChatEventRequestSchema = z.strictObject({
  id: z
    .string()
    .regex(/^[A-Za-z0-9]{1,40}$/, "Invalid id.")
    .optional(),
  eventId: z.string().min(1).max(128),
});

/** The event a chat message carries (ChatEventRef in the app). */
export interface ChatEventRef {
  id: string;
  title: string;
}

/** Longest title kept on the message. */
export const chatEventTitleMax = 200;

/** One line for a shared event: pushes, previews and quotes. */
export const sharedEventLine = (author: string, title: string) => `${author || "Someone"} shared an event: ${title || "Event"}`;

/** A message's preview when it has no text: the event it shares ("📅 Title"). */
export const sharedEventPreview = (title: string) => `📅 ${title || "Event"}`;

// ---- Polls (F33) ------------------------------------------------------------------
//
// A standalone poll posted into a team room: a message with `text: ""`,
// `attachments: []` and
//   poll: { question, options: string[], multiple, closesAt: Date | null,
//           votes: { [uid]: number[] }, voterIds: string[],
//           closedAt?, closedBy? }
// Options are referred to by their index (they never change). `voterIds`
// mirrors the keys of `votes` so a room's polls someone voted in can be
// found with one array-contains query (data export, account deletion).
// Votes are on the message, so everyone who reads the room sees who
// voted for what: polls aren't anonymous. Deleting the message deletes
// the poll. Only the API writes `poll`.

/** Longest question, and longest option. */
export const chatPollQuestionMax = 200;
export const chatPollOptionMax = 80;
/** Fewest and most options. */
export const chatPollOptionsMin = 2;
export const chatPollOptionsMax = 6;

/** `POST /v1/teams/:teamId/chats/:roomId/polls`: posts a poll. */
export const createChatPollRequestSchema = z.strictObject({
  id: z
    .string()
    .regex(/^[A-Za-z0-9]{1,40}$/, "Invalid id.")
    .optional(),
  question: z.string().trim().min(1, "Ask a question.").max(chatPollQuestionMax),
  options: z
    .array(z.string().trim().min(1, "Fill in every option, or remove it.").max(chatPollOptionMax))
    .min(chatPollOptionsMin, `Give at least ${chatPollOptionsMin} options.`)
    .max(chatPollOptionsMax, `At most ${chatPollOptionsMax} options.`),
  multiple: z.boolean().default(false),
  /** When voting stops (ISO 8601); must be in the future. None: open until closed. */
  closesAt: isoDateTime("Pick when the poll closes.").nullable().optional(),
});
export type CreateChatPollRequest = z.input<typeof createChatPollRequestSchema>;

/**
 * `PUT /v1/teams/:teamId/chats/:roomId/messages/:messageId/vote`: the
 * caller's whole choice (option indexes); `[]` takes the vote back. A
 * single-choice poll takes one.
 */
export const voteChatPollRequestSchema = z.strictObject({
  options: z.array(z.number().int().min(0).max(chatPollOptionsMax - 1)).max(chatPollOptionsMax),
});

/** A poll as stored on its message (ChatPoll in the app). Dates as clients read them. */
export interface ChatPoll<D = string> {
  question: string;
  options: string[];
  multiple: boolean;
  closesAt?: D | null;
  closedAt?: D | null;
  closedBy?: string | null;
  votes?: Record<string, number[]>;
  voterIds?: string[];
}

/** Whether [poll] takes no more votes at [now] (ms): closed early, or past closesAt. */
export function chatPollClosed(poll: { closesAt?: unknown; closedAt?: unknown }, now: number): boolean {
  const ms = (v: unknown) => (v instanceof Date ? v.getTime() : typeof v === "string" ? Date.parse(v) : Number.NaN);
  if (poll.closedAt != null && !Number.isNaN(ms(poll.closedAt))) return true;
  const end = ms(poll.closesAt);
  return !Number.isNaN(end) && end <= now;
}

/** Votes per option and how many people voted. */
export function chatPollTally(poll: { options: string[]; votes?: Record<string, number[]> }): { counts: number[]; voters: number } {
  const counts = poll.options.map(() => 0);
  let voters = 0;
  for (const picks of Object.values(poll.votes ?? {})) {
    if (!Array.isArray(picks) || picks.length === 0) continue;
    voters++;
    for (const i of new Set(picks)) if (Number.isInteger(i) && i >= 0 && i < counts.length) counts[i]++;
  }
  return { counts, voters };
}

/**
 * The choice after tapping option [i] with [mine] chosen: tapping a chosen
 * option takes it back; on a single-choice poll another replaces it.
 */
export function chatPollToggle(mine: readonly number[], i: number, multiple: boolean): number[] {
  if (mine.includes(i)) return mine.filter((x) => x !== i);
  return multiple ? [...mine, i].sort((a, b) => a - b) : [i];
}

/** One line for a poll: pushes ("<name> posted a poll: <question>"). */
export const chatPollLine = (author: string, question: string) => `${author || "Someone"} posted a poll: ${question || "Poll"}`;

/** A message's preview when it carries a poll ("📊 Question"). */
export const chatPollPreview = (question: string) => `📊 ${question || "Poll"}`;
