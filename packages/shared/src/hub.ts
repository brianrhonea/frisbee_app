// The team and community hub's writes from the website (docs/product-spec.md
// §8.1, W2/W3): team posts, team events with RSVPs, reactions and polls,
// and team chat messages. Ports of the teams/{id}/posts, events, chats and
// messages rules in firestore.rules; the app still writes these directly.
import { repeatSchema } from "./recurrence.js";
import { z } from "zod";
import { clean } from "./word_filter.js";
import { isoDateTime } from "./dates.js";

// Team posts ---------------------------------------------------------------

/** Longest team post title, body and location (validPost). */
export const teamPostTitleMax = 100;
export const teamPostBodyMax = 5000;
export const teamPostLocationMax = 200;
/** Most links and photos on a team post (TeamPost.maxLinks / maxImages). */
export const teamPostLinksMax = 5;
export const teamPostImagesMax = 4;
/** Longest tournament key on a team post (validString(p.tournamentKey, 300)). */
export const teamPostTournamentKeyMax = 300;

/** A hosted or group tournament's follow key (FollowTarget.tournamentKey in the app). */
export const tournamentFollowKey = (hostId: string, tournamentId: string) => `tournament_${hostId}_${tournamentId}`;

const webLink = z
  .string()
  .trim()
  .max(500, "Keep links under 500 characters.")
  .regex(/^https?:\/\/\S+$/, "Links start with http:// or https://.");

/**
 * `POST /v1/teams/:teamId/posts` and `PATCH /v1/teams/:teamId/posts/:postId`.
 * [uploadIds] are finished `teamImage` uploads for this team and post id;
 * on an edit, [keepImages] lists the photo paths to keep (all when absent).
 */
export const saveTeamPostRequestSchema = z.strictObject({
  /** The id photos were uploaded under; a new one when absent. */
  id: z
    .string()
    .regex(/^[A-Za-z0-9]{1,40}$/, "Invalid id.")
    .optional(),
  title: clean(z.string().trim().max(teamPostTitleMax, `Keep the title under ${teamPostTitleMax} characters.`).default("")),
  body: clean(z.string().max(teamPostBodyMax, `Keep posts under ${teamPostBodyMax} characters.`).default("")),
  location: clean(z.string().trim().max(teamPostLocationMax, `Keep the place under ${teamPostLocationMax} characters.`).default("")),
  links: z.array(webLink).max(teamPostLinksMax, `Add at most ${teamPostLinksMax} links.`).default([]),
  public: z.boolean().default(false),
  uploadIds: z.array(z.string().min(1).max(128)).max(teamPostImagesMax, `Add at most ${teamPostImagesMax} photos.`).default([]),
  keepImages: z.array(z.string().max(1024)).max(teamPostImagesMax).optional(),
  /**
   * Ties the post to one of this team's tournaments or leagues (its follow
   * key, `tournament_{teamId}_{tournamentId}`), so the event's News tab and
   * followers show it (validPost). Left as it is on an edit when absent.
   */
  tournamentKey: z.string().max(teamPostTournamentKeyMax, "That tournament key is too long.").optional(),
});
export type SaveTeamPostRequest = z.input<typeof saveTeamPostRequestSchema>;

export interface SaveTeamPostResult {
  id: string;
}

// Team events --------------------------------------------------------------

/** EventType in the app (validEventDetails' list). */
export const teamEventTypes = ["practice", "game", "tournament", "scrimmage", "workout", "social", "other", "pickup"] as const;
export type TeamEventType = (typeof teamEventTypes)[number];
export const teamEventTypeLabels: Record<TeamEventType, string> = {
  practice: "Practice",
  game: "Game",
  tournament: "Tournament",
  scrimmage: "Scrimmage",
  workout: "Workout",
  social: "Social",
  other: "Other",
  pickup: "Pickup",
};

/** RsvpStatus in the app. */
export const rsvpStatuses = ["going", "maybe", "notGoing"] as const;
export type RsvpStatus = (typeof rsvpStatuses)[number];

/** Reaction in the app: who's going reacts with these. */
export const eventReactions = ["thumbsUp", "fire", "disc", "clap", "laugh", "grimace"] as const;
export type EventReaction = (typeof eventReactions)[number];

const isoDate = isoDateTime("Give a date and time.");

/** validPoll: a question and 2–10 options, each with an id. */
export const eventPollSchema = z.strictObject({
  question: clean(z.string().trim().min(1, "Ask a question.").max(200, "Keep the question under 200 characters.")),
  options: z
    .array(
      z.strictObject({
        id: z.string().regex(/^[A-Za-z0-9_-]{1,40}$/, "Invalid option."),
        text: clean(z.string().trim().min(1, "Fill in each option.").max(100, "Keep options under 100 characters.")),
      }),
    )
    .min(2, "Give at least two options.")
    .max(10, "Give at most 10 options."),
  multiple: z.boolean().default(false),
});

/**
 * `POST /v1/teams/:teamId/events` and `PATCH .../events/:eventId`
 * (validEvent, and validAudience in a school or club community, where
 * [audience] is `everyone` or community role ids).
 */
export const saveTeamEventRequestSchema = z
  .strictObject({
    /**
     * New events only (a replay of the same id is a 409, so the outbox can retry safely): the
     * event's id, or a series' (its events are `{id}_{index}`). The server mints one when absent.
     */
    id: z
      .string()
      .regex(/^[A-Za-z0-9]{1,40}$/, "Invalid id.")
      .optional(),
    title: clean(z.string().trim().min(1, "Give it a title.").max(100, "Keep the title under 100 characters.")),
    type: z.enum(teamEventTypes).default("practice"),
    startsAt: isoDate,
    endsAt: isoDate.nullable().default(null),
    location: clean(z.string().trim().max(200, "Keep the place under 200 characters.").default("")),
    notes: clean(z.string().max(5000, "Keep notes under 5,000 characters.").default("")),
    poll: eventPollSchema.nullable().default(null),
    public: z.boolean().default(false),
    audience: z.array(z.string().min(1).max(64)).max(20, "Pick at most 20 roles.").optional(),
    // New events only: write a series, at the same wall-clock time in [timeZone].
    repeat: repeatSchema.optional(),
    timeZone: z.string().min(1).max(64).optional(),
  })
  .refine((e) => !e.endsAt || Date.parse(e.endsAt) >= Date.parse(e.startsAt), {
    message: "It can't end before it starts.",
    path: ["endsAt"],
  })
  .refine((e) => !e.repeat || e.timeZone, { message: "Send the time zone with a repeat.", path: ["timeZone"] });
export type SaveTeamEventRequest = z.input<typeof saveTeamEventRequestSchema>;

export interface SaveTeamEventResult {
  id: string;
}

/** The longest note on an RSVP ("Late 15 min"), after [cleanRsvpNote]. */
export const rsvpNoteMax = 140;

/**
 * An RSVP note as stored: one line, without control characters (newlines
 * and tabs become spaces, the rest are dropped), runs of spaces squeezed
 * and trimmed. Empty means no note. The app's `cleanRsvpNote` matches.
 */
export function cleanRsvpNote(raw: string): string {
  return raw
    .replace(/[\t\n\r\p{Zl}\p{Zp}]+/gu, " ")
    .replace(/[\u0000-\u001f\u007f-\u009f]/g, "")
    .replace(/ {2,}/g, " ")
    .trim();
}

/**
 * The optional `note` on an RSVP (events and meetings): left out keeps the
 * one there, null or empty removes it. Taking the answer back removes it too.
 */
export const rsvpNoteSchema = z
  .string()
  .max(1000, `Keep the note under ${rsvpNoteMax} characters.`)
  .transform(cleanRsvpNote)
  .pipe(clean(z.string().max(rsvpNoteMax, `Keep the note under ${rsvpNoteMax} characters.`)))
  .nullable()
  .optional();

/**
 * A doc's `rsvpNotes` (uid → note) after [uid] answers: unchanged when
 * [note] is left out and they still have an answer; without theirs when
 * they took the answer back or [note] is null or empty (after
 * [rsvpNoteSchema]); otherwise with [note]. Other members' notes stay.
 */
export function nextRsvpNotes(
  current: unknown,
  uid: string,
  answered: boolean,
  note: string | null | undefined,
): Record<string, string> {
  const out: Record<string, string> = {};
  if (current && typeof current === "object") {
    for (const [k, v] of Object.entries(current as Record<string, unknown>)) if (typeof v === "string") out[k] = v;
  }
  if (!answered || note === null || note === "") delete out[uid];
  else if (note !== undefined) out[uid] = note;
  return out;
}

/**
 * `PUT .../events/:eventId/rsvp`: null takes the answer back (and its
 * note); [note] as in [rsvpNoteSchema], stored in the event's `rsvpNotes`.
 */
export const rsvpRequestSchema = z.strictObject({ status: z.enum(rsvpStatuses).nullable(), note: rsvpNoteSchema });

/** `PUT .../events/:eventId/reaction`. */
export const eventReactionRequestSchema = z.strictObject({ reaction: z.enum(eventReactions), on: z.boolean() });

/** `PUT .../events/:eventId/votes`: the poll options picked (none clears the vote). */
export const eventVotesRequestSchema = z.strictObject({
  optionIds: z.array(z.string().min(1).max(40)).max(10),
});

// Team chat ----------------------------------------------------------------

/** Longest chat message, and most attachments (the messages rule). */
export const chatTextMax = 4000;
export const chatAttachmentsMax = 10;

/**
 * `POST /v1/teams/:teamId/chats/:roomId/messages`. [uploadIds] are
 * finished `chat` uploads for this room, with [id] as their itemId;
 * [replyTo] names a message in the room, quoted by the server.
 */
export const sendChatMessageRequestSchema = z.strictObject({
  id: z
    .string()
    .regex(/^[A-Za-z0-9]{1,40}$/, "Invalid id.")
    .optional(),
  text: clean(z.string().max(chatTextMax, `Keep messages under ${chatTextMax} characters.`).default("")),
  uploadIds: z.array(z.string().min(1).max(128)).max(chatAttachmentsMax).default([]),
  replyTo: z.string().min(1).max(128).optional(),
});

export interface SendChatMessageResult {
  id: string;
}

/** `PUT .../messages/:messageId/reaction`: one emoji per person, null clears it. */
export const chatReactionRequestSchema = z.strictObject({
  emoji: z.string().min(1).max(16).nullable(),
});


// ---- Chat rooms and folders (teams/{id}/chats, chatFolders) ---------------

/** Rules limits (validChatName, validAccess). */
export const chatRoomLimits = { name: 60, roles: 60, users: 200, folderId: 40, rooms: 200, folders: 50 } as const;

const audienceId = z.string().min(1).max(64).regex(/^[^/]+$/, "Invalid role.");
/** A folder id: one path segment, and not one Firestore reserves. */
const folderIdSchema = z
  .string()
  .min(1)
  .max(chatRoomLimits.folderId)
  .regex(/^[^/]+$/)
  .refine((v) => v !== "." && v !== ".." && !/^__.*__$/.test(v), "Invalid folder.");
const memberId = z.string().min(1).max(128).regex(/^[^/]+$/, "Invalid member.");

/**
 * Who reads and who writes a room or folder: "everyone", tiers and custom
 * role ids, and single members. Writers must also be readers.
 */
export const chatAccessSchema = z
  .strictObject({
    readRoles: z.array(audienceId).max(chatRoomLimits.roles),
    writeRoles: z.array(audienceId).max(chatRoomLimits.roles),
    readUsers: z.array(memberId).max(chatRoomLimits.users).default([]),
    writeUsers: z.array(memberId).max(chatRoomLimits.users).default([]),
  })
  .refine((a) => a.writeRoles.every((r) => a.readRoles.includes(r)) && a.writeUsers.every((u) => a.readUsers.includes(u)), {
    message: "Anyone who can write must also be able to read.",
  });

const chatName = clean(z.string().trim().min(1, "Name it.").max(chatRoomLimits.name));

/** `POST /v1/teams/:teamId/chat-rooms` and `PATCH .../chat-rooms/:roomId` (kind is set once). */
export const saveChatRoomRequestSchema = z.strictObject({
  name: chatName,
  kind: z.enum(["text", "voice"]).default("text"),
  folderId: folderIdSchema.nullable().default(null),
  access: chatAccessSchema,
});
export type SaveChatRoomRequest = z.input<typeof saveChatRoomRequestSchema>;

/** `POST /v1/teams/:teamId/chat-folders` and `PATCH .../chat-folders/:folderId`. */
export const saveChatFolderRequestSchema = z.strictObject({ name: chatName, access: chatAccessSchema });

/** `PUT /v1/teams/:teamId/chat-layout`: folder and room order, and which folder each room is in. */
export const chatLayoutRequestSchema = z.strictObject({
  folders: z.array(z.strictObject({ id: memberId, position: z.number().int().min(0).max(10_000) })).max(chatRoomLimits.folders).default([]),
  rooms: z
    .array(
      z.strictObject({
        id: memberId,
        position: z.number().int().min(0).max(10_000),
        folderId: folderIdSchema.nullable(),
      }),
    )
    .max(chatRoomLimits.rooms)
    .default([]),
});
