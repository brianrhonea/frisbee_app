"use client";
import type { UIEvent } from "react";
import type { PagedMessages } from "@/lib/messages";
import "./chat_attachments.css";

/** How near the top (px) a thread's scroll loads the next page by itself. */
const nearTop = 48;

/** A thread body's onScroll: loads older messages on reaching the top, as the app does. */
export function loadAtTop(paged: PagedMessages<unknown>) {
  return (e: UIEvent<HTMLElement>) => {
    if (e.currentTarget.scrollTop <= nearTop && paged.hasMore && paged.autoLoad) void paged.loadOlder();
  };
}

/** "Load older messages" above a thread's first message, while there may be more. */
export function OlderMessages({ paged }: { paged: PagedMessages<unknown> }) {
  if (!paged.hasMore) return null;
  return (
    <p className="thread-older">
      <button type="button" className="text-btn" disabled={paged.loadingMore} onClick={() => void paged.loadOlder()}>
        {paged.loadingMore ? "Loading…" : "Load older messages"}
      </button>
    </p>
  );
}
