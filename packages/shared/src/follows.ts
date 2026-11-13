// Following players, teams and tournaments (users/{uid}/follows/{key},
// Follow in the app's lib/domain/models/follow.dart), follow requests for
// private profiles (profiles/{owner}/followRequests/{uid}), and the
// notification feed (users/{uid}/notifications). Checks follow
// firestore.rules' follows, followRequests and notifications rules.
import { z } from "zod";

export const followTypes = ["user", "team", "tournament"] as const;
export type FollowType = (typeof followTypes)[number];

/** A follow's document id: `{type}_{targetId}` (FollowTarget.key). */
export const followKey = (type: FollowType, targetId: string) => `${type}_${targetId}`;

/**
 * `PUT /v1/follows`: follow a player, team or group, or a tournament
 * ([groupId] its host, [targetId] the tournament id; stored as
 * `{groupId}_{tournamentId}`). The name and photo shown in the list come
 * from the target, not the caller.
 */
export const followRequestSchema = z.strictObject({
  type: z.enum(followTypes),
  targetId: z.string().regex(/^[A-Za-z0-9_-]{1,128}$/),
  groupId: z
    .string()
    .regex(/^[A-Za-z0-9_-]{1,128}$/)
    .optional(),
  notify: z.boolean().default(false),
});
export type FollowRequest = z.input<typeof followRequestSchema>;

/**
 * After `PUT /v1/follows`: `following`, or `requested` when the player's
 * profile is private and they have to accept first.
 */
export interface FollowResult {
  key: string;
  status: "following" | "requested";
}

/** `PATCH /v1/follows/:key`: post notifications for one follow. */
export const followNotifySchema = z.strictObject({ notify: z.boolean() });

/** Most notifications one `POST /v1/me/notifications/read` or delete touches. */
export const notificationBatchMax = 100;

/** `POST /v1/me/notifications/read` and `/delete`: the notifications by id (the page lists them). */
export const notificationIdsSchema = z.strictObject({
  ids: z
    .array(z.string().regex(/^[A-Za-z0-9_-]{1,128}$/))
    .min(1)
    .max(notificationBatchMax),
});
export type NotificationIds = z.input<typeof notificationIdsSchema>;
