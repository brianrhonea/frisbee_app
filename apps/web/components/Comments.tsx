"use client";
import { commentBodyMax, type CommentResult, type LikeResult } from "@stall10/shared";
import { limit, orderBy } from "firebase/firestore";
import Link from "next/link";
import { type FormEvent, useRef, useState } from "react";
import { ApiError, callApi } from "@/lib/client";
import { type Doc, useLiveQuery } from "@/lib/live";
import { useAuth } from "./AuthProvider";
import { Avatar } from "./Avatar";
import { LocalTime } from "./LocalTime";

/** A comment as stored (PostComment in the app). */
interface Comment {
  body: string;
  authorId: string;
  authorName?: string;
  authorPhotoUrl?: string | null;
  createdAt?: string;
  editedAt?: string;
  parentId?: string;
  replyToName?: string;
  likedBy?: string[];
}

/** The most comments a post shows (oldest first). */
const shown = 300;

const problem = (e: unknown) => (e instanceof ApiError ? e.message : "Something went wrong. Try again.");

/**
 * A post's comments, live, with replies one level deep under each one.
 * Members comment, reply, like, and edit or delete their own (the post's
 * author may delete any). Enter sends; Shift+Enter adds a line.
 */
export function Comments({ postId, postAuthorId, autoFocus = false }: {
  postId: string;
  postAuthorId?: string;
  autoFocus?: boolean;
}) {
  const { user } = useAuth();
  const { data, error } = useLiveQuery<Comment>(
    user ? `posts/${postId}/comments` : null,
    [orderBy("createdAt", "asc"), limit(shown)],
    `comments-${postId}`,
  );
  const [replyTo, setReplyTo] = useState<Doc<Comment> | null>(null);

  if (user === undefined) return null;
  if (!user) {
    return (
      <p className="muted small comments-join">
        <Link href="/sign-up">Sign up</Link> or <Link href="/sign-in">log in</Link> to read and write comments.
      </p>
    );
  }
  const all = data ?? [];
  const top = all.filter((c) => !c.parentId);
  const replies = (id: string) => all.filter((c) => c.parentId === id);

  return (
    <section className="comments" aria-label="Comments">
      {error && <p className="form-error">{error}</p>}
      {data === undefined && !error && <p className="muted small">Loading comments…</p>}
      {top.map((c) => (
        <div key={c.id} className="comment-thread">
          <CommentRow comment={c} postId={postId} postAuthorId={postAuthorId} onReply={() => setReplyTo(c)} />
          {replies(c.id).map((r) => (
            <CommentRow
              key={r.id}
              comment={r}
              postId={postId}
              postAuthorId={postAuthorId}
              reply
              onReply={() => setReplyTo(r)}
            />
          ))}
          {replyTo && (replyTo.id === c.id || replyTo.parentId === c.id) && (
            <CommentBox
              postId={postId}
              replyTo={replyTo}
              autoFocus
              onDone={() => setReplyTo(null)}
              onCancel={() => setReplyTo(null)}
            />
          )}
        </div>
      ))}
      <CommentBox postId={postId} autoFocus={autoFocus} />
    </section>
  );
}

function CommentRow({
  comment: c,
  postId,
  postAuthorId,
  reply = false,
  onReply,
}: {
  comment: Doc<Comment>;
  postId: string;
  postAuthorId?: string;
  reply?: boolean;
  onReply: () => void;
}) {
  const { user } = useAuth();
  const [editing, setEditing] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  if (!user) return null;
  const me = user;
  const mine = c.authorId === me.uid;
  const liked = c.likedBy?.includes(me.uid) ?? false;
  const likes = c.likedBy?.length ?? 0;
  const path = `/v1/posts/${encodeURIComponent(postId)}/comments/${encodeURIComponent(c.id)}`;
  const name = c.authorName || "A player";

  async function run(fn: () => Promise<unknown>) {
    setBusy(true);
    setError(null);
    try {
      await fn();
    } catch (e) {
      setError(problem(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className={`comment${reply ? " reply" : ""}`}>
      <Link href={`/players/${encodeURIComponent(c.authorId)}`} className="comment-avatar" tabIndex={-1}>
        <Avatar name={name} url={c.authorPhotoUrl ?? undefined} size={reply ? 28 : 34} />
      </Link>
      <div className="comment-main">
        <div className="comment-bubble">
          <Link href={`/players/${encodeURIComponent(c.authorId)}`} className="comment-author">
            {name}
          </Link>
          {editing ? (
            <CommentBox
              postId={postId}
              editing={c}
              autoFocus
              onDone={() => setEditing(false)}
              onCancel={() => setEditing(false)}
            />
          ) : (
            <p>
              {c.replyToName && <span className="comment-to">@{c.replyToName} </span>}
              {c.body}
            </p>
          )}
        </div>
        <div className="comment-meta">
          <LocalTime iso={c.createdAt} style="relative" />
          {c.editedAt && <span>edited</span>}
          <button
            type="button"
            className={liked ? "on" : ""}
            aria-pressed={liked}
            disabled={busy}
            onClick={() => void run(() => callApi<LikeResult>(me, `${path}/like`, { method: liked ? "DELETE" : "PUT" }))}
          >
            {liked ? "Liked" : "Like"}
            {likes > 0 ? ` · ${likes}` : ""}
          </button>
          <button type="button" onClick={onReply}>
            Reply
          </button>
          {mine && !editing && (
            <button type="button" onClick={() => setEditing(true)}>
              Edit
            </button>
          )}
          {(mine || postAuthorId === me.uid) && (
            <button
              type="button"
              disabled={busy}
              onClick={() => {
                if (confirm("Delete this comment?")) void run(() => callApi(me, path, { method: "DELETE" }));
              }}
            >
              Delete
            </button>
          )}
        </div>
        {error && <p className="post-error">{error}</p>}
      </div>
    </div>
  );
}

/** Writing a comment, a reply, or an edit of one. */
function CommentBox({
  postId,
  replyTo,
  editing,
  autoFocus = false,
  onDone,
  onCancel,
}: {
  postId: string;
  replyTo?: Doc<Comment>;
  editing?: Doc<Comment>;
  autoFocus?: boolean;
  onDone?: () => void;
  onCancel?: () => void;
}) {
  const { user } = useAuth();
  const [body, setBody] = useState(editing?.body ?? "");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const box = useRef<HTMLTextAreaElement>(null);
  if (!user) return null;
  const me = user;

  async function send(e?: FormEvent) {
    e?.preventDefault();
    const text = body.trim();
    if (!text || busy) return;
    setBusy(true);
    setError(null);
    const base = `/v1/posts/${encodeURIComponent(postId)}/comments`;
    try {
      if (editing) {
        await callApi(me, `${base}/${encodeURIComponent(editing.id)}`, { method: "PATCH", body: { body: text } });
      } else {
        await callApi<CommentResult>(me, base, {
          method: "POST",
          body: { body: text, ...(replyTo && { replyTo: replyTo.id }) },
        });
        setBody("");
      }
      onDone?.();
    } catch (err) {
      setError(problem(err));
    } finally {
      setBusy(false);
    }
  }

  return (
    <form className={`comment-box${replyTo ? " reply" : ""}`} onSubmit={(e) => void send(e)}>
      <textarea
        ref={box}
        value={body}
        rows={1}
        maxLength={commentBodyMax}
        autoFocus={autoFocus}
        aria-label={editing ? "Edit your comment" : replyTo ? `Reply to ${replyTo.authorName ?? "this comment"}` : "Write a comment"}
        placeholder={editing ? "" : replyTo ? `Reply to ${replyTo.authorName ?? "this comment"}` : "Write a comment"}
        onChange={(e) => {
          setBody(e.target.value);
          e.target.style.height = "auto";
          e.target.style.height = `${e.target.scrollHeight}px`;
        }}
        onKeyDown={(e) => {
          if (e.key === "Enter" && !e.shiftKey) {
            e.preventDefault();
            void send();
          }
          if (e.key === "Escape") onCancel?.();
        }}
      />
      <button className="btn btn-primary btn-small" type="submit" disabled={busy || !body.trim()}>
        {editing ? "Save" : replyTo ? "Reply" : "Comment"}
      </button>
      {onCancel && (
        <button className="btn btn-small" type="button" onClick={onCancel}>
          Cancel
        </button>
      )}
      {error && <p className="post-error">{error}</p>}
    </form>
  );
}
