import {
  type CommentResult,
  commentRequestSchema,
  editCommentRequestSchema,
  type LikeResult,
  type PostImage,
  postImagesMax,
  postReactionMax,
  repostId,
  type SavePostResult,
  savePostRequestSchema,
} from "@stall10/shared";
import type { Caller, UserLookup } from "../auth.js";
import { ApiError, fromZod } from "../errors.js";
import { docIdParam } from "../ids.js";
import type { MediaStorage } from "../media/storage.js";
import { type Data, type DocStore, serverTime } from "../store.js";
import { authorOf, checkNotMuted } from "./author.js";
import { noPost, people, validId } from "./service.js";

const p = {
  post: (id: string) => `posts/${id}`,
  comment: (postId: string, id: string) => `posts/${postId}/comments/${id}`,
  upload: (id: string) => `uploads/${id}`,
};

const noComment = () => new ApiError("not_found", "This comment was deleted.");

/** The post kinds a member edits (validUserPost's kinds). */
type Kind = "text" | "workout" | "event" | "repost";

function imagesOf(v: unknown): PostImage[] {
  if (!Array.isArray(v)) return [];
  return v.flatMap((i) =>
    i && typeof i === "object" && typeof (i as Data).path === "string"
      ? [
          {
            path: (i as Data).path as string,
            name: typeof (i as Data).name === "string" ? ((i as Data).name as string) : "",
            contentType:
              typeof (i as Data).contentType === "string" ? ((i as Data).contentType as string) : "image/jpeg",
            size: typeof (i as Data).size === "number" ? ((i as Data).size as number) : 0,
          },
        ]
      : [],
  );
}

/**
 * Writing players' posts (`posts/{id}`) and their comments from the website.
 * The Admin SDK skips firestore.rules, so this checks what the posts and
 * comments rules check: the author writes only as themselves, isn't muted,
 * a post has words or a photo (5,000 characters, 5 links, 4 photos), only
 * the author edits or deletes a post, and only text posts take new photos.
 * Photos come from the caller's finished `post` uploads for this post id,
 * never from paths the client names. Workout and event posts are still
 * made in the app; here their words, links and photos change.
 */
export class PostEditor {
  constructor(
    private readonly store: DocStore,
    private readonly users: UserLookup,
    private readonly media: MediaStorage | undefined,
    private readonly now: () => number = Date.now,
  ) {}

  /** The caller's finished photo uploads for post [postId], in order. */
  private async uploadedImages(caller: Caller, postId: string, ids: string[]): Promise<PostImage[]> {
    const unique = [...new Set(ids)];
    const uploads = await Promise.all(unique.map((id) => this.store.get(p.upload(docIdParam(id)))));
    return uploads.map((u, i) => {
      if (!u || u.uid !== caller.uid || u.purpose !== "post" || u.itemId !== postId) {
        throw new ApiError("invalid_argument", "That photo wasn't uploaded for this post.");
      }
      if (u.status !== "ready" || typeof u.path !== "string") {
        throw new ApiError("failed_precondition", "A photo is still being processed. Try again in a moment.");
      }
      const contentType = typeof u.contentType === "string" ? u.contentType : "image/jpeg";
      if (!contentType.startsWith("image/")) {
        throw new ApiError("invalid_argument", "Only photos can be added to posts here.");
      }
      return {
        path: u.path,
        name: u.path.split("/").pop() ?? unique[i]!,
        contentType,
        size: typeof u.actualSize === "number" ? u.actualSize : 0,
      };
    });
  }

  /** `POST /v1/posts`: a new text post by the caller. */
  async create(caller: Caller, body: unknown): Promise<SavePostResult> {
    const parsed = savePostRequestSchema.safeParse(body ?? {});
    if (!parsed.success) throw fromZod(parsed.error);
    const req = parsed.data;
    const id = req.id ?? this.store.newId("posts");
    if (id.startsWith("r_")) throw new ApiError("invalid_argument", "Invalid id.");
    await checkNotMuted(this.store, caller.uid, this.now());
    const images = await this.uploadedImages(caller, id, req.uploadIds);
    const words = req.body.trim();
    if (!words && images.length === 0) throw new ApiError("invalid_argument", "Write something or add a photo.");
    const me = await authorOf(this.store, this.users, caller);
    await this.store.transact(async (tx) => {
      if (await tx.get(p.post(id))) throw new ApiError("already_exists", "That post already exists.");
      tx.create(p.post(id), {
        kind: "text",
        body: words,
        links: req.links,
        images,
        workout: null,
        event: null,
        repostOf: null,
        tournamentKey: null,
        tournamentName: null,
        authorId: caller.uid,
        authorName: me.name,
        authorPhotoUrl: me.photoUrl,
        createdAt: serverTime,
        updatedAt: serverTime,
      });
    });
    return { id, images };
  }

  /** `PATCH /v1/posts/:id`: the author changes its words, links or photos. */
  async edit(caller: Caller, rawId: unknown, body: unknown): Promise<SavePostResult> {
    const id = docIdParam(rawId);
    const parsed = savePostRequestSchema.safeParse(body ?? {});
    if (!parsed.success) throw fromZod(parsed.error);
    const req = parsed.data;
    const current = await this.store.get(p.post(id));
    if (!current) throw noPost();
    if (current.authorId !== caller.uid) throw new ApiError("permission_denied", "Only its author can edit a post.");
    const kind = (current.kind as Kind) ?? "text";
    const before = imagesOf(current.images);
    const keep = req.keepImages ? before.filter((i) => req.keepImages!.includes(i.path)) : before;
    const added = kind === "repost" ? [] : await this.uploadedImages(caller, id, req.uploadIds);
    const images = [...keep, ...added];
    if (images.length > postImagesMax) {
      throw new ApiError("invalid_argument", `Add at most ${postImagesMax} photos.`);
    }
    const words = req.body.trim();
    if (kind === "repost") {
      if (req.links.length || req.uploadIds.length) {
        throw new ApiError("invalid_argument", "A repost only has a note.");
      }
    } else if (kind === "text" && !words && images.length === 0) {
      throw new ApiError("invalid_argument", "Write something or add a photo.");
    }
    const update: Data =
      kind === "repost" ? { body: words, updatedAt: serverTime } : { body: words, links: req.links, images, updatedAt: serverTime };
    await this.store.transact(async (tx) => {
      const now = await tx.get(p.post(id));
      if (!now || now.authorId !== caller.uid) throw noPost();
      tx.update(p.post(id), update);
    });
    const removed = before.filter((i) => !images.some((k) => k.path === i.path));
    await this.deleteFiles(caller.uid, id, removed);
    return { id, images: kind === "repost" ? [] : images };
  }

  /**
   * `DELETE /v1/posts/:id`: the author deletes it and its photos. Deleting a
   * repost also takes the caller off its original's repostedBy, as undoing
   * the repost does.
   */
  async delete(caller: Caller, rawId: unknown): Promise<void> {
    const id = docIdParam(rawId);
    const images = await this.store.transact(async (tx) => {
      const post = await tx.get(p.post(id));
      if (!post) return [];
      if (post.authorId !== caller.uid) throw new ApiError("permission_denied", "Only its author can delete a post.");
      const r = post.repostOf;
      const originalId = r && typeof r === "object" ? (r as Data).postId : null;
      const original =
        validId(originalId) && id === repostId(originalId, caller.uid) ? await tx.get(p.post(originalId)) : null;
      tx.delete(p.post(id));
      if (original && validId(originalId)) {
        const before = people(original.repostedBy);
        if (before.includes(caller.uid)) {
          tx.update(p.post(originalId), { repostedBy: before.filter((u) => u !== caller.uid) });
        }
      }
      return imagesOf(post.images);
    });
    await this.deleteFiles(caller.uid, id, images);
  }

  /**
   * Removes photos from Storage: only files in the author's folder for this
   * post, with the thumbnail the API made beside each one. Best effort; a
   * missing file isn't an error.
   */
  private async deleteFiles(uid: string, postId: string, images: PostImage[]) {
    if (!this.media || images.length === 0) return;
    const folder = `users/${uid}/posts/${postId}/`;
    const paths = images
      .map((i) => i.path)
      .filter((path) => path.startsWith(folder) && !path.includes(".."))
      .flatMap((path) => [path, path.replace(/\.(jpg|png)$/, "_thumb.jpg")]);
    const media = this.media;
    await Promise.all([...new Set(paths)].map((path) => media.delete(path).catch(() => undefined)));
  }

  // Comments ---------------------------------------------------------------

  /**
   * `POST /v1/posts/:id/comments`: a comment, or a reply. Replies are one
   * level deep: replying to a reply answers its top-level comment and says
   * whose reply it was (replyToName). A repost's comments go on its
   * original, so commenting on a repost is refused (the website comments
   * on the original instead).
   */
  async addComment(caller: Caller, rawPostId: unknown, body: unknown): Promise<CommentResult> {
    const postId = docIdParam(rawPostId);
    const parsed = commentRequestSchema.safeParse(body ?? {});
    if (!parsed.success) throw fromZod(parsed.error);
    await checkNotMuted(this.store, caller.uid, this.now());
    const me = await authorOf(this.store, this.users, caller);
    const id = this.store.newId(`posts/${postId}/comments`);
    await this.store.transact(async (tx) => {
      const post = await tx.get(p.post(postId));
      if (!post) throw noPost();
      if (post.repostOf) throw new ApiError("failed_precondition", "Comment on the original post.");
      let reply: Data = {};
      if (parsed.data.replyTo) {
        const to = await tx.get(p.comment(postId, parsed.data.replyTo));
        if (!to) throw noComment();
        const parentId = typeof to.parentId === "string" ? to.parentId : parsed.data.replyTo;
        if (parentId !== parsed.data.replyTo && !(await tx.get(p.comment(postId, parentId)))) throw noComment();
        reply = {
          parentId,
          ...(typeof to.parentId === "string" && { replyToName: String(to.authorName ?? "").substring(0, 80) }),
        };
      }
      tx.create(p.comment(postId, id), {
        body: parsed.data.body,
        authorId: caller.uid,
        authorName: me.name,
        authorPhotoUrl: me.photoUrl,
        createdAt: serverTime,
        ...reply,
      });
    });
    return { id };
  }

  /** `PATCH /v1/posts/:id/comments/:commentId`: its author rewrites it. */
  async editComment(caller: Caller, rawPostId: unknown, rawId: unknown, body: unknown): Promise<void> {
    const path = p.comment(docIdParam(rawPostId), docIdParam(rawId));
    const parsed = editCommentRequestSchema.safeParse(body ?? {});
    if (!parsed.success) throw fromZod(parsed.error);
    await this.store.transact(async (tx) => {
      const c = await tx.get(path);
      if (!c) throw noComment();
      if (c.authorId !== caller.uid) throw new ApiError("permission_denied", "Only its author can edit a comment.");
      tx.update(path, { body: parsed.data.body, editedAt: serverTime });
    });
  }

  /**
   * `DELETE /v1/posts/:id/comments/:commentId`: its author or the post's
   * author. The follows-commentCount function deletes its replies.
   */
  async deleteComment(caller: Caller, rawPostId: unknown, rawId: unknown): Promise<void> {
    const postId = docIdParam(rawPostId);
    const path = p.comment(postId, docIdParam(rawId));
    await this.store.transact(async (tx) => {
      const [c, post] = await Promise.all([tx.get(path), tx.get(p.post(postId))]);
      if (!c) return;
      if (c.authorId !== caller.uid && post?.authorId !== caller.uid) {
        throw new ApiError("permission_denied", "You can't delete this comment.");
      }
      tx.delete(path);
    });
  }

  /** `PUT|DELETE /v1/posts/:id/comments/:commentId/like`. */
  async setCommentLiked(caller: Caller, rawPostId: unknown, rawId: unknown, liked: boolean): Promise<LikeResult> {
    const path = p.comment(docIdParam(rawPostId), docIdParam(rawId));
    return this.store.transact(async (tx) => {
      const c = await tx.get(path);
      if (!c) throw noComment();
      const before = people(c.likedBy);
      if (before.includes(caller.uid) === liked) return { liked, likeCount: before.length };
      if (liked && before.length >= postReactionMax) {
        throw new ApiError("failed_precondition", "This comment can't take more likes.");
      }
      const after = liked ? [...before, caller.uid] : before.filter((u) => u !== caller.uid);
      tx.update(path, { likedBy: after });
      return { liked, likeCount: after.length };
    });
  }
}
