"use client";
import { teamPostCommentLimits } from "@stall10/shared";
import { limit, orderBy } from "firebase/firestore";
import Link from "next/link";
import { type FormEvent, useState } from "react";
import { callApi, problem } from "@/lib/client";
import { useLiveQuery } from "@/lib/live";
import { useAuth } from "../AuthProvider";
import { Avatar } from "../Avatar";
import { LocalTime } from "../LocalTime";
import { ReportButton } from "../Report";
import { useConfirm } from "@/components/ui/ConfirmDialog";
import { ErrorNote } from "@/components/StatusViews";

/** A comment on a team post as stored (TeamPostComment in the app). */
interface TeamPostComment {
  authorId: string;
  authorName?: string;
  body: string;
  createdAt?: string;
}

/**
 * A team post's comments (redesign F24), live, oldest first (the newest
 * 100), with a box to add one. Members only; written through the API. Its
 * author or a team admin ([moderator]) deletes a comment.
 */
export function TeamPostComments({ teamId, postId, moderator }: { teamId: string; postId: string; moderator: boolean }) {
  const askConfirm = useConfirm();
  const { user } = useAuth();
  const { data, error } = useLiveQuery<TeamPostComment>(
    user ? `teams/${teamId}/posts/${postId}/comments` : null,
    [orderBy("createdAt", "desc"), limit(teamPostCommentLimits.shown)],
    `team-post-comments-${teamId}-${postId}`,
  );
  const [body, setBody] = useState("");
  const [busy, setBusy] = useState(false);
  const [problemText, setProblem] = useState<string | null>(null);
  if (!user) return null;
  const me = user;
  const base = `/v1/teams/${encodeURIComponent(teamId)}/posts/${encodeURIComponent(postId)}/comments`;

  async function run(fn: () => Promise<unknown>) {
    setBusy(true);
    setProblem(null);
    try {
      await fn();
      return true;
    } catch (e) {
      setProblem(problem(e));
      return false;
    } finally {
      setBusy(false);
    }
  }

  async function send(e?: FormEvent) {
    e?.preventDefault();
    const text = body.trim();
    if (!text || busy) return;
    if (await run(() => callApi(me, base, { method: "POST", body: { body: text } }))) setBody("");
  }

  const all = [...(data ?? [])].reverse();
  return (
    <section className="comments" aria-label="Comments">
      {error && <ErrorNote>{error}</ErrorNote>}
      {data === undefined && !error && <p className="muted small">Loading comments…</p>}
      {data !== undefined && all.length === 0 && <p className="muted small">No comments yet.</p>}
      {all.map((c) => {
        const name = c.authorName || "Member";
        return (
          <div key={c.id} className="comment">
            <Link href={`/players/${encodeURIComponent(c.authorId)}`} className="comment-avatar" tabIndex={-1}>
              <Avatar name={name} size={34} />
            </Link>
            <div className="comment-main">
              <div className="comment-bubble">
                <Link href={`/players/${encodeURIComponent(c.authorId)}`} className="comment-author">
                  {name}
                </Link>
                <p>{c.body}</p>
              </div>
              <div className="comment-meta">
                <LocalTime iso={c.createdAt} style="relative" />
                {c.authorId !== me.uid && (
                  <ReportButton
                    className=""
                    target={{ kind: "teamPostComment", teamId, postId, commentId: c.id }}
                    authorName={c.authorName || "this player"}
                  />
                )}
                {(c.authorId === me.uid || moderator) && (
                  <button
                    type="button"
                    disabled={busy}
                    onClick={async () => {
                      if ((await askConfirm({ message: "Delete this comment?", confirmLabel: "Delete", destructive: true }))) void run(() => callApi(me, `${base}/${encodeURIComponent(c.id)}`, { method: "DELETE" }));
                    }}
                  >
                    Delete
                  </button>
                )}
              </div>
            </div>
          </div>
        );
      })}
      <form className="comment-box" onSubmit={(e) => void send(e)}>
        <textarea
          value={body}
          rows={1}
          maxLength={teamPostCommentLimits.body}
          aria-label="Write a comment"
          placeholder="Write a comment"
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
          }}
        />
        <button className="btn btn-primary btn-small" type="submit" disabled={busy || !body.trim()}>
          Comment
        </button>
      </form>
      {problemText && <p className="post-error">{problemText}</p>}
    </section>
  );
}
