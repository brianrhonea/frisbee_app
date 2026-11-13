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

// Writing posts and comments ---------------------------------------------
// The posts rule's validUserPost and the comments rule: what a member writes
// from the website (the app still writes directly until it switches).

/** Longest post body (validString(p.body, 5000)). */
export const postBodyMax = 5000;
/** Most links and photos on a post (UserPost.maxLinks / maxImages). */
export const postLinksMax = 5;
export const postImagesMax = 4;
/** Longest link (validLink). */
export const postLinkMax = 500;
/** Longest comment (validString(body, 1000)). */
export const commentBodyMax = 1000;

/** A photo on a post, as stored (ChatAttachment in the app). */
export interface PostImage {
  path: string;
  name: string;
  contentType: string;
  size: number;
}

const link = z
  .string()
  .trim()
  .max(postLinkMax, `Keep links under ${postLinkMax} characters.`)
  .regex(/^https?:\/\/.+/, "Links start with http:// or https://.");

/**
 * `POST /v1/posts` (a new text post) and `PATCH /v1/posts/:id` (the author
 * edits it). [uploadIds] are finished `post` uploads (`/v1/uploads`, with
 * this post's id as itemId) to add; on an edit, [keepImages] lists the
 * paths of the photos to keep (the rest are deleted). A post needs words
 * or a photo. Workout, event and repost posts only change their words.
 */
export const savePostRequestSchema = z.strictObject({
  /** For a new post: the id the photos were uploaded under (optional otherwise). */
  id: z
    .string()
    .regex(/^[A-Za-z0-9_-]{1,128}$/)
    .optional(),
  body: z.string().max(postBodyMax, `Keep posts under ${postBodyMax} characters.`).default(""),
  links: z.array(link).max(postLinksMax, `Add at most ${postLinksMax} links.`).default([]),
  uploadIds: z
    .array(z.string().regex(/^[A-Za-z0-9_-]{1,128}$/))
    .max(postImagesMax)
    .default([]),
  keepImages: z.array(z.string().max(1024)).max(postImagesMax).optional(),
});
export type SavePostRequest = z.input<typeof savePostRequestSchema>;

/** After `POST /v1/posts` or `PATCH /v1/posts/:id`. */
export interface SavePostResult {
  id: string;
  images: PostImage[];
}

/** `POST /v1/posts/:id/comments`: a comment, or a reply to [replyTo] (a comment id). */
export const commentRequestSchema = z.strictObject({
  body: z
    .string()
    .trim()
    .min(1, "Write something first.")
    .max(commentBodyMax, `Keep comments under ${commentBodyMax} characters.`),
  replyTo: z
    .string()
    .regex(/^[A-Za-z0-9_-]{1,128}$/)
    .optional(),
});
export type CommentRequest = z.input<typeof commentRequestSchema>;

/** `PATCH /v1/posts/:id/comments/:commentId`: its author rewrites it. */
export const editCommentRequestSchema = commentRequestSchema.pick({ body: true });
export type EditCommentRequest = z.input<typeof editCommentRequestSchema>;

/** After `POST /v1/posts/:id/comments`. */
export interface CommentResult {
  id: string;
}
