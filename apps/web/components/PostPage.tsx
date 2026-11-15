"use client";
import type { PublicPost } from "@stall10/shared";
import Link from "next/link";
import { useEffect, useState } from "react";
import { ApiError, callApi, problem } from "@/lib/client";
import { type Signal, useChangeSignal } from "@/lib/live";
import { appScheme } from "@/lib/site";
import { useAuth } from "./AuthProvider";
import { PostCard } from "./PostCard";

/**
 * One post on its own page. Visitors get the cached public copy
 * ([initial]; null when its author is private). Members get it as they
 * may see it (`/v1/posts/:id`), refetched whenever it (or a repost's
 * original) changes: edits and counts show within a moment, and a
 * deleted post says so.
 */
export function LivePost({ postId, initial }: { postId: string; initial: PublicPost | null }) {
  const { user } = useAuth();
  const [post, setPost] = useState<PublicPost | null>(null);
  const [gone, setGone] = useState<string | null>(null);
  const [failed, setFailed] = useState<string | null>(null);
  const [attempt, setAttempt] = useState(0);
  const originalId = (post ?? initial)?.repostOf?.postId;
  const signals: Signal[] | null = user
    ? [{ doc: `posts/${postId}` }, ...(originalId ? [{ doc: `posts/${originalId}` }] : [])]
    : null;
  const version = useChangeSignal(signals, user ? `${user.uid}|${postId}|${originalId ?? ""}` : "");

  useEffect(() => {
    if (!user) {
      // Signed out: only the public copy, never a member-only post.
      setPost(null);
      setGone(null);
      setFailed(null);
      return;
    }
    let live = true;
    const timer = setTimeout(() => {
      callApi<PublicPost>(user, `/v1/posts/${encodeURIComponent(postId)}`).then(
        (p) => {
          if (!live) return;
          setPost(p);
          setGone(null);
          setFailed(null);
        },
        (e) => {
          if (!live) return;
          // Not "No such endpoint." (an API from before this route): keep the public copy.
          if (e instanceof ApiError && e.status === 404 && e.message !== "No such endpoint.") setGone(e.message);
          else setFailed(problem(e, "Couldn't load this post. Check your connection and try again."));
        },
      );
    }, 150);
    return () => {
      live = false;
      clearTimeout(timer);
    };
  }, [user, postId, version, attempt]);

  if (gone) return <Unavailable text={gone} />;
  const shown = post ?? initial;
  if (shown) {
    return (
      <>
        <PostCard post={shown} standalone />
        {user === null && <OpenInAppCard postId={postId} />}
      </>
    );
  }
  if (user && failed) {
    return (
      <Unavailable text={failed}>
        <button
          type="button"
          className="btn btn-small"
          onClick={() => {
            setFailed(null);
            setAttempt((n) => n + 1);
          }}
        >
          Try again
        </button>
      </Unavailable>
    );
  }
  if (user === undefined || user) return <p className="muted">Loading…</p>;
  return (
    <Unavailable text="This post isn't public.">
      <Link href={`/sign-in?next=${encodeURIComponent(`/posts/${postId}`)}`}>Log in</Link> to see it if its author
      approved you.
    </Unavailable>
  );
}

/** Visitors can't read the replies here; members see them under the post. */
function OpenInAppCard({ postId }: { postId: string }) {
  return (
    <div className="cta-card">
      <p>See the replies in the Stall 10 app.</p>
      <a className="btn btn-primary btn-small" href={`${appScheme}://open/p/${encodeURIComponent(postId)}`}>
        Open in the app
      </a>
    </div>
  );
}

function Unavailable({ text, children }: { text: string; children?: React.ReactNode }) {
  return (
    <div className="card">
      <h2 className="card-title">{text}</h2>
      {children && <p className="muted small">{children}</p>}
    </div>
  );
}
