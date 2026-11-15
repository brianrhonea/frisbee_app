"use client";
import { limit, where } from "firebase/firestore";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useMemo, useState } from "react";
import { callApi } from "@/lib/client";
import { useLiveQuery } from "@/lib/live";
import { useAuth } from "../../AuthProvider";
import { roomHref } from "./model";

/** Feed ids of these notices start with this (notifications/model.ts). */
const idPrefix = "meetingStarted_";
/** Notices older than this when they arrive aren't news any more. */
const maxAgeMs = 30 * 60_000;

interface Notice {
  title?: string;
  body?: string;
  route?: string | null;
  createdAt?: string;
  read?: boolean;
}

/** The app route `/team-meetings/:teamId/:meetingId/room` as the site's room page. */
export function meetingRoute(route: string | null | undefined): { teamId: string; meetingId: string; href: string } | null {
  const m = /^\/team-meetings\/([^/]+)\/([^/]+)(?:\/room)?$/.exec(route ?? "");
  if (!m) return null;
  const [teamId, meetingId] = [decodeURIComponent(m[1]!), decodeURIComponent(m[2]!)];
  return { teamId, meetingId, href: roomHref(teamId, meetingId) };
}

/**
 * "Meeting started" pop-ups while the site is open (MeetingAlertsViewModel):
 * from the in-app feed, which the meetingStarted function writes for
 * invitees attending, so notification settings apply. Only notices that
 * arrive after the page opened and are under 30 minutes old, each once,
 * and none for the room already open.
 */
export function MeetingAlerts() {
  const { user } = useAuth();
  const path = usePathname();
  const [since] = useState(() => Date.now());
  const [shown, setShown] = useState<Set<string>>(() => new Set());
  const feed = useLiveQuery<Notice>(user ? `users/${user.uid}/notifications` : null, [where("read", "==", false), limit(50)], "meeting-alerts");
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => setNow(Date.now()), [feed.data]);

  const alert = useMemo(() => {
    for (const n of feed.data ?? []) {
      const at = n.createdAt ? Date.parse(n.createdAt) : Number.NaN;
      if (n.read || !n.id.startsWith(idPrefix) || Number.isNaN(at) || at < since || now - at > maxAgeMs) continue;
      if (shown.has(`${n.id}@${at}`)) continue;
      const target = meetingRoute(n.route);
      if (target && path === target.href) continue;
      return { n, at, target };
    }
    return null;
  }, [feed.data, since, now, shown, path]);

  if (!alert || !user) return null;
  const dismiss = () => setShown((s) => new Set(s).add(`${alert.n.id}@${alert.at}`));
  return (
    <div className="card meeting-alert" role="status">
      <p>
        <b>{alert.n.title || "A meeting has started"}</b>
        {alert.n.body && <span className="muted small"> {alert.n.body}</span>}
      </p>
      <div className="home-actions">
        {alert.target && (
          <Link
            className="btn btn-primary btn-small"
            href={alert.target.href}
            onClick={() => {
              dismiss();
              void callApi(user, "/v1/me/notifications/read", { method: "POST", body: { ids: [alert.n.id] } }).catch(() => undefined);
            }}
          >
            Join
          </Link>
        )}
        <button type="button" className="text-btn" onClick={dismiss}>
          Dismiss
        </button>
      </div>
    </div>
  );
}
