// Team chat extras (redesign F2, F3): pinned messages and event cards in a
// team room. Both are API-only (firestore.rules never lets a client set
// these fields), so the app and the website write them through the API.
import { z } from "zod";

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
