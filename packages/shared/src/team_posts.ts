// Team feed extras (redesign F24): pinned team posts and comments on team
// posts. API-only: firestore.rules lets no client set a team post's
// pinnedAt, pinnedBy or commentCount, nor create a comment, so the app and
// the website write them through the API.
import { z } from "zod";
import { clean } from "./word_filter.js";

// ---- Pins ---------------------------------------------------------------------
//
// A pinned post carries `pinnedAt` and `pinnedBy`. The API keeps the
// pinned ids in `teams/{id}/feed/pins` (`ids`, server-only) to hold the
// limit. Clients list a team's pins with a query on its posts (orderBy
// pinnedAt desc, limit teamPostPinsMax; non-members add public == true), so
// a deleted post's pin goes with it.

/** Most pinned posts on one team's feed. */
export const teamPostPinsMax = 3;

/**
 * `PUT /v1/teams/:teamId/posts/:postId/pin`. With a full feed, [unpin]
 * names the pinned post to take down in the same write; without it the
 * API answers failed_precondition ([teamPostPinsFullMessage]). `DELETE`
 * on the same path unpins.
 */
export const pinTeamPostRequestSchema = z.strictObject({
  unpin: z.string().min(1).max(128).optional(),
});

export const teamPostPinsFullMessage = `This team has ${teamPostPinsMax} pinned posts. Unpin one first.`;

/** What a feed post needs for ordering. */
export interface FeedPostOrder {
  id: string;
  /** ISO time, or a Date as the browser's live reads give it. */
  pinnedAt?: string | Date | null;
  createdAt?: string | Date | null;
}

const ms = (v: string | Date | null | undefined, missing: number) =>
  v == null ? missing : v instanceof Date ? v.getTime() : Number.isNaN(Date.parse(v)) ? missing : Date.parse(v);

/** Whether [post] is pinned (has a pinnedAt). */
export const isPinnedPost = (post: FeedPostOrder) => post.pinnedAt != null;

/**
 * A team feed in order: the pinned posts first, newest pin first (at most
 * teamPostPinsMax), then the rest newest first. [pinned] and [recent] may
 * overlap (a pinned post that's also among the newest); each post shows
 * once. A post in [pinned] that no longer has pinnedAt drops to the rest.
 */
export function arrangeTeamFeed<T extends FeedPostOrder>(pinned: readonly T[], recent: readonly T[]): { pinned: T[]; rest: T[] } {
  const byId = new Map<string, T>();
  // The newer read of a post wins: `recent` is the main listener.
  for (const p of [...pinned, ...recent]) byId.set(p.id, p);
  const all = [...byId.values()];
  const now = Number.MAX_SAFE_INTEGER;
  const top = all
    .filter(isPinnedPost)
    .sort((a, b) => ms(b.pinnedAt, now) - ms(a.pinnedAt, now))
    .slice(0, teamPostPinsMax);
  const topIds = new Set(top.map((p) => p.id));
  const rest = all.filter((p) => !topIds.has(p.id)).sort((a, b) => ms(b.createdAt, now) - ms(a.createdAt, now));
  return { pinned: top, rest };
}

// ---- Comments -----------------------------------------------------------------
//
// teams/{id}/posts/{postId}/comments/{commentId}: `authorId`, `authorName`,
// `body`, `createdAt`. A flat thread, oldest first; members read and write
// (through the API), the author or a team admin (manageTeam) deletes. The
// post's `commentCount` is kept by the `follows-teamPostCommentCount`
// function (missing reads as 0).

export const teamPostCommentLimits = {
  body: 1000,
  authorName: 80,
  /** Most comments a post's thread shows (the newest, oldest first). */
  shown: 100,
} as const;

/** `POST /v1/teams/:teamId/posts/:postId/comments`. */
export const teamPostCommentRequestSchema = z.strictObject({
  body: clean(
    z
      .string()
      .trim()
      .min(1, "Write a comment first.")
      .max(teamPostCommentLimits.body, `Keep it under ${teamPostCommentLimits.body} characters.`),
  ),
});
export type TeamPostCommentRequest = z.infer<typeof teamPostCommentRequestSchema>;

/** "Comment", "1 comment", "4 comments" (a missing or bad count is 0). */
export function teamPostCommentLabel(count: unknown): string {
  const n = typeof count === "number" && Number.isFinite(count) && count > 0 ? Math.floor(count) : 0;
  return n === 0 ? "Comment" : n === 1 ? "1 comment" : `${n} comments`;
}
