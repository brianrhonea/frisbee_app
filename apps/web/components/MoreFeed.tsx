"use client";
import type { PostPage, PublicPost } from "@stall10/shared";
import { useState } from "react";
import { callApi } from "@/lib/client";
import { useAuth } from "./AuthProvider";
import { PostCard } from "./PostCard";

/**
 * Older community posts for members (`GET /v1/feed`), after the page the
 * server rendered; [before] is that page's last post time (ms).
 */
export function MoreFeed({ before }: { before: number | null }) {
  const { user } = useAuth();
  const [posts, setPosts] = useState<PublicPost[]>([]);
  const [next, setNext] = useState(before);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(false);

  if (!user) return null;

  async function load() {
    if (!user || next === null) return;
    setBusy(true);
    setError(false);
    try {
      const page = await callApi<PostPage>(user, `/v1/feed?before=${next}`);
      setPosts((p) => [...p, ...page.posts.filter((x) => !p.some((y) => y.id === x.id))]);
      setNext(page.next);
    } catch {
      setError(true);
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      {posts.length > 0 && (
        <div className="stack">
          {posts.map((p) => (
            <PostCard key={p.id} post={p} />
          ))}
        </div>
      )}
      <div className="pager">
        {next === null ? (
          <p className="empty">You&apos;re all caught up.</p>
        ) : (
          <button className="btn" type="button" disabled={busy} onClick={() => void load()}>
            {busy ? "Loading…" : "Older posts"}
          </button>
        )}
        {error && <p className="post-error">Couldn&apos;t load more posts. Try again.</p>}
      </div>
    </>
  );
}
