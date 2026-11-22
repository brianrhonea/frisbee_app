import {
  type LikeResult,
  type PostState,
  type PostStates,
  postReactionMax,
  postStateLimit,
  type RepostResult,
  repostId,
  repostRequestSchema,
} from "@stall10/shared";
import type { TagTournaments } from "@stall10/shared";
import type { Caller, UserLookup } from "../auth.js";
import { ApiError, fromZod } from "../errors.js";
import { docIdParam, isDocId } from "../ids.js";
import { type Data, type DocStore, serverTime, type Tx } from "../store.js";
import { authorOf, checkNotMuted, nameMax, text, checkSeesPost } from "./author.js";
import { clip } from "../teams/access.js";
import { refuseBlocked } from "../moderation/blocks.js";
import { tagTournaments } from "./tags.js";

const p = {
  post: (id: string) => `posts/${id}`,
};

export const people = (v: unknown): string[] =>
  Array.isArray(v) ? v.filter((x): x is string => typeof x === "string") : [];


export const noPost = () => new ApiError("not_found", "This post was deleted.");

/** A post and the one its likes and reposts count toward. */
interface Target {
  id: string;
  data: Data;
}

type Reader = Pick<Tx, "get">;

/**
 * Likes and reposts of players' posts (`posts/{id}`). The Admin SDK skips
 * firestore.rules, so this checks what the posts rule's like/repost update
 * and repost create check: anyone signed in adds or removes only
 * themselves, at most 20,000 a post; a repost is someone else's original
 * (never a repost), not muted, stored as `r_{original}_{uid}` and written
 * together with the original's repostedBy. Liking or reposting a repost
 * acts on its original, as the app's PostActions does. The repost document
 * has the fields the app writes (UserPost.repost + toEditableMap).
 */
export class PostService {
  constructor(
    private readonly store: DocStore,
    private readonly users: UserLookup,
    private readonly now: () => number = Date.now,
  ) {}

  /** `GET /v1/me/tag-tournaments`: what the composer's "At a tournament" offers. */
  async tagTournaments(caller: Caller): Promise<TagTournaments> {
    return tagTournaments(this.store, caller.uid, new Date(this.now()));
  }

  /** [id] itself, or its original when it's a repost. */
  private async target(tx: Reader, id: string): Promise<Target> {
    const data = await tx.get(p.post(id));
    if (!data) throw noPost();
    const r = data.repostOf;
    if (!r || typeof r !== "object") return { id, data };
    const originalId = (r as Data).postId;
    if (!isDocId(originalId)) throw noPost();
    const original = await tx.get(p.post(originalId));
    if (!original) throw noPost();
    return { id: originalId, data: original };
  }

  /** The caller may see [id] (a repost, maybe) and its target (S1). */
  private async checkSees(tx: Reader, uid: string, id: string, t: Target) {
    if (t.id !== id) {
      const repost = await tx.get(p.post(id));
      if (repost) await checkSeesPost(tx, uid, repost);
    }
    await checkSeesPost(tx, uid, t.data);
  }

  /** Likes the post (its original, for a repost), or takes the like back. */
  async setLiked(caller: Caller, rawId: unknown, liked: boolean): Promise<LikeResult> {
    const id = docIdParam(rawId);
    return this.store.transact(async (tx) => {
      const t = await this.target(tx, id);
      await this.checkSees(tx, caller.uid, id, t);
      if (liked) await refuseBlocked(tx, caller.uid, t.data.authorId);
      const before = people(t.data.likedBy);
      const had = before.includes(caller.uid);
      if (had === liked) return { liked, likeCount: before.length };
      if (liked && before.length >= postReactionMax) {
        throw new ApiError("failed_precondition", "This post can't take more likes.");
      }
      const after = liked ? [...before, caller.uid] : before.filter((u) => u !== caller.uid);
      tx.update(p.post(t.id), { likedBy: after });
      return { liked, likeCount: after.length };
    });
  }

  /** Reposts the post (its original, for a repost) with an optional note. Again is a no-op. */
  async repost(caller: Caller, rawId: unknown, body: unknown): Promise<RepostResult> {
    const id = docIdParam(rawId);
    const parsed = repostRequestSchema.safeParse(body ?? {});
    if (!parsed.success) throw fromZod(parsed.error);
    const note = parsed.data.note?.trim() ?? "";
    await checkNotMuted(this.store, caller.uid, this.now());
    const me = await authorOf(this.store, this.users, caller);
    return this.store.transact(async (tx) => {
      const t = await this.target(tx, id);
      await this.checkSees(tx, caller.uid, id, t);
      const authorId = t.data.authorId;
      if (typeof authorId !== "string" || !authorId) throw noPost();
      if (authorId === caller.uid) throw new ApiError("permission_denied", "You can't repost your own post.");
      await refuseBlocked(tx, caller.uid, authorId);
      // It would reach the reposter's followers (validRepost in the rules).
      if (t.data.private === true) {
        throw new ApiError("failed_precondition", "Posts from private profiles can't be reposted.");
      }
      const mine = p.post(repostId(t.id, caller.uid));
      const existing = await tx.get(mine);
      const before = people(t.data.repostedBy);
      if (existing) {
        // Already reposted; keep the count in step with the repost.
        if (!before.includes(caller.uid)) tx.update(p.post(t.id), { repostedBy: [...before, caller.uid] });
        return { reposted: true, repostCount: before.includes(caller.uid) ? before.length : before.length + 1 };
      }
      if (before.length >= postReactionMax) {
        throw new ApiError("failed_precondition", "This post can't take more reposts.");
      }
      tx.create(mine, {
        kind: "repost",
        body: note,
        links: [],
        images: [],
        workout: null,
        event: null,
        repostOf: { postId: t.id, authorId, authorName: clip(text(t.data.authorName), nameMax) },
        tournamentKey: null,
        tournamentName: null,
        authorId: caller.uid,
        authorName: me.name,
        authorPhotoUrl: me.photoUrl,
        private: me.private,
        createdAt: serverTime,
        updatedAt: serverTime,
      });
      const after = [...before.filter((u) => u !== caller.uid), caller.uid];
      tx.update(p.post(t.id), { repostedBy: after });
      return { reposted: true, repostCount: after.length };
    });
  }

  /**
   * Takes back the caller's repost of the post (or of its original): deletes
   * `r_{original}_{uid}` and removes them from repostedBy together. [rawId]
   * may be their repost itself, even once the original is gone.
   */
  async undoRepost(caller: Caller, rawId: unknown): Promise<RepostResult> {
    const id = docIdParam(rawId);
    return this.store.transact(async (tx) => {
      const data = await tx.get(p.post(id));
      if (!data) throw noPost();
      const r = data.repostOf;
      const originalId = r && typeof r === "object" ? (r as Data).postId : id;
      if (!isDocId(originalId)) throw noPost();
      const original = originalId === id ? data : await tx.get(p.post(originalId));
      const mine = p.post(repostId(originalId, caller.uid));
      const existing = mine === p.post(id) ? data : await tx.get(mine);
      if (existing && existing.authorId === caller.uid) tx.delete(mine);
      if (!original) return { reposted: false, repostCount: 0 };
      const before = people(original.repostedBy);
      const after = before.filter((u) => u !== caller.uid);
      if (after.length !== before.length) tx.update(p.post(originalId), { repostedBy: after });
      return { reposted: false, repostCount: after.length };
    });
  }

  /** The caller's likes and reposts of up to 50 posts (`ids`: comma-separated). */
  async states(caller: Caller, rawIds: unknown): Promise<PostStates> {
    const ids = [...new Set(typeof rawIds === "string" ? rawIds.split(",") : [])].filter(isDocId);
    if (ids.length > postStateLimit) {
      throw new ApiError("invalid_argument", `Ask about at most ${postStateLimit} posts at a time.`);
    }
    const reader: Reader = { get: (path) => this.store.get(path) };
    const found = await Promise.all(
      ids.map(async (id) => {
        try {
          return [id, await this.target(reader, id)] as const;
        } catch (e) {
          if (e instanceof ApiError && e.code === "not_found") return null;
          throw e;
        }
      }),
    );
    const out: PostStates = {};
    for (const entry of found) {
      if (!entry) continue;
      const [id, t] = entry;
      const liked = people(t.data.likedBy);
      const reposted = people(t.data.repostedBy);
      out[id] = {
        liked: liked.includes(caller.uid),
        reposted: reposted.includes(caller.uid),
        // Not a private profile's post (one reposted before can be taken back).
        canRepost: t.data.authorId !== caller.uid && (t.data.private !== true || reposted.includes(caller.uid)),
        likeCount: liked.length,
        repostCount: reposted.length,
      } satisfies PostState;
    }
    return out;
  }
}
