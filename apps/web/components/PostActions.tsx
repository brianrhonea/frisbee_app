"use client";
import {
  type LikeResult,
  type PostState,
  type PublicPost,
  type RepostResult,
  repostNoteMax,
} from "@stall10/shared";
import Link from "next/link";
import { useEffect, useState } from "react";
import { ApiError, callApi } from "@/lib/client";
import { postState } from "@/lib/postState";
import { useAuth } from "./AuthProvider";
import { postUrl, ShareButton } from "./ShareButton";

const plural = (n: number, one: string, many: string) => `${n} ${n === 1 ? one : many}`;
const problem = (e: unknown) => (e instanceof ApiError ? e.message : "Something went wrong. Try again.");

/**
 * A post's likes, reposts and comments. Members like and repost here (a
 * repost's go to its original, as in the app) and open the comments with
 * [onComment]; visitors are asked to sign up.
 */
export function PostActions({ post, onComment }: { post: PublicPost; onComment?: () => void }) {
  const { user } = useAuth();
  // What likes and reposts count toward: the post, or a repost's original.
  const target = post.repostOf ? post.original : post;
  const [state, setState] = useState<PostState | null>(null);
  const [busy, setBusy] = useState(false);
  const [composing, setComposing] = useState(false);
  const [note, setNote] = useState("");
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!user || !target) return;
    let live = true;
    postState(user, post.id).then(
      (s) => live && s && setState(s),
      () => live && setError("Couldn't load your likes. Refresh to try again."),
    );
    return () => {
      live = false;
    };
  }, [user, post.id, target]);

  if (!target) return null;
  const likeCount = state?.likeCount ?? target.likeCount;
  const repostCount = state?.repostCount ?? target.repostCount;
  const comments = target.commentCount ? <span>{plural(target.commentCount, "comment", "comments")}</span> : null;

  if (!user) {
    return (
      <footer className="post-counts">
        <span>{plural(likeCount, "like", "likes")}</span>
        <span>{plural(repostCount, "repost", "reposts")}</span>
        {comments}
        <ShareButton url={postUrl(post.id)} />
        {user === null && (
          <Link className="post-join" href="/sign-up">
            Sign up to like and reply
          </Link>
        )}
      </footer>
    );
  }

  async function toggleLike() {
    if (!user || !state) return;
    const liked = !state.liked;
    const before = state;
    setError(null);
    setState({ ...state, liked, likeCount: state.likeCount + (liked ? 1 : -1) });
    try {
      const r = await callApi<LikeResult>(user, `/v1/posts/${encodeURIComponent(post.id)}/like`, {
        method: liked ? "PUT" : "DELETE",
      });
      setState((s) => (s ? { ...s, ...r } : s));
    } catch (e) {
      setState(before);
      setError(problem(e));
    }
  }

  async function repost(undo: boolean) {
    if (!user || !state) return;
    setBusy(true);
    setError(null);
    try {
      const r = await callApi<RepostResult>(user, `/v1/posts/${encodeURIComponent(post.id)}/repost`, {
        method: undo ? "DELETE" : "PUT",
        body: undo ? undefined : { note },
      });
      setState((s) => (s ? { ...s, ...r } : s));
      setComposing(false);
      setNote("");
    } catch (e) {
      setError(problem(e));
    } finally {
      setBusy(false);
    }
  }

  const ready = state !== null && !busy;
  const liked = state?.liked ?? false;
  const reposted = state?.reposted ?? false;
  return (
    <>
      <footer className="post-counts post-actions">
        <button
          type="button"
          className={`post-action${liked ? " on" : ""}`}
          aria-pressed={liked}
          disabled={!state}
          onClick={() => void toggleLike()}
        >
          <span aria-hidden="true">{liked ? "♥" : "♡"}</span> {plural(likeCount, "like", "likes")}
        </button>
        {state && !state.canRepost ? (
          <span>{plural(repostCount, "repost", "reposts")}</span>
        ) : (
          <button
            type="button"
            className={`post-action${reposted ? " on" : ""}`}
            aria-pressed={reposted}
            title={reposted ? "Undo your repost" : "Repost to your followers"}
            disabled={!ready}
            onClick={() => (reposted ? void repost(true) : setComposing((c) => !c))}
          >
            <span aria-hidden="true">↻</span> {plural(repostCount, "repost", "reposts")}
          </button>
        )}
        {onComment ? (
          <button type="button" className="post-action" onClick={onComment}>
            <span aria-hidden="true">💬</span> {plural(target.commentCount ?? 0, "comment", "comments")}
          </button>
        ) : (
          comments
        )}
        <ShareButton url={postUrl(post.id)} />
      </footer>
      {composing && !reposted && (
        <form
          className="repost-form"
          onSubmit={(e) => {
            e.preventDefault();
            void repost(false);
          }}
        >
          <label htmlFor={`note-${post.id}`}>Repost to your followers</label>
          <textarea
            id={`note-${post.id}`}
            value={note}
            maxLength={repostNoteMax}
            rows={2}
            placeholder="Add a note (optional)"
            onChange={(e) => setNote(e.target.value)}
          />
          <div className="repost-buttons">
            <button className="btn btn-small" type="button" onClick={() => setComposing(false)}>
              Cancel
            </button>
            <button className="btn btn-primary btn-small" type="submit" disabled={!ready}>
              {busy ? "Reposting…" : "Repost"}
            </button>
          </div>
        </form>
      )}
      {error && (
        <p className="post-error" role="alert">
          {error}
        </p>
      )}
    </>
  );
}
