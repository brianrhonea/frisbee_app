"use client";
// Infinite scroll for Home's feeds (Dashboard, ForYou) and the community
// page (MoreFeed): a sentinel under the list loads the next page as it
// nears the screen. A page that adds nothing shown (For you's sources can
// page without moving its cutoff) is re-checked when it lands; after a few
// of those in a row, or a failed page, or without IntersectionObserver, an
// "Older posts" button takes over.
import { useCallback, useEffect, useRef, useState } from "react";

/** Pages in a row that showed nothing new before handing over to the button. */
const maxEmptyPages = 3;

export interface InfiniteFeed {
  /** More on the server. */
  hasMore: boolean;
  /** A page is loading. */
  busy: boolean;
  /** The last page failed. */
  error: boolean;
  /** Items shown, so a page that adds none can be told apart. */
  count: number;
  loadMore: () => void | Promise<void>;
}

export function useInfiniteFeed({ hasMore, busy, error, count, loadMore }: InfiniteFeed) {
  const [node, setNode] = useState<HTMLElement | null>(null);
  const [near, setNear] = useState(false);
  const [supported, setSupported] = useState(false);
  const [empty, setEmpty] = useState(0);
  const load = useRef(loadMore);
  load.current = loadMore;
  const before = useRef<number | null>(null);

  useEffect(() => {
    if (!node || typeof IntersectionObserver === "undefined") return;
    setSupported(true);
    const io = new IntersectionObserver((entries) => setNear(entries.some((e) => e.isIntersecting)), { rootMargin: "0px 0px 600px 0px" });
    io.observe(node);
    return () => io.disconnect();
  }, [node]);

  // A page landed: did it show anything?
  useEffect(() => {
    if (busy || before.current === null) return;
    setEmpty((n) => (count > before.current! ? 0 : n + 1));
    before.current = null;
  }, [busy, count]);

  const auto = supported && !error && empty < maxEmptyPages;
  useEffect(() => {
    if (!auto || !near || !hasMore || busy) return;
    before.current = count;
    void load.current();
    // eslint-disable-next-line react-hooks/exhaustive-deps -- count is read when a page starts, not a reason to start one.
  }, [auto, near, hasMore, busy]);

  /** The button: also clears a stall, so scrolling loads again after it. */
  const more = useCallback(() => {
    setEmpty(0);
    before.current = count;
    void load.current();
  }, [count]);

  return { sentinel: setNode, auto, more };
}

/**
 * The end of a feed: the sentinel, then "Loading…", the "Older posts"
 * button when scrolling doesn't load, or "You're all caught up."
 */
export function FeedPager(feed: InfiniteFeed & { errorText?: string }) {
  const { sentinel, auto, more } = useInfiniteFeed(feed);
  return (
    <nav className="pager feed-pager" aria-label="Older posts">
      <span ref={sentinel} className="feed-sentinel" aria-hidden="true" />
      {!feed.hasMore ? (
        <p className="empty">You&apos;re all caught up.</p>
      ) : auto ? (
        <p className="muted small" aria-live="polite">
          {feed.busy ? "Loading more posts…" : ""}
        </p>
      ) : (
        <button className="btn" type="button" disabled={feed.busy} onClick={more}>
          {feed.busy ? "Loading…" : "Older posts"}
        </button>
      )}
      {feed.error && <p className="post-error">{feed.errorText ?? "Couldn't load more posts. Try again."}</p>}
    </nav>
  );
}
