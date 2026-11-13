// Liking and reposting players' posts (`posts/{id}`) through the API, as
// the app's PostActions does: liking or reposting a repost acts on its
// original. Checks follow firestore.rules' posts rule.
import { z } from "zod";

/** Longest repost note (UserPost.body, validString(p.body, 5000)). */
export const repostNoteMax = 5000;

/** Most people a post lists in likedBy or repostedBy (the rule's cap). */
export const postReactionMax = 20000;

/** Most posts one `GET /v1/posts/state` asks about. */
export const postStateLimit = 50;

/** `PUT /v1/posts/:id/repost`: an optional note shown above the original. */
export const repostRequestSchema = z.object({
  note: z.string().max(repostNoteMax, `Keep the note under ${repostNoteMax} characters.`).optional(),
});
export type RepostRequest = z.infer<typeof repostRequestSchema>;

/** After `PUT|DELETE /v1/posts/:id/like`. */
export interface LikeResult {
  liked: boolean;
  likeCount: number;
}

/** After `PUT|DELETE /v1/posts/:id/repost`. */
export interface RepostResult {
  reposted: boolean;
  repostCount: number;
}

/**
 * The caller's view of one post's likes and reposts (its original's, for a
 * repost). `canRepost` is false for their own posts.
 */
export interface PostState {
  liked: boolean;
  reposted: boolean;
  canRepost: boolean;
  likeCount: number;
  repostCount: number;
}

/** `GET /v1/posts/state?ids=a,b`: by the ids asked about; missing posts are left out. */
export type PostStates = Record<string, PostState>;

/** A repost's document id: one per person per original (firestore.rules' repostPath). */
export const repostId = (originalId: string, uid: string) => `r_${originalId}_${uid}`;
