// The team and community hub's writes from the website (docs/product-spec.md
// §8.1, W2/W3): team posts, team events with RSVPs, reactions and polls,
// and team chat messages. Ports of the teams/{id}/posts, events, chats and
// messages rules in firestore.rules; the app still writes these directly.
import { z } from "zod";

// Team posts ---------------------------------------------------------------

/** Longest team post title, body and location (validPost). */
export const teamPostTitleMax = 100;
export const teamPostBodyMax = 5000;
export const teamPostLocationMax = 200;
/** Most links and photos on a team post (TeamPost.maxLinks / maxImages). */
export const teamPostLinksMax = 5;
export const teamPostImagesMax = 4;

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
  title: z.string().trim().max(teamPostTitleMax, `Keep the title under ${teamPostTitleMax} characters.`).default(""),
  body: z.string().max(teamPostBodyMax, `Keep posts under ${teamPostBodyMax} characters.`).default(""),
  location: z.string().trim().max(teamPostLocationMax, `Keep the place under ${teamPostLocationMax} characters.`).default(""),
  links: z.array(webLink).max(teamPostLinksMax, `Add at most ${teamPostLinksMax} links.`).default([]),
  public: z.boolean().default(false),
  uploadIds: z.array(z.string().min(1).max(128)).max(teamPostImagesMax, `Add at most ${teamPostImagesMax} photos.`).default([]),
  keepImages: z.array(z.string().max(1024)).max(teamPostImagesMax).optional(),
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
export const eventReactionEmoji: Record<EventReaction, string> = {
  thumbsUp: "👍",
  fire: "🔥",
  disc: "🥏",
  clap: "🙌",
  laugh: "😂",
  grimace: "😬",
};

const isoDate = z.string().refine((s) => !Number.isNaN(Date.parse(s)), "Give a date and time.");

/** validPoll: a question and 2–10 options, each with an id. */
export const eventPollSchema = z.strictObject({
  question: z.string().trim().min(1, "Ask a question.").max(200, "Keep the question under 200 characters."),
  options: z
    .array(
      z.strictObject({
        id: z.string().regex(/^[A-Za-z0-9_-]{1,40}$/, "Invalid option."),
        text: z.string().trim().min(1, "Fill in each option.").max(100, "Keep options under 100 characters."),
      }),
    )
    .min(2, "Give at least two options.")
    .max(10, "Give at most 10 options."),
  multiple: z.boolean().default(false),
});
export type EventPollInput = z.input<typeof eventPollSchema>;

/**
 * `POST /v1/teams/:teamId/events` and `PATCH .../events/:eventId`
 * (validEvent, and validAudience in a school or club community, where
 * [audience] is `everyone` or community role ids).
 */
export const saveTeamEventRequestSchema = z
  .strictObject({
    title: z.string().trim().min(1, "Give it a title.").max(100, "Keep the title under 100 characters."),
    type: z.enum(teamEventTypes).default("practice"),
    startsAt: isoDate,
    endsAt: isoDate.nullable().default(null),
    location: z.string().trim().max(200, "Keep the place under 200 characters.").default(""),
    notes: z.string().max(5000, "Keep notes under 5,000 characters.").default(""),
    poll: eventPollSchema.nullable().default(null),
    public: z.boolean().default(false),
    audience: z.array(z.string().min(1).max(64)).max(20, "Pick at most 20 roles.").optional(),
  })
  .refine((e) => !e.endsAt || Date.parse(e.endsAt) >= Date.parse(e.startsAt), {
    message: "It can't end before it starts.",
    path: ["endsAt"],
  });
export type SaveTeamEventRequest = z.input<typeof saveTeamEventRequestSchema>;

export interface SaveTeamEventResult {
  id: string;
}

/** `PUT .../events/:eventId/rsvp`: null takes the answer back. */
export const rsvpRequestSchema = z.strictObject({ status: z.enum(rsvpStatuses).nullable() });

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
  text: z.string().max(chatTextMax, `Keep messages under ${chatTextMax} characters.`).default(""),
  uploadIds: z.array(z.string().min(1).max(128)).max(chatAttachmentsMax).default([]),
  replyTo: z.string().min(1).max(128).optional(),
});
export type SendChatMessageRequest = z.input<typeof sendChatMessageRequestSchema>;

export interface SendChatMessageResult {
  id: string;
}

/** `PUT .../messages/:messageId/reaction`: one emoji per person, null clears it. */
export const chatReactionRequestSchema = z.strictObject({
  emoji: z.string().min(1).max(16).nullable(),
});

/** The emoji the website offers for chat reactions. */
export const chatReactionChoices = ["👍", "❤️", "😂", "🔥", "🥏", "👏", "😮", "😢"] as const;
