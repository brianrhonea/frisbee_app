"use client";
import type { PublicPost } from "@stall10/shared";
import Link from "next/link";
import { useEffect, useState } from "react";
import { ApiError, callApi } from "@/lib/client";
import { type Signal, useChangeSignal } from "@/lib/live";
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
      return;
    }
    let live = true;
    const timer = setTimeout(() => {
      callApi<PublicPost>(user, `/v1/posts/${encodeURIComponent(postId)}`).then(
        (p) => {
          if (!live) return;
          setPost(p);
          setGone(null);
        },
        (e) => {
          // Not "No such endpoint." (an API from before this route): keep the public copy.
          if (live && e instanceof ApiError && e.status === 404 && e.message !== "No such endpoint.") setGone(e.message);
        },
      );
    }, 150);
    return () => {
      live = false;
      clearTimeout(timer);
    };
  }, [user, postId, version]);

  if (gone) return <Unavailable text={gone} />;
  const shown = post ?? initial;
  if (shown) return <PostCard post={shown} standalone />;
  if (user === undefined || user) return <p className="muted">Loading…</p>;
  return (
    <Unavailable text="This post isn't public.">
      <Link href={`/sign-in?next=${encodeURIComponent(`/posts/${postId}`)}`}>Log in</Link> to see it if its author
      approved you.
    </Unavailable>
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
