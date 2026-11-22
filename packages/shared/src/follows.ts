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

/**
 * A tournament follow key (`tournament_{hostId}_{tournamentId}`, also a
 * post's "At a tournament" tag) split into the host or group and the
 * tournament (FollowTarget.parseTournamentKey in the app). Ids never hold
 * "_", so the last one splits them. Null for anything else.
 */
export function parseTournamentKey(key: string | null | undefined): { hostId: string; tournamentId: string } | null {
  if (!key?.startsWith("tournament_")) return null;
  const rest = key.slice("tournament_".length);
  const at = rest.lastIndexOf("_");
  if (at <= 0 || at === rest.length - 1) return null;
  return { hostId: rest.slice(0, at), tournamentId: rest.slice(at + 1) };
}

/**
 * Where a tag opens: the hosted tournament's page, which falls back to the
 * group's tournament of that id (?host=), on both platforms.
 */
export function tournamentTagHref(key: string | null | undefined): string | null {
  const t = parseTournamentKey(key);
  return t ? `/tournaments/${encodeURIComponent(t.tournamentId)}?host=${encodeURIComponent(t.hostId)}` : null;
}

/** "At a tournament" lists tournaments from this many days before they start. */
export const tournamentTagDays = 7;
const dayMs = 24 * 60 * 60 * 1000;

/**
 * Whether a post may be tagged "At" a tournament now: from
 * [tournamentTagDays] days before it starts to the end of its last day
 * ([endsOn], else the day it starts). tournamentTagOpen in the app.
 */
export function tournamentTagOpen(startsOn: Date | string, endsOn: Date | string | null | undefined, now: Date): boolean {
  const start = new Date(startsOn).getTime();
  if (Number.isNaN(start)) return false;
  const endDay = endsOn ? new Date(endsOn).getTime() : Number.NaN;
  const last = Number.isNaN(endDay) ? start : Math.max(start, endDay);
  const t = now.getTime();
  return t >= start - tournamentTagDays * dayMs && t < last + dayMs;
}

/** `GET /v1/me/tag-tournaments`: the followed tournaments a post can be tagged with now, soonest first. */
export interface TagTournament {
  /** The follow key, as a post's tag stores it. */
  key: string;
  name: string;
  startsOn: string;
  endsOn: string | null;
}
export interface TagTournaments {
  tournaments: TagTournament[];
}
