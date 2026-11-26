"use client";
import { webParent, webRoute } from "@stall10/shared";
import { limit, orderBy, where } from "firebase/firestore";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useMemo, useState } from "react";
import { callApi } from "@/lib/client";
import { type Doc, useLiveQuery } from "@/lib/live";
import { useAuth } from "./AuthProvider";
import { Avatar } from "./Avatar";
import { FollowButton } from "./FollowButton";
import { LocalTime } from "./LocalTime";
import "./member.css";
import { Button } from "./ui/Button";

/** A notification as the functions write it (AppNotification in the app). */
interface Notice {
  category?: string;
  title?: string;
  body?: string;
  route?: string | null;
  createdAt?: string;
  read?: boolean;
  count?: number;
  /** What a folded entry counts: likes, comments, repost, … */
  itemKind?: string;
  followBack?: { uid: string; name?: string; photoUrl?: string | null };
}

const shown = 100;

/** Today's notifications, then earlier ones (the app's Today / Earlier groups). */
function byDay<T extends { createdAt?: string }>(list: T[]): Array<[string, T[]]> {
  const start = new Date();
  start.setHours(0, 0, 0, 0);
  const today = list.filter((n) => Date.parse(n.createdAt ?? "") >= start.getTime());
  const earlier = list.filter((n) => !(Date.parse(n.createdAt ?? "") >= start.getTime()));
  return (
    [
      ["Today", today],
      ["Earlier", earlier],
    ] as Array<[string, T[]]>
  ).filter(([, l]) => l.length > 0);
}

const filters = [
  ["all", "All"],
  ["social", "People"],
  ["posts", "Posts"],
  ["team", "Teams and events"],
] as const;
type Filter = (typeof filters)[number][0];

/**
 * Messages (team chat and direct) push and show in Chats with its unread
 * bubbles, never here; older entries from before are hidden too
 * (NotificationCategory.isMessages in the app).
 */
const isMessages = (n: Notice) => n.category === "chat" || n.category === "directMessages";

function inFilter(n: Notice, f: Filter) {
  if (isMessages(n)) return false;
  const c = n.category ?? "teamActivity";
  switch (f) {
    case "all":
      return true;
    case "social":
      return c === "social";
    case "posts":
      return c === "posts";
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
  return data?.filter((n) => !isMessages(n)).length ?? 0;
}

/**
 * The notification feed, live: filter by kind, open one (marked read; it
 * stays, in lighter type, until cleared), mark everything shown read, or
 * clear it. Follow requests sit at the top. New followers can be followed
 * back from here.
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
  const requests = useLiveQuery<{ name?: string }>(
    user ? `profiles/${user.uid}/followRequests` : null,
    [limit(100)],
    "requests",
  );
  const waiting = requests.data?.length ?? 0;

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
        <button type="button" className="text-btn notice-mark" disabled={unread.length === 0} onClick={() => void mark(unread.map((n) => n.id))}>
          Mark all read
        </button>
        <Button
          size="small"
          disabled={list.length === 0}
          onClick={() => {
            if (confirm("Clear these notifications?")) void clear(list.map((n) => n.id));
          }}
        >
          Clear
        </Button>
      </div>

      {/* Follow requests waiting are the member's to do: their own group, in amber. */}
      <section className={`notice-group${waiting > 0 ? " needs" : ""}`} aria-labelledby="notice-group-requests">
        <h2 className="notice-group-head" id="notice-group-requests">
          {waiting > 0 ? "Needs you" : "Requests"}
        </h2>
        <Link href="/notifications/requests" className={`notice notice-requests${waiting > 0 ? " unread" : ""}`}>
          <span className="notice-icon notice-icon-person" aria-hidden="true">
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round">
              {iconPaths.person.map((d) => (
                <path key={d} d={d} />
              ))}
            </svg>
          </span>
          <span className="notice-dot" aria-hidden="true" />
          <span className="notice-main">
            <b>Follow requests</b>
            <span className="notice-body">{waiting === 0 ? "None waiting" : `${waiting} waiting for an answer`}</span>
          </span>
          {waiting > 0 && <span className="pill">{waiting}</span>}
          <span className="notice-chevron" aria-hidden="true">
            ›
          </span>
        </Link>
      </section>

      {error && <p className="form-error">{error}</p>}
      {data === undefined && !error && <p className="muted">Loading…</p>}
      {data && list.length === 0 && <p className="empty">You're all caught up.</p>}
      {byDay(list).map(([day, items]) => (
        <section key={day} className="notice-group" aria-label={day}>
          <h2 className="notice-group-head">{day}</h2>
          <ul className="notice-list">
            {items.map((n) => (
              <NoticeRow key={n.id} n={n} onOpen={() => !n.read && void mark([n.id])} onClear={() => void clear([n.id])} />
            ))}
          </ul>
        </section>
      ))}
    </div>
  );
}

/** What happened: the item kind, else the collapse id's prefix (`dm_…`, `likes_…`); AppNotification.kind in the app. */
function kindOf(n: Doc<Notice>): string {
  if (n.itemKind) return n.itemKind;
  const i = n.id.indexOf("_");
  return i > 0 ? n.id.slice(0, i) : n.id;
}

// Feather-style strokes (24×24) for each kind, as noticeIcon in the app.
const iconPaths: Record<string, string[]> = {
  heart: ["M20.8 4.6a5.5 5.5 0 0 0-7.8 0L12 5.7l-1-1.1a5.5 5.5 0 0 0-7.8 7.8l1 1.1L12 21l7.8-7.5 1-1.1a5.5 5.5 0 0 0 0-7.8z"],
  repeat: ["M17 1l4 4-4 4", "M3 11V9a4 4 0 0 1 4-4h14", "M7 23l-4-4 4-4", "M21 13v2a4 4 0 0 1-4 4H3"],
  comment: ["M21 11.5a8.4 8.4 0 0 1-9 8.4 8.6 8.6 0 0 1-3.9-.9L3 21l1.9-5.1A8.4 8.4 0 1 1 21 11.5z"],
  person: ["M16 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2", "M8.5 3a4 4 0 1 0 0 8 4 4 0 0 0 0-8z", "M20 8v6", "M23 11h-6"],
  at: ["M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8z", "M16 8v5a3 3 0 0 0 6 0v-1a10 10 0 1 0-3.9 7.9"],
  chat: ["M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"],
  video: ["M23 7l-7 5 7 5V7z", "M3 5h11a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2z"],
  calendar: ["M5 4h14a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2z", "M16 2v4", "M8 2v4", "M3 10h18"],
  alarm: ["M12 5a8 8 0 1 0 0 16 8 8 0 0 0 0-16z", "M12 9v4l2 2", "M5 3L2 6", "M22 6l-3-3"],
  group: ["M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2", "M9 3a4 4 0 1 0 0 8 4 4 0 0 0 0-8z", "M23 21v-2a4 4 0 0 0-3-3.9", "M16 3.1a4 4 0 0 1 0 7.8"],
  feed: ["M4 11a9 9 0 0 1 9 9", "M4 4a16 16 0 0 1 16 16", "M5 19a1 1 0 1 0 0 .01"],
  bell: ["M18 8a6 6 0 0 0-12 0c0 7-3 9-3 9h18s-3-2-3-9", "M13.7 21a2 2 0 0 1-3.4 0"],
};

function iconFor(n: Doc<Notice>): string {
  switch (kindOf(n)) {
    case "likes":
    case "commentLikes":
      return "heart";
    case "repost":
      return "repeat";
    case "comments":
    case "replies":
    case "videoComments":
      return "comment";
    case "follower":
    case "followRequests":
      return "person";
    case "mention":
      return "at";
    case "chat":
    case "dm":
    case "dmRequests":
      return "chat";
    case "meeting":
    case "meetingStarted":
      return "video";
    case "event":
    case "schedule":
    case "calendarInvite":
      return "calendar";
    case "deadline":
      return "alarm";
    case "invite":
    case "teamInvite":
    case "joinRequest":
    case "joinApproved":
      return "group";
    case "posts":
      return "feed";
  }
  switch (n.category) {
    case "chat":
    case "directMessages":
      return "chat";
    case "eventChanges":
      return "calendar";
    case "eventReminders":
      return "alarm";
    case "meetings":
      return "video";
    case "posts":
      return "feed";
    case "social":
      return "heart";
    default:
      return "bell";
  }
}

function NoticeIcon({ n }: { n: Doc<Notice> }) {
  const name = iconFor(n);
  return (
    <span className={`notice-icon notice-icon-${name}`} aria-hidden="true">
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round">
        {iconPaths[name].map((d) => (
          <path key={d} d={d} />
        ))}
      </svg>
    </span>
  );
}

function NoticeRow({ n, onOpen, onClear }: { n: Doc<Notice>; onOpen: () => void; onClear: () => void }) {
  const to = href(n);
  const router = useRouter();
  // Back from the page goes to the page it belongs under (a team chat to
  // its team, a conversation to Chats), not back here: this list's place
  // in the history becomes that page (openFromNotifications in the app).
  const parent = to ? webParent(to) : null;
  const title = (
    <>
      <span className="notice-title">
        <b>{n.title || "Stall 10"}</b>
        {n.count && n.count > 1 ? <span className="pill">{n.count}</span> : null}
      </span>
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
        <NoticeIcon n={n} />
      )}
      <span className="notice-dot" aria-hidden="true" />
      {to ? (
        <Link
          href={to}
          className="notice-main"
          onClick={(e) => {
            onOpen();
            if (!parent || e.metaKey || e.ctrlKey || e.shiftKey || e.button !== 0) return;
            e.preventDefault();
            // The list's history entry becomes the parent, then the page
            // opens over it (Next syncs with the native history calls).
            window.history.replaceState(window.history.state, "", parent);
            router.push(to);
          }}
        >
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
