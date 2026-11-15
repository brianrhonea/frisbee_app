// The member's own account: name and pictures, and notification settings
// (users/{uid}/settings/notifications, NotificationPreferences in the app).
import { z } from "zod";
import { profileLimits } from "./profile.js";

const uploadId = z.string().regex(/^[A-Za-z0-9_-]{1,128}$/);

/**
 * `PUT /v1/me/identity`: the name everyone sees, the profile picture and
 * the header photo. Pictures are the caller's finished `avatar` uploads;
 * null removes one; a field left out stays as it is.
 */
export const identityRequestSchema = z
  .strictObject({
    name: z.string().trim().min(1, "Enter your name.").max(profileLimits.name).optional(),
    photoUploadId: uploadId.nullable().optional(),
    headerUploadId: uploadId.nullable().optional(),
  })
  .refine((b) => b.name !== undefined || b.photoUploadId !== undefined || b.headerUploadId !== undefined, {
    message: "Nothing to change.",
  });

/** What `PUT /v1/me/identity` answers: the profile's name and picture URLs now. */
export interface IdentityResult {
  name: string;
  photoUrl: string | null;
  headerUrl: string | null;
}

/** `PUT /v1/me/read-receipts`: whether others see when the caller has read their messages. */
export const readReceiptsRequestSchema = z.strictObject({ on: z.boolean() });

/** Notification kinds (NotificationCategory in the app), in the app's order. */
export const notificationCategories = [
  "chat",
  "directMessages",
  "eventChanges",
  "eventReminders",
  "teamActivity",
  "meetings",
  "posts",
  "social",
] as const;
export type NotificationCategory = (typeof notificationCategories)[number];

export const notificationCategoryInfo: Record<NotificationCategory, { label: string; description: string; perTeam: boolean }> = {
  chat: { label: "Team chat", description: "New messages in team chat rooms you can read", perTeam: true },
  directMessages: { label: "Direct messages", description: "New private messages", perTeam: false },
  eventChanges: { label: "Event changes", description: "Team events added, changed or cancelled", perTeam: true },
  eventReminders: { label: "Event reminders", description: "A reminder a day before each team or personal event", perTeam: true },
  teamActivity: { label: "Team activity", description: "New and updated plays, and requests to join your groups", perTeam: true },
  meetings: { label: "Meetings", description: "Meeting invites, and when a meeting you're attending starts", perTeam: true },
  posts: {
    label: "Posts you follow",
    description: "New posts from people, teams and tournaments you turned on post notifications for",
    perTeam: true,
  },
  social: { label: "Likes, reposts and followers", description: "When someone likes or reposts your post, or starts following you", perTeam: false },
};

const docId = z.string().regex(/^[A-Za-z0-9_-]{1,128}$/);

/**
 * `PUT /v1/me/notification-settings/category`: turns a kind on or off for
 * every team, or (with [teamId], per-team kinds only) for one team.
 */
export const notificationCategoryRequestSchema = z
  .strictObject({ category: z.enum(notificationCategories), on: z.boolean(), teamId: docId.optional() })
  .refine((b) => !b.teamId || notificationCategoryInfo[b.category].perTeam, {
    message: "That kind of notification isn't set per team.",
    path: ["teamId"],
  });

/** `PUT /v1/me/notification-settings/mute`: silences one team chat room or one conversation. */
export const notificationMuteRequestSchema = z
  .strictObject({ teamId: docId.optional(), roomId: docId.optional(), conversationId: docId.optional(), muted: z.boolean() })
  .refine((b) => (b.conversationId ? !b.teamId && !b.roomId : Boolean(b.teamId && b.roomId)), {
    message: "Say which chat room or conversation.",
  });

/** A muted room's entry in `mutedRooms` (NotificationPreferences.roomKey / conversationKey). */
export const mutedRoomKey = (teamId: string, roomId: string) => `${teamId}/${roomId}`;
export const mutedConversationKey = (conversationId: string) => `dm/${conversationId}`;
