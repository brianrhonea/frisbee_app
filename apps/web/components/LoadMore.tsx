"use client";

/** "Show more" under a list read a page at a time (useLivePaged); nothing once it's all there. */
export function LoadMore({ paged, label = "Show more" }: { paged: { more: boolean; loadingMore: boolean; loadMore: () => void }; label?: string }) {
  if (!paged.more) return null;
  return (
    <div className="pager">
      <button type="button" className="btn btn-small" disabled={paged.loadingMore} onClick={paged.loadMore}>
        {paged.loadingMore ? "Loading…" : label}
      </button>
    </div>
  );
}
