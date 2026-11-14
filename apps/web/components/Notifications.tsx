"use client";
import { webRoute } from "@stall10/shared";
import { limit, orderBy, where } from "firebase/firestore";
import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { callApi } from "@/lib/client";
import { type Doc, useLiveQuery } from "@/lib/live";
import { useAuth } from "./AuthProvider";
import { Avatar } from "./Avatar";
import { FollowButton } from "./FollowButton";
import { LocalTime } from "./LocalTime";

/** A notification as the functions write it (AppNotification in the app). */
interface Notice {
  category?: string;
  title?: string;
  body?: string;
  route?: string | null;
  createdAt?: string;
  read?: boolean;
  count?: number;
  followBack?: { uid: string; name?: string; photoUrl?: string | null };
}

const shown = 100;

const filters = [
  ["all", "All"],
  ["social", "People"],
  ["posts", "Posts"],
  ["team", "Teams and events"],
  ["messages", "Messages"],
] as const;
type Filter = (typeof filters)[number][0];

function inFilter(n: Notice, f: Filter) {
  const c = n.category ?? "teamActivity";
  switch (f) {
    case "all":
      return true;
    case "social":
      return c === "social";
    case "posts":
      return c === "posts";
    case "messages":
      return c === "chat" || c === "directMessages";
    case "team":
      return ["teamActivity", "eventChanges", "eventReminders", "meetings"].includes(c);
  }
}

/** Where a notification goes on the website: the site's page for the app's route. */
function href(n: Notice): string | null {
  return webRoute(n.route);
}

/** The member's unread notifications, for the sidebar badge. */
export function useUnreadCount(): number {
  const { user } = useAuth();
  const { data } = useLiveQuery<Notice>(
    user ? `users/${user.uid}/notifications` : null,
    [where("read", "==", false), limit(100)],
    "unread",
  );
  return data?.length ?? 0;
}

/**
 * The notification feed, live: filter by kind, open one (marked read as
 * you go), mark everything shown read, or clear it. New followers can be
 * followed back from here.
 */
export function Notifications() {
  const { user } = useAuth();
  const { data, error } = useLiveQuery<Notice>(
    user ? `users/${user.uid}/notifications` : null,
    [orderBy("createdAt", "desc"), limit(shown)],
    "notifications",
  );
  const [filter, setFilter] = useState<Filter>("all");
  const list = useMemo(() => (data ?? []).filter((n) => inFilter(n, filter)), [data, filter]);
  const unread = list.filter((n) => !n.read);

  // Opening the page shows what's new; it's marked read after a moment.
  useEffect(() => {
    if (!user || unread.length === 0) return;
    const t = setTimeout(() => void mark(unread.map((n) => n.id)), 2500);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps -- re-run when the unread set changes
  }, [user, unread.map((n) => n.id).join(",")]);

  if (!user) return null;
  const me = user;

  async function mark(ids: string[]) {
    for (let i = 0; i < ids.length; i += 100) {
      await callApi(me, "/v1/me/notifications/read", { method: "POST", body: { ids: ids.slice(i, i + 100) } }).catch(
        () => undefined,
      );
    }
  }
  async function clear(ids: string[]) {
    for (let i = 0; i < ids.length; i += 100) {
      await callApi(me, "/v1/me/notifications/delete", { method: "POST", body: { ids: ids.slice(i, i + 100) } }).catch(
        () => undefined,
      );
    }
  }

  return (
    <div className="notifications">
      <div className="toolbar">
        <div className="segmented" role="tablist" aria-label="Show">
          {filters.map(([f, label]) => (
            <button
              key={f}
              type="button"
              role="tab"
              aria-selected={filter === f}
              className={filter === f ? "on" : ""}
              onClick={() => setFilter(f)}
            >
              {label}
            </button>
          ))}
        </div>
        <span className="composer-spacer" />
        <button
          type="button"
          className="btn btn-small"
          disabled={list.length === 0}
          onClick={() => {
            if (confirm("Clear these notifications?")) void clear(list.map((n) => n.id));
          }}
        >
          Clear
        </button>
      </div>

      {error && <p className="form-error">{error}</p>}
      {data === undefined && !error && <p className="muted">Loading…</p>}
      {data && list.length === 0 && <p className="empty">You're all caught up.</p>}
      <ul className="notice-list">
        {list.map((n) => (
          <NoticeRow key={n.id} n={n} onOpen={() => !n.read && void mark([n.id])} onClear={() => void clear([n.id])} />
        ))}
      </ul>
    </div>
  );
}

function NoticeRow({ n, onOpen, onClear }: { n: Doc<Notice>; onOpen: () => void; onClear: () => void }) {
  const to = href(n);
  const title = (
    <>
      <b>{n.title || "Stall 10"}</b>
      {n.count && n.count > 1 ? <span className="pill">{n.count}</span> : null}
      {n.body && <span className="notice-body">{n.body}</span>}
      <small>
        <LocalTime iso={n.createdAt} style="relative" />
      </small>
    </>
  );
  return (
    <li className={`notice${n.read ? "" : " unread"}`}>
      {n.followBack ? (
        <Avatar name={n.followBack.name || "Player"} url={n.followBack.photoUrl ?? undefined} size={38} />
      ) : (
        <span className="notice-dot" aria-hidden="true" />
      )}
      {to ? (
        <Link href={to} className="notice-main" onClick={onOpen}>
          {title}
        </Link>
      ) : (
        <div className="notice-main">{title}</div>
      )}
      {n.followBack && <FollowButton targetId={n.followBack.uid} />}
      <button type="button" className="icon-btn" aria-label="Clear" title="Clear" onClick={onClear}>
        ×
      </button>
    </li>
  );
}
